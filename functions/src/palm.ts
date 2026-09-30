import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { logger } from "firebase-functions";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import {
  enforceAppCheck, FREE_PALM_LIFETIME, GEMINI_API_KEY, MODEL_LIGHT, MODEL_VISION, PREMIUM_PALM_DAILY, PROMPT_VERSION, REGION,
} from "./config";
import { generateJson } from "./gemini";
import { palmSystem, palmUserPrompt, PALM_SCHEMA, RELATIONS, VALIDATION_SCHEMA, VALIDATION_SYSTEM, type Validation } from "./prompts/palm";
import { sunSign } from "./astro";
import { birthLine, reserveQuota, requireUid, safeBirthPlace, safeBirthTime, safeDob, safeFirstName, safeProfile, today } from "./quota";
import { findBanned, languageName } from "./safety";
import { normalizePalm, PalmReadingZ, type PalmReading } from "./schemas";

const ID_RE = /^[A-Za-z0-9_-]{6,40}$/;

export interface PalmSubject { name: string; relation: string; dob: string; birthTime: string; birthPlace: string }

/** Validates the optional "someone else's palm" details (untrusted client input, goes into the prompt). */
export function safeSubject(raw: unknown): PalmSubject | null {
  if (raw == null) return null;
  if (typeof raw !== "object") throw new HttpsError("invalid-argument", "Invalid person details.");
  const s = raw as Record<string, unknown>;
  const name = safeFirstName(s.name);
  if (name.length < 2) throw new HttpsError("invalid-argument", "Please enter their name.");
  const relation = typeof s.relation === "string" && Object.hasOwn(RELATIONS, s.relation) ? s.relation : "other";
  return { name, relation, dob: safeDob(s.dob), birthTime: safeBirthTime(s.birthTime), birthPlace: safeBirthPlace(s.birthPlace) };
}
/** Rejected photos don't consume the reading, so cap validation attempts to stop free Gemini usage. */
const MAX_VALIDATIONS_PER_DAY = 15;
const JPEG = [0xff, 0xd8, 0xff], PNG = [0x89, 0x50, 0x4e, 0x47];

async function countValidation(uid: string) {
  const db = getFirestore();
  const ref = db.doc(`users/${uid}/private/palmAttempts`);
  const date = today();
  return db.runTransaction(async (tx) => {
    const d = (await tx.get(ref)).data() as { date?: string; n?: number } | undefined;
    const n = d?.date === date ? (d.n ?? 0) : 0;
    if (n >= MAX_VALIDATIONS_PER_DAY) throw new HttpsError("resource-exhausted", "Too many photo attempts today. Please try again tomorrow.", { reason: "attempts" });
    tx.set(ref, { date, n: n + 1 });
  });
}

export const analyzePalm = onCall(
  { region: REGION, secrets: [GEMINI_API_KEY], enforceAppCheck, timeoutSeconds: 120, memory: "512MiB" },
  async (req) => {
    const uid = requireUid(req);
    const { readingId, hand, subject: rawSubject } = (req.data ?? {}) as { readingId?: string; hand?: string; subject?: unknown };
    if (!readingId || !ID_RE.test(readingId)) throw new HttpsError("invalid-argument", "Invalid reading id.");
    if (hand !== "left" && hand !== "right") throw new HttpsError("invalid-argument", "Hand must be left or right.");
    const subject = safeSubject(rawSubject);

    const db = getFirestore();
    const imagePath = `palms/${uid}/${readingId}.jpg`; // path is derived server-side, never trusted from the client
    const docRef = db.doc(`users/${uid}/palmReadings/${readingId}`);
    if ((await docRef.get()).get("status") === "done") throw new HttpsError("already-exists", "This reading is already complete.");

    const file = getStorage().bucket().file(imagePath);
    const [exists] = await file.exists();
    if (!exists) throw new HttpsError("not-found", "Photo not found. Please upload it again.");
    const [meta] = await file.getMetadata();
    if (Number(meta.size) > 5 * 1024 * 1024) {
      await file.delete({ ignoreNotFound: true });
      throw new HttpsError("invalid-argument", "Photo is too large.");
    }
    const [buf] = await file.download();
    const isJpeg = JPEG.every((b, i) => buf[i] === b), isPng = PNG.every((b, i) => buf[i] === b);
    if (!isJpeg && !isPng) {
      await file.delete({ ignoreNotFound: true });
      throw new HttpsError("invalid-argument", "That file isn't a supported photo. Please use a JPEG or PNG.");
    }
    const image = { inlineData: { mimeType: isPng ? "image/png" : "image/jpeg", data: buf.toString("base64") } };

    // Reserve the reading atomically up front; refunded on any failure below.
    const quota = await reserveQuota(uid, "palm", {
      freeDaily: FREE_PALM_LIFETIME.value(), premiumDaily: PREMIUM_PALM_DAILY.value(), freeLifetime: FREE_PALM_LIFETIME.value(),
    });
    const profile = safeProfile(quota.user);
    const started = Date.now();
    try {
      await countValidation(uid);
      await docRef.set({
        hand, status: "processing", createdAt: FieldValue.serverTimestamp(), promptVersion: PROMPT_VERSION,
        ...(subject ? { subject: { name: subject.name, relation: subject.relation } } : {}),
      });

      // 1) Validate the photo with the light model.
      const validation = await generateJson<Validation>({
        model: MODEL_LIGHT.value(), system: VALIDATION_SYSTEM, schema: VALIDATION_SCHEMA, temperature: 0.1, maxOutputTokens: 400,
        parts: [image, { text: `The user says this is ${subject ? "someone's" : "their"} ${hand} hand.` }],
      });
      if (!validation.is_palm || validation.quality === "poor") {
        await quota.refund();
        await file.delete({ ignoreNotFound: true }); // never keep rejected photos
        await docRef.set({ status: "invalid", validation }, { merge: true });
        return { status: "invalid", validation };
      }

      // 2) Full reading with the vision model (for the user, or for the person they named).
      const owner = subject
        ? {
          name: subject.name, relation: subject.relation, focus: profile.focus,
          zodiac: subject.dob ? sunSign(Number(subject.dob.slice(5, 7)), Number(subject.dob.slice(8, 10))) : "",
          birth: birthLine(subject),
        }
        : { name: profile.name, relation: undefined, focus: profile.focus, zodiac: profile.zodiac, birth: birthLine(profile) };
      const system = palmSystem(languageName(profile.language), owner.name, !!subject);
      const prompt = palmUserPrompt({ hand, ...owner, date: today() });
      let reading: PalmReading | undefined;
      for (let attempt = 0; attempt < 2 && !reading; attempt++) {
        const raw = await generateJson<unknown>({
          model: MODEL_VISION.value(), system, schema: PALM_SCHEMA, maxOutputTokens: 8192, temperature: 0.4, parts: [image, { text: prompt }],
        });
        const parsed = PalmReadingZ.safeParse(raw);
        if (!parsed.success) { logger.warn("palm schema mismatch", { issues: parsed.error.issues.slice(0, 3) }); continue; }
        const banned = findBanned(parsed.data);
        if (banned) { logger.warn("palm banned phrase, regenerating", { banned }); continue; }
        reading = normalizePalm(parsed.data);
      }
      if (!reading) throw new HttpsError("unavailable", "We couldn't finish your reading. Please try again — no credit was used.");

      const keep = quota.user.settings?.keepPalmPhotos === true;
      await docRef.set({
        status: "done", validation, result: reading, model: MODEL_VISION.value(), latencyMs: Date.now() - started,
        premiumAtCreation: quota.premium, imageKept: keep, ...(keep ? { imagePath } : {}),
      }, { merge: true });
      // The client keeps a local copy for the overlay. The server copy is deleted unless the user opted in.
      if (!keep) await file.delete({ ignoreNotFound: true });
      return { status: "done", readingId, result: reading, premium: quota.premium };
    } catch (e) {
      await quota.refund();
      await docRef.set({ status: "failed" }, { merge: true }).catch(() => undefined);
      throw e instanceof HttpsError ? e : new HttpsError("internal", "We couldn't finish your reading. Please try again — no credit was used.");
    }
  },
);
