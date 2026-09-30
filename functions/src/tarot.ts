import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import {
  enforceAppCheck, FREE_TAROT_DAILY, GEMINI_API_KEY, MODEL_REASONING, PREMIUM_TAROT_DAILY, PROMPT_VERSION, REGION, REVERSAL_PROBABILITY,
} from "./config";
import { cardById, drawCards, READERS, SPREADS, type SpreadPosition } from "./data";
import { generateJson } from "./gemini";
import { tarotSystem, tarotUserPrompt, TAROT_SCHEMA } from "./prompts/text";
import { birthLine, loadUser, reserveQuota, requireUid, safeProfile, today } from "./quota";
import { cleanUserText, CRISIS_REPLY, DOC_ID, findBanned, isCrisis, languageName } from "./safety";
import { TarotZ, type TarotInterpretation } from "./schemas";

const TOPICS = ["love", "career", "relationships", "growth", "general"];

export const startTarotReading = onCall(
  { region: REGION, secrets: [GEMINI_API_KEY], enforceAppCheck, timeoutSeconds: 120 },
  async (req) => {
    const uid = requireUid(req);
    const d = (req.data ?? {}) as { question?: string; topic?: string; spreadId?: string; customSpreadId?: string; aiEnabled?: boolean; readerId?: string };
    const question = cleanUserText(d.question, 200);
    const topic = TOPICS.includes(d.topic ?? "") ? d.topic! : "general";
    const aiEnabled = d.aiEnabled !== false;
    const db = getFirestore();

    const { premium } = await loadUser(uid);

    // Resolve spread (built-in or the user's custom spread).
    let spreadName: string; let positions: SpreadPosition[]; let spreadId: string;
    if (d.customSpreadId) {
      if (typeof d.customSpreadId !== "string" || !DOC_ID.test(d.customSpreadId)) throw new HttpsError("invalid-argument", "Invalid spread id.");
      if (!premium) throw new HttpsError("permission-denied", "Custom spreads are a Premium feature.", { reason: "premium" });
      const s = await db.doc(`users/${uid}/customSpreads/${d.customSpreadId}`).get();
      if (!s.exists) throw new HttpsError("not-found", "Spread not found.");
      const data = s.data() as { name?: unknown; positions?: unknown };
      const raw = Array.isArray(data.positions) ? data.positions.slice(0, 10) : [];
      spreadName = cleanUserText(data.name, 40) || "My Spread";
      positions = raw
        .map((p) => (p && typeof p === "object" ? (p as { label?: unknown; meaning?: unknown }) : {}))
        .map((p, i) => ({ index: i, label: cleanUserText(p.label, 30) || `Card ${i + 1}`, meaning: cleanUserText(p.meaning, 80) }));
      spreadId = `custom:${d.customSpreadId}`;
    } else {
      const s = SPREADS.find((x) => x.id === (d.spreadId ?? "three_card"));
      if (!s) throw new HttpsError("invalid-argument", "Unknown spread.");
      if (s.premium && !premium) throw new HttpsError("permission-denied", `${s.name} is a Premium spread.`, { reason: "premium" });
      spreadName = s.name; positions = s.positions; spreadId = s.id;
    }
    if (positions.length < 1) throw new HttpsError("invalid-argument", "Spread has no positions.");

    const reader = READERS.find((r) => r.id === d.readerId) ?? READERS[0];
    if (reader.premium && !premium) throw new HttpsError("permission-denied", `${reader.name} is available with Premium.`, { reason: "premium" });
    const drawn = drawCards(positions.length, REVERSAL_PROBABILITY);
    const cards = drawn.map((c, i) => ({ ...c, position: i, positionLabel: positions[i].label, positionMeaning: positions[i].meaning }));

    // Every reading reserves quota atomically (AI-off readings count against a separate, generous cap).
    const aiOn = aiEnabled && !isCrisis(question);
    const quota = await reserveQuota(uid, aiOn ? "tarot" : "tarotBasic", aiOn
      ? { freeDaily: FREE_TAROT_DAILY.value(), premiumDaily: PREMIUM_TAROT_DAILY.value() }
      : { freeDaily: 30, premiumDaily: 200 });
    const profile = safeProfile(quota.user);

    let interpretation: TarotInterpretation | null = null;
    let safety = aiEnabled && !aiOn;
    try {
      if (aiOn) {
        const system = tarotSystem(languageName(profile.language), profile.name, reader.name, reader.persona);
        const prompt = tarotUserPrompt({ question, topic, spreadName, positions, drawn, cards: cardById, name: profile.name, zodiac: profile.zodiac, date: today(), birth: birthLine(profile) });
        const maxTokens = positions.length === 1 ? 2048 : positions.length <= 3 ? 4096 : 8192;
        for (let attempt = 0; attempt < 2 && !interpretation; attempt++) {
          const parsed = TarotZ.safeParse(await generateJson<unknown>({ model: MODEL_REASONING.value(), system, schema: TAROT_SCHEMA, parts: [{ text: prompt }], maxOutputTokens: maxTokens }));
          if (parsed.success && !findBanned(parsed.data)) interpretation = parsed.data;
        }
        if (!interpretation) throw new HttpsError("unavailable", "The cards are shy right now. Please try again — no credit was used.");
        safety = interpretation.safety_flag;
      }

      const ref = db.collection(`users/${uid}/tarotReadings`).doc();
      const doc = {
        question, topic, spreadId, spreadName, aiEnabled, readerId: reader.id, cards, interpretation,
        safety, safetyMessage: safety ? CRISIS_REPLY : null, model: aiOn ? MODEL_REASONING.value() : null,
        promptVersion: PROMPT_VERSION, createdAt: FieldValue.serverTimestamp(),
      };
      await ref.set(doc);
      return { readingId: ref.id, ...doc, createdAt: new Date().toISOString() };
    } catch (e) {
      await quota.refund();
      throw e instanceof HttpsError ? e : new HttpsError("internal", "The cards are shy right now. Please try again — no credit was used.");
    }
  },
);
