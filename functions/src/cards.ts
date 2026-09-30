import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { enforceAppCheck, GEMINI_API_KEY, MODEL_LIGHT, REGION } from "./config";
import { cardById, dailyCardFor } from "./data";
import { generateText } from "./gemini";
import { requireUid, safeProfile, today, type UserDoc } from "./quota";
import { findBanned, GLOBAL_RULES, languageName } from "./safety";

async function loadUser(uid: string) {
  return ((await getFirestore().doc(`users/${uid}`).get()).data() ?? {}) as UserDoc;
}

/** Short personalised "AI Insight" for a card, cached per user/card/day. */
export const getCardInsight = onCall(
  { region: REGION, secrets: [GEMINI_API_KEY], enforceAppCheck, timeoutSeconds: 30 },
  async (req) => {
    const uid = requireUid(req);
    const { cardId, reversed } = (req.data ?? {}) as { cardId?: string; reversed?: boolean };
    const card = cardById.get(cardId ?? "");
    if (!card) throw new HttpsError("invalid-argument", "Unknown card.");
    const date = today();
    const ref = getFirestore().doc(`users/${uid}/insights/${card.id}_${reversed ? "r" : "u"}_${date}`);
    const snap = await ref.get();
    if (snap.exists) return { text: snap.get("text") as string };
    const p = safeProfile(await loadUser(uid));
    const system = `${GLOBAL_RULES}\n- Respond in ${languageName(p.language)}.`;
    const prompt = `Write ONE or TWO sentences (max 35 words) of personal guidance about the tarot card ${card.name} (${reversed ? "reversed" : "upright"}) ` +
      `for a ${p.zodiac || "seeker"} whose focus is ${p.focus.join(", ") || "general"}, for today ${date}. Speak as Selene, warm and optimistic. No preamble, no quotes.`;
    let text = await generateText(MODEL_LIGHT.value(), system, prompt, 300);
    if (findBanned(text)) text = card.description;
    await ref.set({ text, createdAt: FieldValue.serverTimestamp() });
    return { text };
  },
);

/** Deterministic daily card with a short personal message. */
export const getDailyCard = onCall(
  { region: REGION, secrets: [GEMINI_API_KEY], enforceAppCheck, timeoutSeconds: 30 },
  async (req) => {
    const uid = requireUid(req);
    // Only today (±1 day for time zones) is allowed; arbitrary dates would allow unlimited Gemini calls.
    const now = Date.now();
    const allowed = [today(new Date(now - 86400000)), today(new Date(now)), today(new Date(now + 86400000))];
    const date = typeof req.data?.date === "string" && allowed.includes(req.data.date) ? req.data.date : today();
    const ref = getFirestore().doc(`users/${uid}/dailyCard/${date}`);
    const snap = await ref.get();
    if (snap.exists) return snap.data();
    const drawn = dailyCardFor(uid, date);
    const card = cardById.get(drawn.cardId)!;
    const p = safeProfile(await loadUser(uid));
    const system = `${GLOBAL_RULES}\n- Respond in ${languageName(p.language)}.`;
    const prompt = `Today's card for ${p.name || "friend"} (${p.zodiac || "unknown sign"}) is ${card.name} ${drawn.reversed ? "reversed" : "upright"}. ` +
      `Write a 40-60 word "message for you today" with one tiny actionable step. Warm, specific, no preamble.`;
    let message: string;
    try {
      message = await generateText(MODEL_LIGHT.value(), system, prompt, 400);
      if (findBanned(message)) message = drawn.reversed ? card.reversed : card.upright;
    } catch {
      message = drawn.reversed ? card.reversed : card.upright; // graceful fallback, still cached for the day
    }
    const doc = { ...drawn, date, message };
    await ref.set({ ...doc, createdAt: FieldValue.serverTimestamp() });
    return doc;
  },
);
