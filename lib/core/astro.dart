import 'dart:math' as math;

/// Zodiac and moon helpers (mirrors functions/src/astro.ts).
class ZodiacSign {
  const ZodiacSign(this.id, this.name, this.range, this.symbol, this.startMonth, this.startDay);
  final String id, name, range, symbol;
  final int startMonth, startDay;
  String get image => 'assets/images/zodiac_$id.webp';
}

const zodiacSigns = <ZodiacSign>[
  ZodiacSign('aries', 'Aries', 'Mar 21 – Apr 19', '♈', 3, 21),
  ZodiacSign('taurus', 'Taurus', 'Apr 20 – May 20', '♉', 4, 20),
  ZodiacSign('gemini', 'Gemini', 'May 21 – Jun 20', '♊', 5, 21),
  ZodiacSign('cancer', 'Cancer', 'Jun 21 – Jul 22', '♋', 6, 21),
  ZodiacSign('leo', 'Leo', 'Jul 23 – Aug 22', '♌', 7, 23),
  ZodiacSign('virgo', 'Virgo', 'Aug 23 – Sep 22', '♍', 8, 23),
  ZodiacSign('libra', 'Libra', 'Sep 23 – Oct 22', '♎', 9, 23),
  ZodiacSign('scorpio', 'Scorpio', 'Oct 23 – Nov 21', '♏', 10, 23),
  ZodiacSign('sagittarius', 'Sagittarius', 'Nov 22 – Dec 21', '♐', 11, 22),
  ZodiacSign('capricorn', 'Capricorn', 'Dec 22 – Jan 19', '♑', 12, 22),
  ZodiacSign('aquarius', 'Aquarius', 'Jan 20 – Feb 18', '♒', 1, 20),
  ZodiacSign('pisces', 'Pisces', 'Feb 19 – Mar 20', '♓', 2, 19),
];

ZodiacSign signById(String? id) => zodiacSigns.firstWhere((s) => s.id == id, orElse: () => zodiacSigns.first);

/// Tropical sun sign for a birth date.
ZodiacSign sunSignFor(DateTime date) {
  final md = date.month * 100 + date.day;
  final sorted = [...zodiacSigns]..sort((a, b) => (a.startMonth * 100 + a.startDay).compareTo(b.startMonth * 100 + b.startDay));
  var found = signById('capricorn');
  for (final s in sorted) {
    if (s.startMonth * 100 + s.startDay <= md) found = s;
  }
  return found;
}

class MoonInfo {
  const MoonInfo(this.name, this.index, this.illumination, this.age);
  final String name;
  final int index;
  final double illumination;
  final double age;

  /// True while the lit side is on the right (northern hemisphere view).
  bool get waxing => age < _synodic / 2;
  String get meaning => moonMeanings[index];
}

const _synodic = 29.530588853;
final _refNewMoon = DateTime.utc(2000, 1, 6, 18, 14);

const moonPhaseNames = [
  'New Moon', 'Waxing Crescent', 'First Quarter', 'Waxing Gibbous',
  'Full Moon', 'Waning Gibbous', 'Last Quarter', 'Waning Crescent',
];

const moonMeanings = [
  'A time for new intentions and quiet beginnings.',
  'Take the first small steps toward your intentions.',
  'Push through challenges and make decisions.',
  'Refine your plans and trust the process.',
  'Celebrate what has grown and release what no longer serves you.',
  'Share your wisdom and practice gratitude.',
  'Let go, forgive and clear space.',
  'A time for reflection, release and setting new intentions.',
];

/// Approximate moon phase (±1 day) for the given moment.
MoonInfo moonPhase(DateTime date) {
  final days = date.toUtc().difference(_refNewMoon).inSeconds / 86400.0;
  final age = ((days % _synodic) + _synodic) % _synodic;
  final illumination = (1 - math.cos(2 * math.pi * age / _synodic)) / 2;
  final index = ((age / _synodic) * 8 + 0.5).floor() % 8;
  return MoonInfo(moonPhaseNames[index], index, illumination, age);
}
