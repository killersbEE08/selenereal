import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { moonPhase, periodKey, SIGNS, type Period } from "./astro";
import { enforceAppCheck, GEMINI_API_KEY, MODEL_LIGHT, PROMPT_VERSION, REGION } from "./config";
import { generateJson } from "./gemini";
import { horoscopeSystem, HOROSCOPE_SCHEMA } from "./prompts/text";
import { requireUid, isPremium, type UserDoc } from "./quota";
import { findBanned, languageName } from "./safety";
import { HoroscopeZ } from "./schemas";

const PERIODS: Period[] = ["daily", "weekly", "monthly", "yearly"];
const LANGS = ["en", "hi"];

export async function getOrCreateHoroscope(sign: string, period: Period, lang: string, now = new Date()) {
  const key = periodKey(period, now);
  const id = `${sign}_${period}_${key}_${lang}`;
  const ref = getFirestore().doc(`horoscopes/${id}`);
  const snap = await ref.get();
  if (snap.exists) return snap.data()!;
  const s = SIGNS.find((x) => x.id === sign)!;
  const moon = moonPhase(now).name;
  let data: unknown;
  for (let i = 0; i < 2; i++) {
    const raw = await generateJson<unknown>({
      model: MODEL_LIGHT.value(), system: horoscopeSystem({ language: languageName(lang), period, periodKey: key, moon }), schema: HOROSCOPE_SCHEMA,
      parts: [{ text: `Sign: ${s.name} (${s.range}). Period: ${period} ${key}.` }], maxOutputTokens: 2048, temperature: 1,
    });
    const p = HoroscopeZ.safeParse(raw);
    if (p.success && !findBanned(p.data)) { data = p.data; break; }
  }
  if (!data) throw new HttpsError("unavailable", "The stars are still aligning. Please try again shortly.");
  const doc = { ...(data as object), sign, period, periodKey: key, language: lang, promptVersion: PROMPT_VERSION, generatedAt: FieldValue.serverTimestamp() };
  await ref.set(doc);
  return { ...doc, generatedAt: new Date().toISOString() };
}

export const getHoroscope = onCall(
  { region: REGION, secrets: [GEMINI_API_KEY], enforceAppCheck, timeoutSeconds: 60 },
  async (req) => {
    const uid = requireUid(req);
    const { sign, period } = (req.data ?? {}) as { sign?: string; period?: Period };
    if (!SIGNS.some((s) => s.id === sign)) throw new HttpsError("invalid-argument", "Unknown sign.");
    if (!PERIODS.includes(period as Period)) throw new HttpsError("invalid-argument", "Unknown period.");
    const user = (await getFirestore().doc(`users/${uid}`).get()).data() as UserDoc | undefined;
    if (period !== "daily" && !isPremium(user)) {
      throw new HttpsError("permission-denied", "Weekly, monthly and yearly horoscopes are Premium.", { reason: "premium" });
    }
    const lang = LANGS.includes(user?.language ?? "") ? user!.language! : "en";
    const h = await getOrCreateHoroscope(sign!, period!, lang);
    return { ...h, generatedAt: undefined };
  },
);

/** Pre-generates today's daily horoscopes shortly after midnight UTC so users hit the cache. */
export const prewarmHoroscopes = onSchedule(
  { region: REGION, schedule: "5 0 * * *", timeZone: "UTC", secrets: [GEMINI_API_KEY], timeoutSeconds: 540 },
  async () => {
    const now = new Date();
    const periods: Period[] = ["daily"];
    if (now.getUTCDay() === 1) periods.push("weekly");
    if (now.getUTCDate() === 1) periods.push("monthly");
    if (now.getUTCDate() === 1 && now.getUTCMonth() === 0) periods.push("yearly");
    for (const period of periods) {
      for (let i = 0; i < SIGNS.length; i += 4) {
        await Promise.all(SIGNS.slice(i, i + 4).map((s) =>
          getOrCreateHoroscope(s.id, period, "en", now).catch((e) => logger.error("prewarm failed", { sign: s.id, period, e: String(e) }))));
      }
    }
  },
);
