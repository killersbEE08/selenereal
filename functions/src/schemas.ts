import { z } from "zod";

const emojiText = z.object({ emoji: z.string(), text: z.string() });
const point = z.object({ x: z.number(), y: z.number() });

export const PalmReadingZ = z.object({
  headline: z.string(),
  palm_box: z.object({ ymin: z.number(), xmin: z.number(), ymax: z.number(), xmax: z.number() }).optional(),
  hand_type: z.object({ element: z.enum(["earth", "air", "fire", "water"]), tags: z.array(z.string()).min(1), description: z.string() }),
  lines: z.array(z.object({
    name: z.enum(["heart", "head", "life", "fate"]),
    status: z.string(),
    observation: z.string(),
    meaning: z.string(),
    points: z.array(point),
    confidence: z.number(),
  })).min(1),
  mounts: z.array(z.object({ name: z.string(), prominence: z.string(), meaning: z.string() })),
  overview: z.object({ love: z.string(), career: z.string(), life_path: z.string(), personality: z.string() }),
  personality: z.object({ traits: z.array(emojiText) }),
  love: z.object({ summary: z.string(), strengths: z.array(z.string()), mindful_of: z.array(z.string()), outlook: z.string(), chip: z.string() }),
  career: z.object({ summary: z.string(), best_areas: z.array(z.object({ emoji: z.string(), label: z.string() })), outlook: z.string(), chip: z.string() }),
  life_path: z.object({ summary: z.string(), predictions: z.array(emojiText), chip: z.string() }),
  quote: z.string(),
  did_you_know: z.string(),
  safety_flag: z.boolean(),
});
export type PalmReading = z.infer<typeof PalmReadingZ>;

/**
 * Converts the model's 0-1000 grid to 0..1 (older readings already used 0..1), clamps everything,
 * drops points that fall well outside the palm box, removes near-duplicate points and keeps one
 * entry per line. Lines left with < 2 points get confidence 0 so the app doesn't draw them.
 */
export function normalizePalm(r: PalmReading): PalmReading {
  const clamp = (v: number) => Math.min(1, Math.max(0, Number.isFinite(v) ? v : 0));
  const all = [...r.lines.flatMap((l) => l.points.flatMap((p) => [p.x, p.y])), ...(r.palm_box ? Object.values(r.palm_box) : [])];
  const scale = all.some((v) => v > 1.5) ? 1000 : 1;
  const n = (v: number) => clamp(v / scale);

  let box: { ymin: number; xmin: number; ymax: number; xmax: number } | undefined;
  if (r.palm_box) {
    const b = { ymin: n(r.palm_box.ymin), xmin: n(r.palm_box.xmin), ymax: n(r.palm_box.ymax), xmax: n(r.palm_box.xmax) };
    // Only trust a sensible box (at least 15% of the image in each direction).
    if (b.xmax - b.xmin > 0.15 && b.ymax - b.ymin > 0.15) box = b;
  }
  const PAD = 0.08;
  const inBox = (p: { x: number; y: number }) =>
    !box || (p.x >= box.xmin - PAD && p.x <= box.xmax + PAD && p.y >= box.ymin - PAD && p.y <= box.ymax + PAD);

  const seen = new Set<string>();
  const lines = r.lines.filter((l) => (seen.has(l.name) ? false : (seen.add(l.name), true))).map((l) => {
    const pts: { x: number; y: number }[] = [];
    for (const raw of l.points) {
      const p = { x: n(raw.x), y: n(raw.y) };
      if (!inBox(p)) continue;
      const last = pts[pts.length - 1];
      if (last && Math.hypot(last.x - p.x, last.y - p.y) < 0.004) continue;
      pts.push(p);
    }
    return { ...l, confidence: pts.length >= 2 ? clamp(l.confidence) : 0, points: pts };
  });
  const { palm_box: _raw, ...rest } = r;
  return { ...rest, ...(box ? { palm_box: box } : {}), lines };
}

export const TarotZ = z.object({
  title: z.string(),
  cards: z.array(z.object({ position_index: z.number().int(), card_id: z.string(), headline: z.string(), interpretation: z.string() })),
  synthesis: z.string(),
  yes_no_leaning: z.enum(["yes", "no", "unclear", "not_applicable"]),
  advice: z.array(z.string()),
  affirmation: z.string(),
  follow_up_questions: z.array(z.string()),
  safety_flag: z.boolean(),
});
export type TarotInterpretation = z.infer<typeof TarotZ>;

export const HoroscopeZ = z.object({
  overview: z.string(),
  affirmation: z.string(),
  love: z.string(),
  career: z.string(),
  health: z.string(),
  lucky_number: z.number().int(),
  lucky_color: z.string(),
  lucky_color_hex: z.string(),
  mood: z.string(),
});
export type Horoscope = z.infer<typeof HoroscopeZ>;
