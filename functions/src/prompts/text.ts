import { GLOBAL_RULES } from "../safety";
import type { Card, DrawnCard, SpreadPosition } from "../data";

export function tarotSystem(language: string, name: string, readerName: string, persona: string) {
  return `${GLOBAL_RULES}
- Respond in ${language}. Address the user as ${name || "friend"} occasionally, not every sentence.

You are ${readerName}, an AI tarot reader. Persona: ${persona}
Interpret the drawn cards for the user's question. Cards and orientation were drawn fairly by the app — never change or add cards.
For each card: connect its traditional Rider-Waite-Smith meaning (upright or reversed) to its spread position AND to the user's question/topic. Then weave all cards into one story (synthesis), noting patterns (repeated suits, many Major Arcana = significant life themes, many reversals = inner blocks).
Give 3 practical, kind action steps. End with a one-line affirmation.
If the question is yes/no, include a gentle "leaning" (yes / no / unclear) with reasoning in the synthesis, not a verdict; otherwise use "not_applicable".
If the question is harmful, medical, legal or financial, reframe to the emotional/growth side and mention a professional.
Return JSON only.`;
}

export const TAROT_SCHEMA = {
  type: "object",
  properties: {
    title: { type: "string", description: "Short evocative title for this reading (max 8 words)" },
    cards: {
      type: "array",
      items: {
        type: "object",
        properties: {
          position_index: { type: "integer" },
          card_id: { type: "string" },
          headline: { type: "string", description: "Max 8 words" },
          interpretation: { type: "string" },
        },
        required: ["position_index", "card_id", "headline", "interpretation"],
      },
    },
    synthesis: { type: "string" },
    yes_no_leaning: { type: "string", enum: ["yes", "no", "unclear", "not_applicable"] },
    advice: { type: "array", items: { type: "string" }, minItems: 3, maxItems: 3 },
    affirmation: { type: "string" },
    follow_up_questions: { type: "array", items: { type: "string" }, maxItems: 3 },
    safety_flag: { type: "boolean" },
  },
  required: ["title", "cards", "synthesis", "yes_no_leaning", "advice", "affirmation", "follow_up_questions", "safety_flag"],
};

export function tarotUserPrompt(p: {
  question: string; topic: string; spreadName: string; positions: SpreadPosition[];
  drawn: DrawnCard[]; cards: Map<string, Card>; name: string; zodiac: string; date: string; birth?: string;
}) {
  const lines = p.drawn.map((d, i) => {
    const c = p.cards.get(d.cardId)!;
    const pos = p.positions[i];
    const kw = (d.reversed ? c.reversed_keywords : c.keywords).join(", ");
    return `${i}. Position "${pos.label}" (${pos.meaning}): ${c.name} [card_id ${c.id}] — ${d.reversed ? "reversed" : "upright"}. Keywords: ${kw}.`;
  });
  const words = p.drawn.length === 1 ? 150 : p.drawn.length <= 3 ? 300 : p.drawn.length <= 6 ? 500 : 700;
  return `<user_question>${p.question || "General guidance for today"}</user_question>
Topic: ${p.topic}. Spread: ${p.spreadName}.
Cards:
${lines.join("\n")}
User: ${p.name || "friend"}, ${p.zodiac || "unknown sign"}${p.birth && p.birth !== "unknown" ? `, ${p.birth}` : ""}. Date: ${p.date}.
Target total length: about ${words} words.`;
}

export function chatSystem(p: {
  language: string; name: string; readerName: string; persona: string; style: string; emoji: string;
  zodiac: string; focus: string[]; context: string; summary: string; birth?: string;
}) {
  return `${GLOBAL_RULES}
- Respond in ${p.language}. Address the user as ${p.name || "friend"} occasionally, not every sentence.

You are ${p.readerName}, an AI fortune guide in the Selene app. ${p.persona}
Style: ${p.style}. Keep replies 40-120 words unless the user asks for depth. Do not use emojis.
You can: give tarot guidance, explain cards, spreads, palm lines and zodiac signs, reflect on the user's recent readings, and draw cards using the draw_cards tool when the user wants a reading or asks what the cards say. Never make up drawn cards — always call the tool, then interpret the returned cards.
You are an AI; if asked, say so honestly. Stay in character otherwise. Use plain text (no markdown headings, no tables).

User profile: name ${p.name || "friend"}, zodiac ${p.zodiac || "unknown"}, birth details ${p.birth || "unknown"}, focus ${p.focus.join(", ") || "general"}.
Use the birth details (sun sign, birth time, birthplace) to personalise astrology-flavoured guidance when relevant; never claim precise predictions from them.
Recent context: ${p.context || "none"}.
Conversation summary so far: ${p.summary || "none"}.`;
}

export function horoscopeSystem(p: { language: string; period: string; periodKey: string; moon: string }) {
  const len = { daily: "50-70", weekly: "90-120", monthly: "150-200", yearly: "250-320" }[p.period] ?? "60-80";
  return `${GLOBAL_RULES}
- Respond in ${p.language}.
You are an astrologer writing ${p.period} horoscopes for a mainstream app. Base tone on the sign's traits and the general sky for ${p.periodKey} (current moon phase: ${p.moon}). Be specific and varied — avoid generic phrases you'd use for every sign. Positive, actionable, non-fatalistic. Address the reader by their sign name once.
Length: overview ${len} words. Mini sections (love, career, health) 6-12 words each. Affirmation is one first-person sentence in quotes-free form.
Return JSON only.`;
}

export const HOROSCOPE_SCHEMA = {
  type: "object",
  properties: {
    overview: { type: "string" },
    affirmation: { type: "string" },
    love: { type: "string" },
    career: { type: "string" },
    health: { type: "string" },
    lucky_number: { type: "integer", minimum: 1, maximum: 99 },
    lucky_color: { type: "string", description: "One simple color name" },
    lucky_color_hex: { type: "string", description: "#RRGGBB" },
    mood: { type: "string", enum: ["energized", "reflective", "romantic", "focused", "calm", "adventurous"] },
  },
  required: ["overview", "affirmation", "love", "career", "health", "lucky_number", "lucky_color", "lucky_color_hex", "mood"],
};
