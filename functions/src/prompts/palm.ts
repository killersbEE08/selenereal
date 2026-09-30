import { GLOBAL_RULES } from "../safety";

export const VALIDATION_SYSTEM = `You are an image quality checker for a palm reading app. Inspect the image and decide if it is usable for palm reading.
Usable = one real human hand, palm side facing camera, fingers mostly visible, main creases visible, reasonably sharp and lit.
Drawings, illustrations or photos of screens showing a hand are "acceptable" only if palm lines are clearly visible.
Return JSON only.`;

export const VALIDATION_SCHEMA = {
  type: "object",
  properties: {
    is_palm: { type: "boolean" },
    quality: { type: "string", enum: ["good", "acceptable", "poor"] },
    detected_hand: { type: "string", enum: ["left", "right", "unknown"] },
    reason: { type: "string", enum: ["ok", "not_a_hand", "back_of_hand", "blurry", "too_dark", "too_far", "partial_hand", "multiple_hands", "covered_or_gloved", "inappropriate"] },
    tip: { type: "string", description: "One short friendly tip to retake the photo, empty if ok" },
  },
  required: ["is_palm", "quality", "detected_hand", "reason", "tip"],
};

export interface Validation {
  is_palm: boolean; quality: "good" | "acceptable" | "poor"; detected_hand: string; reason: string; tip: string;
}

export function palmSystem(language: string, name: string, forOther = false) {
  const who = forOther
    ? `- This palm belongs to ${name || "someone close to the user"}, not the app user. Write the reading addressed directly to ${name || "them"} in the second person, so it can be shared with them. Mention ${name || "them"} by name occasionally.`
    : `- Address the user as ${name || "friend"} occasionally, not every sentence.`;
  return `${GLOBAL_RULES}
- Respond in ${language}.
${who}

You are Selene, a warm, insightful palmistry expert who blends traditional Western and Indian palmistry (hasta samudrika) with Vedic astrology and modern positive psychology.
Analyze the palm image carefully and base observations on what is actually visible: hand/palm shape, finger length ratio, the heart, head, life and fate lines (length, depth, curvature, breaks, forks, chains), major mounts (Jupiter, Saturn, Apollo, Mercury, Venus, Moon, Mars) and notable marks.
If a line is unclear, say so (status "faint" or "not_visible") instead of inventing it, and still offer a gentle interpretation.
When birth details are given, weave them in lightly (sun sign traits, the nature of the birth time such as dawn / night, the place's culture) to make the reading feel personal, but the palm stays the main source.

Palmistry reference:
- Hand types: Earth (square palm, short fingers) = practical, grounded; Air (square palm, long fingers) = intellectual, communicative; Fire (long palm, short fingers) = passionate, energetic; Water (long palm, long fingers) = intuitive, emotional, creative.
- Heart line: emotions, love style. Head line: thinking style. Life line: vitality and life changes (NEVER lifespan). Fate line: sense of purpose, career path.
- Left hand = inner self and natural potential; right hand = actions, career and how potential is used.

LINE TRACING (this is drawn on top of the photo, so precision matters more than anything else):
- Coordinates are integers on a 0-1000 grid over the WHOLE image as given: x = 0 at the left edge, 1000 at the right edge; y = 0 at the top edge, 1000 at the bottom edge. Do not mirror or rotate.
- First give palm_box: the tight box around the palm area (excluding fingers and wrist) on the same grid.
- For each line give 8-12 points lying exactly ON the visible crease, ordered from its start to its end, evenly spaced along the crease, following its real curvature. Never draw a straight line through the palm if the crease curves. Points must stay inside the palm.
- Heart line: the highest major horizontal crease, just under the finger bases; starts at the little-finger edge of the palm and runs toward the gap between index and middle finger.
- Head line: the horizontal crease below the heart line; starts on the thumb side (often joined with the life line between thumb and index finger) and runs across or slopes down toward the little-finger side.
- Life line: the curved crease that arcs around the thumb's fleshy base (Venus mount); starts between thumb and index finger and sweeps down toward the wrist centre.
- Fate line: the vertical crease in the middle of the palm running from near the wrist up toward the middle finger. Many palms have a faint or no fate line: then use low confidence and status "faint"/"not_visible" rather than guessing.
- confidence (0..1) = how sure you are the traced points sit on the real crease. Use < 0.4 if you cannot see it.

Writing style: second person, warm, specific to the observed features, 2-4 sentences per section, explain any jargon, uplifting but honest. Predictions must be soft, time-framed ranges ("in the next 1-2 years") and framed as possibilities. Tags, labels and chips are short (1-3 words). Emojis are single emoji characters.
Return JSON only matching the schema.`;
}

const str = { type: "string" };
const emojiText = { type: "object", properties: { emoji: str, text: str }, required: ["emoji", "text"] };
const grid = { type: "integer", minimum: 0, maximum: 1000 };

export const PALM_SCHEMA = {
  type: "object",
  properties: {
    headline: { type: "string", description: "One-sentence subtitle for 'Your Reading is Ready'" },
    palm_box: {
      type: "object",
      description: "Tight box around the palm (no fingers) on the 0-1000 image grid",
      properties: { ymin: grid, xmin: grid, ymax: grid, xmax: grid },
      required: ["ymin", "xmin", "ymax", "xmax"],
    },
    hand_type: {
      type: "object",
      properties: {
        element: { type: "string", enum: ["earth", "air", "fire", "water"] },
        tags: { type: "array", items: str, minItems: 3, maxItems: 4 },
        description: str,
      },
      required: ["element", "tags", "description"],
    },
    lines: {
      type: "array", minItems: 4, maxItems: 4,
      items: {
        type: "object",
        properties: {
          name: { type: "string", enum: ["heart", "head", "life", "fate"] },
          status: { type: "string", enum: ["strong", "clear", "balanced", "visible", "deep", "curved", "faint", "broken", "forked", "not_visible"] },
          observation: { type: "string", description: "What is visibly seen" },
          meaning: str,
          points: {
            type: "array", minItems: 2, maxItems: 14,
            description: "8-12 points on the crease, start to end, on the 0-1000 image grid",
            items: { type: "object", properties: { y: grid, x: grid }, required: ["y", "x"] },
          },
          confidence: { type: "number" },
        },
        required: ["name", "status", "observation", "meaning", "points", "confidence"],
      },
    },
    mounts: {
      type: "array",
      items: {
        type: "object",
        properties: {
          name: { type: "string", enum: ["jupiter", "saturn", "apollo", "mercury", "venus", "moon", "mars"] },
          prominence: { type: "string", enum: ["high", "medium", "low"] },
          meaning: str,
        },
        required: ["name", "prominence", "meaning"],
      },
    },
    overview: {
      type: "object",
      properties: { love: str, career: str, life_path: str, personality: str },
      required: ["love", "career", "life_path", "personality"],
      description: "One short line (max 12 words) each for the overview cards",
    },
    personality: {
      type: "object",
      properties: { traits: { type: "array", items: emojiText, minItems: 5, maxItems: 5 } },
      required: ["traits"],
    },
    love: {
      type: "object",
      properties: {
        summary: str,
        strengths: { type: "array", items: str, minItems: 3, maxItems: 3 },
        mindful_of: { type: "array", items: str, minItems: 2, maxItems: 2 },
        outlook: str,
        chip: { type: "string", description: "1 word, e.g. Positive" },
      },
      required: ["summary", "strengths", "mindful_of", "outlook", "chip"],
    },
    career: {
      type: "object",
      properties: {
        summary: str,
        best_areas: { type: "array", minItems: 4, maxItems: 4, items: { type: "object", properties: { emoji: str, label: str }, required: ["emoji", "label"] } },
        outlook: str,
        chip: { type: "string", description: "1 word, e.g. Growth" },
      },
      required: ["summary", "best_areas", "outlook", "chip"],
    },
    life_path: {
      type: "object",
      properties: {
        summary: str,
        predictions: { type: "array", items: emojiText, minItems: 4, maxItems: 4 },
        chip: { type: "string", description: "1 word, e.g. Bright" },
      },
      required: ["summary", "predictions", "chip"],
    },
    quote: { type: "string", description: "Short uplifting quote, max 15 words" },
    did_you_know: str,
    safety_flag: { type: "boolean" },
  },
  required: ["headline", "palm_box", "hand_type", "lines", "mounts", "overview", "personality", "love", "career", "life_path", "quote", "did_you_know", "safety_flag"],
};

export const RELATIONS: Record<string, string> = {
  partner: "partner", crush: "crush", friend: "friend", family: "family member", other: "someone they know",
};

export function palmUserPrompt(p: {
  hand: string; name: string; zodiac: string; focus: string[]; date: string; birth: string; relation?: string;
}) {
  const meaning = p.hand === "left" ? "inner self, natural personality" : "career, future, actions";
  const owner = p.relation
    ? `Palm owner: ${p.name || "unknown"}, the app user's ${RELATIONS[p.relation] ?? "someone they know"}.`
    : `Palm owner: the app user, ${p.name || "friend"}.`;
  return `Hand: ${p.hand} (${meaning}).
${owner} Zodiac: ${p.zodiac || "unknown"}. Birth details: ${p.birth}. Focus areas: ${p.focus.join(", ") || "general"}.
Today: ${p.date}.`;
}
