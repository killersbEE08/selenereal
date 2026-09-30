import { timingSafeEqual } from "node:crypto";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { defineSecret } from "firebase-functions/params";
import { logger } from "firebase-functions";
import { HttpsError, onCall, onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { enforceAppCheck, isEmulator, REGION } from "./config";
import { requireUid } from "./quota";

const REVENUECAT_WEBHOOK_AUTH = defineSecret("REVENUECAT_WEBHOOK_AUTH");
/** RevenueCat *secret* API key (v1, starts with sk_). Server-only; used by syncPremium. */
const REVENUECAT_API_KEY = defineSecret("REVENUECAT_API_KEY");

async function deleteUserData(uid: string) {
  const db = getFirestore();
  await db.recursiveDelete(db.doc(`users/${uid}`));
  await getStorage().bucket().deleteFiles({ prefix: `palms/${uid}/` }).catch(() => undefined);
  await getStorage().bucket().deleteFiles({ prefix: `shares/${uid}/` }).catch(() => undefined);
}

/** Deletes all of the caller's data and their Auth account (GDPR / DPDP / store requirement). */
export const deleteMyData = onCall({ region: REGION, enforceAppCheck }, async (req) => {
  const uid = requireUid(req, { allowUnverified: true });
  const { deleteAccount } = (req.data ?? {}) as { deleteAccount?: boolean };
  await deleteUserData(uid);
  if (deleteAccount === true) await getAuth().deleteUser(uid);
  return { ok: true };
});

/** Deletes only the stored palm photos. */
export const deletePalmPhotos = onCall({ region: REGION, enforceAppCheck }, async (req) => {
  const uid = requireUid(req);
  await getStorage().bucket().deleteFiles({ prefix: `palms/${uid}/` }).catch(() => undefined);
  return { ok: true };
});

/** Removes palm photos older than 30 days for users who opted to keep them. */
export const cleanupPalmPhotos = onSchedule({ region: REGION, schedule: "30 3 * * *", timeZone: "UTC" }, async () => {
  const cutoff = Date.now() - 30 * 86400000;
  const [files] = await getStorage().bucket().getFiles({ prefix: "palms/" });
  let n = 0;
  for (const f of files) {
    if (new Date(String(f.metadata.timeCreated)).getTime() < cutoff) { await f.delete({ ignoreNotFound: true }); n++; }
  }
  logger.info("palm cleanup", { deleted: n });
});

export interface RcEvent {
  app_user_id?: string; original_app_user_id?: string; aliases?: string[]; transferred_to?: string[];
  type?: string; expiration_at_ms?: number | null; product_id?: string; entitlement_ids?: string[] | null; environment?: string;
}

const PREMIUM_ENTITLEMENT = "premium";
const FIREBASE_UID = /^[A-Za-z0-9]{20,40}$/;

/**
 * Decides premium state from a RevenueCat event. CANCELLATION only turns off auto-renew
 * (access continues until expiry), so it must NOT revoke; EXPIRATION does.
 */
export function premiumFromEvent(ev: RcEvent, now = Date.now()): { uid: string; active: boolean; expiresAt: number | null } | null {
  const uid = [ev.app_user_id, ev.original_app_user_id, ...(ev.aliases ?? [])].find((x) => x && FIREBASE_UID.test(x) && !x.startsWith("$RCAnonymousID"));
  if (!uid) return null;
  if (ev.type === "TEST") return null;
  if (ev.entitlement_ids && !ev.entitlement_ids.includes(PREMIUM_ENTITLEMENT)) return null;
  const exp = ev.expiration_at_ms ?? null;
  const notExpired = exp === null || exp > now;
  const active = ev.type === "EXPIRATION" ? false : notExpired;
  return { uid, active, expiresAt: exp };
}

/** RevenueCat webhook → premium entitlement (the only writer of users/{uid}.premium in production). */
export const revenueCatWebhook = onRequest({ region: REGION, secrets: [REVENUECAT_WEBHOOK_AUTH] }, async (req, res) => {
  const expected = Buffer.from(`Bearer ${REVENUECAT_WEBHOOK_AUTH.value()}`);
  const got = Buffer.from(String(req.headers.authorization ?? ""));
  if (req.method !== "POST" || got.length !== expected.length || !timingSafeEqual(got, expected)) { res.status(401).send("unauthorized"); return; }
  const ev = req.body?.event as RcEvent | undefined;
  if (!ev) { res.status(400).send("bad event"); return; }

  // Subscription moved to another account (restore on a new login): revoke from the old uids.
  if (ev.type === "TRANSFER") {
    for (const from of (req.body.event.transferred_from as string[] | undefined) ?? []) {
      if (FIREBASE_UID.test(from)) await getFirestore().doc(`users/${from}`).set({ premium: { active: false, event: "TRANSFER_OUT" } }, { merge: true });
    }
    const to = (ev.transferred_to ?? []).find((x) => FIREBASE_UID.test(x));
    if (to) ev.app_user_id = to;
  }

  const decision = premiumFromEvent(ev);
  if (!decision) { res.status(200).send("ignored"); return; } // ack so RevenueCat doesn't retry
  const ref = getFirestore().doc(`users/${decision.uid}`);
  const snap = await ref.get();
  if (!snap.exists) { res.status(200).send("unknown user"); return; }
  const cur = snap.data()?.premium as { active?: boolean; source?: string } | undefined;
  if (!decision.active && cur?.active && cur.source === "dodo") { res.status(200).send("kept web subscription"); return; }
  await ref.set({
    premium: {
      active: decision.active, plan: ev.product_id ?? null, event: ev.type ?? null, environment: ev.environment ?? null,
      expiresAt: decision.expiresAt ? Timestamp.fromMillis(decision.expiresAt) : null, updatedAt: Timestamp.now(),
    },
  }, { merge: true });
  logger.info("premium updated", { type: ev.type, active: decision.active, env: ev.environment });
  res.status(200).send("ok");
});

export interface RcEntitlement { expires_date?: string | null; grace_period_expires_date?: string | null; product_identifier?: string | null }

/**
 * Decides premium state from a RevenueCat v1 subscriber payload. A null expires_date means a
 * lifetime / non-expiring grant (e.g. a promotional entitlement granted in the dashboard).
 */
export function premiumFromSubscriber(body: unknown, now = Date.now()): { active: boolean; expiresAt: number | null; plan: string | null } {
  const ent = (body as { subscriber?: { entitlements?: Record<string, RcEntitlement> } })?.subscriber?.entitlements?.[PREMIUM_ENTITLEMENT];
  if (!ent) return { active: false, expiresAt: null, plan: null };
  const ms = (s?: string | null) => (s ? Date.parse(s) : NaN);
  const exp = ms(ent.expires_date);
  const grace = ms(ent.grace_period_expires_date);
  const until = Math.max(Number.isNaN(exp) ? -Infinity : exp, Number.isNaN(grace) ? -Infinity : grace);
  const lifetime = ent.expires_date == null;
  return { active: lifetime || until > now, expiresAt: lifetime ? null : until, plan: ent.product_identifier ?? null };
}

/**
 * Pulls the caller's entitlement straight from RevenueCat and writes it to Firestore.
 * The webhook remains the main writer, but it does not fire for every case (dashboard grants,
 * restores of an already-known purchase, a missed delivery), which left the paywall waiting
 * forever. The app calls this after purchase/restore and when the paywall opens.
 */
export const syncPremium = onCall({ region: REGION, enforceAppCheck, secrets: [REVENUECAT_API_KEY] }, async (req) => {
  const uid = requireUid(req);
  const key = REVENUECAT_API_KEY.value();
  if (!key) throw new HttpsError("failed-precondition", "Subscriptions are not configured yet.");
  let body: unknown;
  try {
    const r = await fetch(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(uid)}`, {
      headers: { Authorization: `Bearer ${key}`, Accept: "application/json" },
      signal: AbortSignal.timeout(10_000),
    });
    if (!r.ok) throw new Error(`RevenueCat ${r.status}`);
    body = await r.json();
  } catch (e) {
    logger.warn("syncPremium: RevenueCat lookup failed", { error: String(e) });
    throw new HttpsError("unavailable", "Could not reach the store. Please try again in a moment.");
  }
  const d = premiumFromSubscriber(body);
  const ref = getFirestore().doc(`users/${uid}`);
  const current = ((await ref.get()).data()?.premium ?? {}) as { active?: boolean; source?: string };
  // Only downgrade on an explicit "no entitlement" answer; never touch non-RevenueCat test grants in the emulator,
  // and never revoke a web (Dodo) subscription because the store has nothing.
  if (d.active || (current.active && current.source !== "dodo")) {
    await ref.set({
      premium: {
        active: d.active, plan: d.plan, event: "SYNC", source: "revenuecat_api",
        expiresAt: d.expiresAt ? Timestamp.fromMillis(d.expiresAt) : null, updatedAt: Timestamp.now(),
      },
    }, { merge: true });
  }
  logger.info("premium synced", { active: d.active });
  return { active: d.active, expiresAt: d.expiresAt };
});

/** Emulator-only helper so the paywall can be tested before store products exist. */
export const devSetPremium = onCall({ region: REGION }, async (req) => {
  if (!isEmulator()) throw new HttpsError("permission-denied", "Not available.");
  const uid = requireUid(req);
  const active = req.data?.active !== false;
  await getFirestore().doc(`users/${uid}`).set({
    premium: { active, plan: active ? "dev_yearly" : null, expiresAt: active ? Timestamp.fromMillis(Date.now() + 365 * 86400000) : null },
  }, { merge: true });
  return { active };
});
