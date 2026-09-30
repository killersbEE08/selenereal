/** Astronomy helpers (approximate, ±1 day), shared with the Flutter implementation. */
const SYNODIC = 29.530588853;
const REF_NEW_MOON = Date.UTC(2000, 0, 6, 18, 14);

export const PHASES = ["New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous", "Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent"];

export function moonPhase(date: Date) {
  const days = (date.getTime() - REF_NEW_MOON) / 86400000;
  const age = ((days % SYNODIC) + SYNODIC) % SYNODIC;
  const illumination = (1 - Math.cos((2 * Math.PI * age) / SYNODIC)) / 2;
  const index = Math.floor(((age / SYNODIC) * 8 + 0.5)) % 8;
  return { age, illumination, name: PHASES[index], index };
}

export const SIGNS = [
  { id: "aries", name: "Aries", range: "Mar 21 – Apr 19", start: [3, 21] },
  { id: "taurus", name: "Taurus", range: "Apr 20 – May 20", start: [4, 20] },
  { id: "gemini", name: "Gemini", range: "May 21 – Jun 20", start: [5, 21] },
  { id: "cancer", name: "Cancer", range: "Jun 21 – Jul 22", start: [6, 21] },
  { id: "leo", name: "Leo", range: "Jul 23 – Aug 22", start: [7, 23] },
  { id: "virgo", name: "Virgo", range: "Aug 23 – Sep 22", start: [8, 23] },
  { id: "libra", name: "Libra", range: "Sep 23 – Oct 22", start: [9, 23] },
  { id: "scorpio", name: "Scorpio", range: "Oct 23 – Nov 21", start: [10, 23] },
  { id: "sagittarius", name: "Sagittarius", range: "Nov 22 – Dec 21", start: [11, 22] },
  { id: "capricorn", name: "Capricorn", range: "Dec 22 – Jan 19", start: [12, 22] },
  { id: "aquarius", name: "Aquarius", range: "Jan 20 – Feb 18", start: [1, 20] },
  { id: "pisces", name: "Pisces", range: "Feb 19 – Mar 20", start: [2, 19] },
] as const;

export function sunSign(month: number, day: number): string {
  const md = month * 100 + day;
  let found: string = "capricorn";
  // Sorted by calendar start; the last start <= md wins, otherwise Capricorn (Dec 22 – Jan 19).
  const byStart = [...SIGNS].sort((a, b) => a.start[0] * 100 + a.start[1] - (b.start[0] * 100 + b.start[1]));
  for (const s of byStart) if (s.start[0] * 100 + s.start[1] <= md) found = s.id;
  return found;
}

/** ISO week key like 2026-W39. */
export function isoWeekKey(d: Date): string {
  const t = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const dayNum = t.getUTCDay() || 7;
  t.setUTCDate(t.getUTCDate() + 4 - dayNum);
  const yearStart = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
  const week = Math.ceil(((t.getTime() - yearStart.getTime()) / 86400000 + 1) / 7);
  return `${t.getUTCFullYear()}-W${String(week).padStart(2, "0")}`;
}

export type Period = "daily" | "weekly" | "monthly" | "yearly";
export function periodKey(period: Period, d: Date): string {
  const iso = d.toISOString();
  switch (period) {
    case "daily": return iso.slice(0, 10);
    case "weekly": return isoWeekKey(d);
    case "monthly": return iso.slice(0, 7);
    case "yearly": return iso.slice(0, 4);
  }
}
