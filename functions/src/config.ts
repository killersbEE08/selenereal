import { defineSecret, defineString, defineInt } from "firebase-functions/params";

export const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");

// Model IDs are params so they can be changed without an app release (models rotate quickly).
export const MODEL_VISION = defineString("MODEL_VISION", { default: "gemini-3.5-flash" });
export const MODEL_REASONING = defineString("MODEL_REASONING", { default: "gemini-3.5-flash" });
export const MODEL_LIGHT = defineString("MODEL_LIGHT", { default: "gemini-3.5-flash-lite" });

export const FREE_PALM_LIFETIME = defineInt("FREE_PALM_LIFETIME", { default: 1 });
// Freemium: free users get a taste of each feature, Premium unlocks the rest (mirrored in lib/data/models.dart).
export const FREE_TAROT_DAILY = defineInt("FREE_TAROT_DAILY", { default: 1 });
export const FREE_CHAT_DAILY = defineInt("FREE_CHAT_DAILY", { default: 3 });
export const PREMIUM_CHAT_DAILY = defineInt("PREMIUM_CHAT_DAILY", { default: 200 });
export const PREMIUM_PALM_DAILY = defineInt("PREMIUM_PALM_DAILY", { default: 10 });
export const PREMIUM_TAROT_DAILY = defineInt("PREMIUM_TAROT_DAILY", { default: 50 });

export const REGION = "asia-south1";
export const PROMPT_VERSION = "2026-09-29.1";
export const REVERSAL_PROBABILITY = 0.3;

export const isEmulator = () => process.env.FUNCTIONS_EMULATOR === "true";
// App Check is enforced in production; the emulator uses the debug flow.
export const enforceAppCheck = process.env.FUNCTIONS_EMULATOR !== "true";
