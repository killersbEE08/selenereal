import { createHash, randomInt } from "node:crypto";
import cardsJson from "./data/cards.json";
import spreadsJson from "./data/spreads.json";
import readersJson from "./data/readers.json";

export interface Card {
  id: string; name: string; number: number; roman: string; arcana: "major" | "minor"; suit: string | null;
  element: string; astrology: string; keywords: string[]; reversed_keywords: string[];
  description: string; upright: string; reversed: string; symbolism: string; love: string; career: string; yes_no: string;
}
export interface SpreadPosition { index: number; label: string; meaning: string }
export interface Spread { id: string; name: string; subtitle: string; premium: boolean; positions: SpreadPosition[] }
export interface Reader {
  id: string; name: string; tags: string[]; persona: string; style: string; emoji: string; premium: boolean; greeting: string;
}

export const CARDS = cardsJson as Card[];
export const SPREADS = spreadsJson as unknown as Spread[];
export const READERS = readersJson as unknown as Reader[];
export const cardById = new Map(CARDS.map((c) => [c.id, c]));

export interface DrawnCard { cardId: string; reversed: boolean }

/** Fair draw: Fisher–Yates with a CSPRNG, unique cards. `rand(n)` returns an int in [0, n). */
export function drawCards(count: number, reversalProbability: number, rand: (n: number) => number = randomInt): DrawnCard[] {
  if (count < 1 || count > CARDS.length) throw new Error("invalid count");
  const ids = CARDS.map((c) => c.id);
  for (let i = ids.length - 1; i > 0; i--) {
    const j = rand(i + 1);
    [ids[i], ids[j]] = [ids[j], ids[i]];
  }
  return ids.slice(0, count).map((cardId) => ({ cardId, reversed: rand(1000) < reversalProbability * 1000 }));
}

/** Deterministic daily card per user and date. */
export function dailyCardFor(uid: string, date: string): DrawnCard {
  const h = createHash("sha256").update(`${uid}:${date}`).digest();
  return { cardId: CARDS[h.readUInt32BE(0) % CARDS.length].id, reversed: h[4] < 0.3 * 256 };
}
