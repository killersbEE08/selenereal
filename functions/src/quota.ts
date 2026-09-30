import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { HttpsError, type CallableRequest } from "firebase-functions/v2/https";

export type Feature = "palm" | "tarot" | "tarotBasic" | "chat";

export interface UserDoc {
  displayName?: string; zodiac?: string; language?: string; focusAreas?: string[]; dob?: string;
  birthTime?: string | null; birthPlace?: string | null;
  premium?: { active?: boolean; expiresAt?: FirebaseFirestore.Timestamp | null };
  usage?: { date?: string; palm?: number; tarot?: number; tarotBasic?: number; chat?: number; lifetimePalm?: number };
  settings?: { keepPalmPhotos?: boolean };
}

const SIGN_IDS = ["aries", "taurus", "gemini", "cancer", "leo", "virgo", "libra", "scorpio", "sagittarius", "capricorn", "aquarius", "pisces"];
const FOCUS_IDS = ["love", "career", "growth", "health", "spirituality"];
const DOB_RE = /^(19|20)\d{2}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/;
const TIME_RE = /^([01]\d|2[0-3]):[0-5]\d$/;

/** First name: letters/marks/.'- only, max 30 chars. */
export function safeFirstName(raw: unknown): string {
  const first = String(raw ?? "").normalize("NFKC").trim().split(/[^\p{L}\p{M}.'-]+/u).find(Boolean) ?? "";
  return first.replace(/[^\p{L}\p{M}.'-]/gu, "").slice(0, 30);
}
/** Birth date YYYY-MM-DD, or "" when missing/invalid. */
export const safeDob = (v: unknown) => (typeof v === "string" && DOB_RE.test(v) ? v : "");
/** Birth time HH:mm (24h), or "" when unknown/invalid. */
export const safeBirthTime = (v: unknown) => (typeof v === "string" && TIME_RE.test(v) ? v : "");
/** Birth place: letters, spaces and , . ' - only (a city/country), max 60 chars. */
export function safeBirthPlace(v: unknown): string {
  if (typeof v !== "string") return "";
  return v.normalize("NFKC").replace(/[^\p{L}\p{M} ,.'-]/gu, "").replace(/\s{2,}/g, " ").trim().slice(0, 60);
}

/**
 * Profile fields are user-editable, so they are untrusted when interpolated into prompts.
 * Name: letters/spaces/.'- only, max 30 chars. Everything else is whitelisted.
 */
export function safeProfile(u: UserDoc) {
  return {
    name: safeFirstName(u.displayName),
    zodiac: SIGN_IDS.includes(String(u.zodiac)) ? String(u.zodiac) : "",
    focus: Array.isArray(u.focusAreas) ? u.focusAreas.filter((f) => FOCUS_IDS.includes(String(f))).slice(0, 5) : [],
    language: u.language === "hi" ? "hi" : "en",
    dob: safeDob(u.dob),
    birthTime: safeBirthTime(u.birthTime),
    birthPlace: safeBirthPlace(u.birthPlace),
  };
}

/** One-line birth chart context for prompts, e.g. "born 2000-01-31 at 06:45 in Patna, India". */
export function birthLine(p: { dob: string; birthTime: string; birthPlace: string }): string {
  if (!p.dob && !p.birthPlace) return "unknown";
  return ["born", p.dob || "(date unknown)", p.birthTime ? `at ${p.birthTime}` : "(time unknown)", p.birthPlace ? `in ${p.birthPlace}` : ""].filter(Boolean).join(" ");
}

/**
 * Returns the caller's uid. Email/password accounts must have verified their email; the same
 * rule is enforced in firestore.rules, so a modified app can't skip the verification screen.
 * Guest (anonymous) and Google accounts pass. `allowUnverified` is only for account deletion.
 */
export function requireUid(req: CallableRequest<unknown>, opts: { allowUnverified?: boolean } = {}): string {
  if (!req.auth?.uid) throw new HttpsError("unauthenticated", "Please sign in to continue.");
  if (!opts.allowUnverified && needsEmailVerification(req.auth.token as unknown as AuthToken)) {
    throw new HttpsError("permission-denied", "Please verify your email address to continue.", { reason: "email_unverified" });
  }
  return req.auth.uid;
}

interface AuthToken { email_verified?: boolean; firebase?: { sign_in_provider?: string } }
export const needsEmailVerification = (t: AuthToken | undefined) => t?.firebase?.sign_in_provider === "password" && t.email_verified !== true;

export const today = (d = new Date()) => d.toISOString().slice(0, 10);

export function isPremium(u: UserDoc | undefined, now = Date.now()): boolean {
  const p = u?.premium;
  if (!p?.active) return false;
  return !p.expiresAt || p.expiresAt.toMillis() > now;
}

export interface Limits { freeDaily: number; premiumDaily: number; freeLifetime?: number }

/** Pure quota decision, exported for tests. */
export function quotaDecision(u: UserDoc | undefined, feature: Feature, limits: Limits, date: string) {
  const premium = isPremium(u);
  const usage = u?.usage ?? {};
  const used = usage.date === date ? (usage[feature] ?? 0) : 0;
  if (!premium && feature === "palm" && limits.freeLifetime !== undefined) {
    if ((usage.lifetimePalm ?? 0) >= limits.freeLifetime) return { allowed: false, premium, reason: "lifetime" as const };
  }
  const cap = premium ? limits.premiumDaily : limits.freeDaily;
  if (used >= cap) return { allowed: false, premium, reason: "daily" as const };
  return { allowed: true, premium, reason: null };
}

function quotaError(reason: "lifetime" | "daily" | null, feature: Feature, premium = false) {
  const msg = reason === "lifetime" ? "You've used your free palm reading. Go Premium for unlimited readings." :
    premium ? "You've reached today's limit. Please come back tomorrow." :
      feature === "chat" ? "You've used today's free messages. Go Premium to keep chatting." :
        feature === "tarot" ? "You've used today's free AI reading. Go Premium for unlimited readings." :
          "You've reached today's limit. Come back tomorrow or Go Premium.";
  // Premium users at their (generous) cap shouldn't be sent to the paywall.
  return new HttpsError("resource-exhausted", msg, { feature, reason: premium ? "premium_cap" : reason });
}

function bump(u: UserDoc | undefined, feature: Feature, date: string, delta: 1 | -1) {
  const usage = { ...(u?.usage ?? {}) };
  if (usage.date !== date) Object.assign(usage, { date, palm: 0, tarot: 0, tarotBasic: 0, chat: 0 });
  usage[feature] = Math.max(0, (usage[feature] ?? 0) + delta);
  if (feature === "palm") usage.lifetimePalm = Math.max(0, (usage.lifetimePalm ?? 0) + delta);
  return usage;
}

export interface Reservation { user: UserDoc; premium: boolean; refund: () => Promise<void> }

/**
 * Atomically checks AND consumes one unit inside a transaction, so parallel requests
 * can't all pass the check before any is counted. Call `refund()` if the AI call fails
 * (failed readings never cost the user).
 */
export async function reserveQuota(uid: string, feature: Feature, limits: Limits): Promise<Reservation> {
  const db = getFirestore();
  const ref = db.doc(`users/${uid}`);
  const date = today();
  const { user, premium } = await db.runTransaction(async (tx) => {
    const u = (await tx.get(ref)).data() as UserDoc | undefined;
    const d = quotaDecision(u, feature, limits, date);
    if (!d.allowed) throw quotaError(d.reason, feature, d.premium);
    tx.set(ref, { usage: bump(u, feature, date, 1), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    return { user: u ?? {}, premium: d.premium };
  });
  let refunded = false;
  const refund = async () => {
    if (refunded) return;
    refunded = true;
    await db.runTransaction(async (tx) => {
      const u = (await tx.get(ref)).data() as UserDoc | undefined;
      tx.set(ref, { usage: bump(u, feature, date, -1) }, { merge: true });
    }).catch(() => undefined);
  };
  return { user, premium, refund };
}

/** Read-only premium/user lookup for features that don't consume quota. */
export async function loadUser(uid: string) {
  const u = ((await getFirestore().doc(`users/${uid}`).get()).data() ?? {}) as UserDoc;
  return { user: u, premium: isPremium(u) };
}
