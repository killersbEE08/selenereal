import { createHmac, timingSafeEqual } from "node:crypto";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { defineSecret, defineString } from "firebase-functions/params";
import { HttpsError, onCall, onRequest } from "firebase-functions/v2/https";
import { enforceAppCheck, REGION } from "./config";
import { requireUid } from "./quota";

/**
 * Dodo Payments = web billing (Play / App Store purchases stay on RevenueCat).
 * Both write the same users/{uid}.premium shape; `source: "dodo"` marks web subscriptions so a
 * store-side "not subscribed" answer never revokes a web subscription (and vice versa).
 */
const DODO_API_KEY = defineSecret("DODO_API_KEY");
const DODO_WEBHOOK_KEY = defineSecret("DODO_WEBHOOK_KEY");
const DODO_ENV = defineString("DODO_ENV", { default: "test_mode" }); // "test_mode" | "live_mode"
const DODO_PRODUCT_MONTHLY = defineString("DODO_PRODUCT_MONTHLY", { default: "" });
const DODO_PRODUCT_YEARLY = defineString("DODO_PRODUCT_YEARLY", { default: "" });
/** Public URL of the web app (Cloudflare Pages), used for checkout/portal return links. */
const WEB_APP_URL = defineString("WEB_APP_URL", { default: "https://selene-web.pages.dev" });

const FIREBASE_UID = /^[A-Za-z0-9]{20,40}$/;
/** Renewal webhooks can arrive a little after the period ends; don't lock the user out meanwhile. */
const RENEWAL_GRACE_MS = 2 * 86400000;

const apiBase = () => (DODO_ENV.value() === "live_mode" ? "https://live.dodopayments.com" : "https://test.dodopayments.com");

async function dodo<T>(method: "GET" | "POST", path: string, body?: unknown): Promise<T> {
  const r = await fetch(`${apiBase()}${path}`, {
    method,
    headers: { Authorization: `Bearer ${DODO_API_KEY.value()}`, "Content-Type": "application/json", Accept: "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(15_000),
  });
  if (!r.ok) {
    const text = await r.text().catch(() => "");
    throw new Error(`Dodo ${method} ${path} -> ${r.status} ${text.slice(0, 300)}`);
  }
  return (await r.json()) as T;
}

// ---------- Pure helpers (unit tested) ----------

/**
 * Standard Webhooks verification: HMAC-SHA256 over `${id}.${timestamp}.${body}` with the
 * base64 secret (optional `whsec_` prefix). The header may hold several `v1,<sig>` entries.
 */
export function verifyDodoSignature(
  secret: string, headers: { id?: string; timestamp?: string; signature?: string }, rawBody: string, nowSec = Math.floor(Date.now() / 1000),
): boolean {
  const { id, timestamp, signature } = headers;
  if (!secret || !id || !timestamp || !signature) return false;
  const ts = Number(timestamp);
  if (!Number.isFinite(ts) || Math.abs(nowSec - ts) > 300) return false; // replay window: 5 min
  const key = Buffer.from(secret.startsWith("whsec_") ? secret.slice(6) : secret, "base64");
  const expected = createHmac("sha256", key).update(`${id}.${timestamp}.${rawBody}`).digest();
  return signature.split(" ").some((part) => {
    const [ver, sig] = part.split(",", 2);
    if (ver !== "v1" || !sig) return false;
    const got = Buffer.from(sig, "base64");
    return got.length === expected.length && timingSafeEqual(got, expected);
  });
}

export interface DodoSubscription {
  subscription_id?: string; status?: string; product_id?: string; next_billing_date?: string | null;
  past_due_ends_at?: string | null; cancel_at_next_billing_date?: boolean;
  metadata?: Record<string, string> | null; customer?: { customer_id?: string; email?: string } | null;
}

export interface DodoDecision {
  active: boolean; expiresAt: number | null; plan: string | null; subscriptionId: string | null; customerId: string | null; status: string;
}

/**
 * Premium state from a Dodo subscription. A subscription cancelled "at period end" stays
 * `active` until then (cancel_at_next_billing_date), so status alone decides access.
 */
export function premiumFromDodo(s: DodoSubscription, now = Date.now()): DodoDecision {
  const status = String(s.status ?? "");
  const ms = (v?: string | null) => (v ? Date.parse(v) : NaN);
  let active = false;
  let until = NaN;
  if (status === "active") {
    until = ms(s.next_billing_date) + RENEWAL_GRACE_MS;
    active = Number.isNaN(until) || until > now;
  } else if (status === "past_due") {
    until = ms(s.past_due_ends_at);
    active = !Number.isNaN(until) && until > now; // card retry window
  }
  return {
    active,
    expiresAt: active && !Number.isNaN(until) ? until : null,
    plan: s.product_id ?? null,
    subscriptionId: s.subscription_id ?? null,
    customerId: s.customer?.customer_id ?? null,
    status,
  };
}

/** Picks the Firebase uid from subscription metadata (set by createDodoCheckout). */
export const uidFromMetadata = (m?: Record<string, string> | null) => {
  const v = m?.firebase_uid;
  return v && FIREBASE_UID.test(v) ? v : null;
};

// ---------- Persistence ----------

async function uidForCustomer(customerId: string | null): Promise<string | null> {
  if (!customerId) return null;
  const d = await getFirestore().doc(`dodoCustomers/${customerId}`).get();
  const uid = d.data()?.uid;
  return typeof uid === "string" && FIREBASE_UID.test(uid) ? uid : null;
}

/** Writes the decision unless a newer event already did (webhooks can arrive out of order). */
async function applyDecision(uid: string, d: DodoDecision, event: string, eventAt: number) {
  const db = getFirestore();
  const ref = db.doc(`users/${uid}`);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return;
    const cur = snap.data() ?? {};
    const lastAt = (cur.dodo?.lastEventAt as Timestamp | undefined)?.toMillis() ?? 0;
    if (eventAt < lastAt) return;
    const premium = cur.premium as { active?: boolean; source?: string } | undefined;
    // Only the web subscription may switch web Premium off; never touch an active store purchase.
    const mayWritePremium = d.active || !premium?.active || premium.source === "dodo";
    tx.set(ref, {
      dodo: {
        customerId: d.customerId ?? cur.dodo?.customerId ?? null, subscriptionId: d.subscriptionId, status: d.status,
        lastEventAt: Timestamp.fromMillis(eventAt),
      },
      ...(mayWritePremium ? {
        premium: {
          active: d.active, plan: d.plan, event, source: "dodo", environment: DODO_ENV.value(),
          expiresAt: d.expiresAt ? Timestamp.fromMillis(d.expiresAt) : null, updatedAt: Timestamp.now(),
        },
      } : {}),
    }, { merge: true });
  });
}

// ---------- Callables (web app) ----------

/** Creates (or reuses) the Dodo customer for this uid and returns a hosted checkout URL. */
export const createDodoCheckout = onCall({ region: REGION, enforceAppCheck, secrets: [DODO_API_KEY] }, async (req) => {
  const uid = requireUid(req);
  const plan = req.data?.plan === "monthly" ? "monthly" : "yearly";
  const productId = plan === "monthly" ? DODO_PRODUCT_MONTHLY.value() : DODO_PRODUCT_YEARLY.value();
  if (!productId || !DODO_API_KEY.value()) throw new HttpsError("failed-precondition", "Subscriptions are not configured yet.");

  const user = await getAuth().getUser(uid);
  if (!user.email) {
    throw new HttpsError("failed-precondition", "Please sign in with Google or email before subscribing, so your Premium is saved to your account.", { reason: "needs_account" });
  }

  const db = getFirestore();
  const ref = db.doc(`users/${uid}`);
  const doc = (await ref.get()).data() ?? {};
  let customerId = doc.dodo?.customerId as string | undefined;
  try {
    if (!customerId) {
      const c = await dodo<{ customer_id: string }>("POST", "/customers", { email: user.email, name: user.displayName || user.email.split("@")[0] });
      customerId = c.customer_id;
      await db.doc(`dodoCustomers/${customerId}`).set({ uid, createdAt: Timestamp.now() });
      await ref.set({ dodo: { customerId } }, { merge: true });
    }
    const base = WEB_APP_URL.value().replace(/\/+$/, "");
    const session = await dodo<{ session_id: string; checkout_url: string | null }>("POST", "/checkouts", {
      product_cart: [{ product_id: productId, quantity: 1 }],
      customer: { customer_id: customerId },
      metadata: { firebase_uid: uid, plan },
      return_url: `${base}/#/paywall?checkout=return`,
      cancel_url: `${base}/#/paywall`,
      customization: { theme: "dark" },
    });
    if (!session.checkout_url) throw new Error("no checkout_url");
    return { url: session.checkout_url };
  } catch (e) {
    logger.error("createDodoCheckout failed", { error: String(e) });
    throw new HttpsError("unavailable", "Could not start checkout. Please try again in a moment.");
  }
});

/** Link to Dodo's customer portal (manage / cancel the web subscription, invoices). */
export const dodoPortal = onCall({ region: REGION, enforceAppCheck, secrets: [DODO_API_KEY] }, async (req) => {
  const uid = requireUid(req);
  const customerId = (await getFirestore().doc(`users/${uid}`).get()).data()?.dodo?.customerId as string | undefined;
  if (!customerId) throw new HttpsError("not-found", "No web subscription found for this account.");
  try {
    const base = WEB_APP_URL.value().replace(/\/+$/, "");
    const r = await dodo<{ link: string }>("POST", `/customers/${encodeURIComponent(customerId)}/customer-portal/session?return_url=${encodeURIComponent(`${base}/#/profile`)}`);
    return { url: r.link };
  } catch (e) {
    logger.error("dodoPortal failed", { error: String(e) });
    throw new HttpsError("unavailable", "Could not open subscription settings. Please try again.");
  }
});

/**
 * Pulls the caller's subscriptions from Dodo and stores the best one. Used when the browser
 * returns from checkout, so Premium unlocks even if the webhook is late.
 */
export const syncDodoPremium = onCall({ region: REGION, enforceAppCheck, secrets: [DODO_API_KEY] }, async (req) => {
  const uid = requireUid(req);
  const customerId = (await getFirestore().doc(`users/${uid}`).get()).data()?.dodo?.customerId as string | undefined;
  if (!customerId) return { active: false };
  let items: DodoSubscription[];
  try {
    const r = await dodo<{ items?: DodoSubscription[] }>("GET", `/subscriptions?customer_id=${encodeURIComponent(customerId)}&page_size=20`);
    items = r.items ?? [];
  } catch (e) {
    logger.warn("syncDodoPremium lookup failed", { error: String(e) });
    throw new HttpsError("unavailable", "Could not confirm your subscription yet. Please try again in a moment.");
  }
  const decisions = items.map((s) => premiumFromDodo({ ...s, customer: s.customer ?? { customer_id: customerId } }));
  const best = decisions.find((d) => d.active) ?? decisions[0];
  if (best) await applyDecision(uid, best, "SYNC", Date.now());
  return { active: best?.active ?? false };
});

// ---------- Webhook ----------

/** Dodo → Premium. Configure in Dodo dashboard → Developer → Webhooks (subscription.* events). */
export const dodoWebhook = onRequest({ region: REGION, secrets: [DODO_WEBHOOK_KEY] }, async (req, res) => {
  if (req.method !== "POST") { res.status(405).send("method not allowed"); return; }
  const raw = req.rawBody?.toString("utf8") ?? "";
  const ok = verifyDodoSignature(DODO_WEBHOOK_KEY.value(), {
    id: req.header("webhook-id"), timestamp: req.header("webhook-timestamp"), signature: req.header("webhook-signature"),
  }, raw);
  if (!ok) { res.status(401).send("invalid signature"); return; }

  let body: { type?: string; timestamp?: string; data?: DodoSubscription & { payload_type?: string } };
  try { body = JSON.parse(raw); } catch { res.status(400).send("bad json"); return; }
  const type = String(body.type ?? "");
  const data = body.data;
  if (!type.startsWith("subscription.") || !data) { res.status(200).send("ignored"); return; }

  const d = premiumFromDodo(data);
  const uid = uidFromMetadata(data.metadata) ?? (await uidForCustomer(d.customerId));
  if (!uid) {
    logger.warn("dodoWebhook: no uid for subscription", { type, sub: d.subscriptionId });
    res.status(200).send("unknown user"); // ack so Dodo doesn't retry forever
    return;
  }
  const eventAt = Date.parse(body.timestamp ?? "") || Date.now();
  await applyDecision(uid, d, type, eventAt);
  logger.info("dodo premium updated", { type, status: d.status, active: d.active });
  res.status(200).send("ok");
});
