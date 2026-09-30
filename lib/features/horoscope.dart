import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../core/astro.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../data/api.dart';
import 'home.dart' show MoonGlyph;

class HoroscopeScreen extends ConsumerStatefulWidget {
  const HoroscopeScreen({super.key});
  @override
  ConsumerState<HoroscopeScreen> createState() => _HoroscopeState();
}

class _HoroscopeState extends ConsumerState<HoroscopeScreen> {
  String? _sign;
  int _period = 0;
  late DateTime _weekStart = _mondayOf(DateTime.now());
  DateTime _selectedDay = DateTime.now();
  static const _periods = ['daily', 'weekly', 'monthly', 'yearly'];

  static DateTime _mondayOf(DateTime d) => DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

  void _changeSign() => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Choose a Sign', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Flexible(
              child: GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.9,
                children: [
                for (final s in zodiacSigns)
                  GlowCard(
                    padding: const EdgeInsets.all(6),
                    selected: s.id == _sign,
                    onTap: () {
                      setState(() => _sign = s.id);
                      Navigator.pop(context);
                    },
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Image.asset(s.image, height: 64),
                      Text(s.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                      Text(s.range, style: const TextStyle(color: AppColors.textMuted, fontSize: 9.5)),
                    ]),
                  ),
              ],
              ),
            ),
          ]),
        ),
      );

  void _setPeriod(int i) {
    if (i > 0 && !ref.read(isPremiumProvider)) {
      context.push('/paywall');
      return;
    }
    setState(() => _period = i);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userDocProvider).value;
    final sign = signById(_sign ?? user?.zodiac ?? 'aries');
    final premium = ref.watch(isPremiumProvider);
    final period = _periods[_period];
    final h = ref.watch(horoscopeProvider((sign.id, period)));
    final today = DateTime.now();
    final moon = moonPhase(_selectedDay);

    return ListView(padding: const EdgeInsets.only(bottom: 110), children: [
      HeroHeader(
        title: 'Horoscope',
        subtitle: 'Daily insights & moon calendar',
        image: 'assets/images/hero_horoscope.webp',
        headingLead: 'Your Cosmic Guide for',
        headingAccent: 'Today',
        description: 'Personalized insights based on your zodiac sign and the current cosmic energy.',
        showBack: false,
        height: 360,
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: GlowCard(
          onTap: _changeSign,
          child: Row(children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)), color: AppColors.gold.withValues(alpha: 0.08)),
              child: ClipOval(child: Image.asset(sign.image, fit: BoxFit.cover, excludeFromSemantics: true)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(sign.name, style: Theme.of(context).textTheme.headlineSmall),
                Text(sign.range, style: const TextStyle(color: AppColors.textSecondary)),
              ]),
            ),
            const SizedBox(width: 8),
            OutlinePillButton(label: 'Change', icon: Ic.transfer, onPressed: _changeSign),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SegmentedTabs(
          labels: const ['Today', 'Week', 'Month', 'Year'],
          icons: [null, if (premium) ...[null, null, null] else ...[Ic.lockFill, Ic.lockFill, Ic.lockFill]],
          index: _period,
          onChanged: _setPeriod,
        ),
      ),
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: h.when(
          loading: () => const GlowCard(child: SizedBox(height: 220, child: Loading())),
          error: (e, _) => GlowCard(
            child: MascotMessage(title: 'The stars are aligning', message: friendlyError(e, 'Could not load your horoscope. Check your connection.'), action: 'Try again', onAction: () => ref.invalidate(horoscopeProvider((sign.id, period)))),
          ),
          data: (d) => _HoroscopeCard(d: d, sign: sign, period: period),
        ),
      ),
      const SizedBox(height: 12),
      // Moon phase
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: GlowCard(
          child: Row(children: [
            MoonGlyph(moon: moon, size: 80),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(DateUtils.isSameDay(_selectedDay, today) ? 'Today’s Moon Phase' : DateFormat.MMMd().format(_selectedDay),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                Text(moon.name, style: Theme.of(context).textTheme.titleLarge),
                Text(moon.meaning, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                const SizedBox(height: 8),
                Text('Illumination ${(moon.illumination * 100).round()}%', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(value: moon.illumination, minHeight: 6, color: AppColors.gold, backgroundColor: AppColors.border),
                ),
              ]),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      // Moon calendar (week strip)
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: GlowCard(
          child: Column(children: [
            Row(children: [
              const AppIcon(Ic.moon, color: AppColors.gold),
              const SizedBox(width: 8),
              Text('Moon Calendar', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              Text(DateFormat.yMMMM().format(_weekStart.add(const Duration(days: 3))), style: const TextStyle(color: AppColors.gold, fontSize: 13)),
              IconButton(tooltip: 'Previous week', onPressed: () => setState(() => _weekStart = _weekStart.subtract(const Duration(days: 7))), icon: const AppIcon(Ic.left, color: Colors.white)),
              IconButton(tooltip: 'Next week', onPressed: () => setState(() => _weekStart = _weekStart.add(const Duration(days: 7))), icon: const AppIcon(Ic.right, color: Colors.white)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              for (var i = 0; i < 7; i++)
                Expanded(child: _DayCell(day: _weekStart.add(Duration(days: i)), selected: DateUtils.isSameDay(_weekStart.add(Duration(days: i)), _selectedDay), onTap: (d) => setState(() => _selectedDay = d))),
            ]),
          ]),
        ),
      ),
      const DisclaimerText(),
    ]);
  }
}

class _HoroscopeCard extends StatelessWidget {
  const _HoroscopeCard({required this.d, required this.sign, required this.period});
  final Map<String, dynamic> d;
  final ZodiacSign sign;
  final String period;
  @override
  Widget build(BuildContext context) {
    final title = {'daily': 'Today’s Horoscope', 'weekly': 'This Week', 'monthly': 'This Month', 'yearly': 'This Year'}[period]!;
    Color lucky;
    try {
      lucky = Color(int.parse('FF${'${d['lucky_color_hex']}'.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      lucky = AppColors.magenta;
    }
    return GlowCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
          Text('${d['periodKey'] ?? ''}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ]),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text('${d['overview'] ?? ''}', style: const TextStyle(color: Colors.white, height: 1.5))),
          const SizedBox(width: 8),
          Image.asset(sign.image, width: 88, excludeFromSemantics: true),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.gold.withValues(alpha: 0.3))),
          child: Row(children: [
            const AppIcon(Ic.quote, size: 24, color: AppColors.gold),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Affirmation', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                Text('“${d['affirmation'] ?? ''}”', style: const TextStyle(color: AppColors.textSecondary, fontStyle: FontStyle.italic)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        // Full-width rows: AI text length varies a lot, so the cards must size to their content
        // (a fixed-aspect grid clipped/overflowed long Love/Career/Health text).
        for (final (icon, label, key, color) in const [(Ic.heart, 'Love', 'love', AppColors.heart), (Ic.briefcase, 'Career', 'career', AppColors.gold), (Ic.leaf, 'Health', 'health', AppColors.success)])
          if ('${d[key] ?? ''}'.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InsightCard(icon: icon, title: label, color: color, body: '${d[key]}'),
            ),
        GlowCard(
          padding: const EdgeInsets.all(12),
          child: Wrap(spacing: 16, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              const AppIcon(Ic.starFill, size: 16, color: AppColors.gold),
              const SizedBox(width: 6),
              const Text('Lucky Number ', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              Text('${d['lucky_number'] ?? ''}', style: const TextStyle(color: AppColors.gold, fontSize: 16, fontWeight: FontWeight.w700)),
            ]),
            Row(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(radius: 8, backgroundColor: lucky),
              const SizedBox(width: 6),
              Flexible(child: Text('Lucky Color: ${d['lucky_color'] ?? ''}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13))),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.selected, required this.onTap});
  final DateTime day;
  final bool selected;
  final ValueChanged<DateTime> onTap;
  @override
  Widget build(BuildContext context) {
    final m = moonPhase(DateTime(day.year, day.month, day.day, 12));
    return GestureDetector(
      onTap: () => onTap(day),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.gold : AppColors.border, width: selected ? 1.4 : 1),
          color: selected ? AppColors.cardElevated : Colors.transparent,
        ),
        child: Column(children: [
          Text(DateFormat.E().format(day), style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          Text('${day.day}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          MoonGlyph(moon: m, size: 26),
          const SizedBox(height: 4),
          Text(m.name.replaceFirst(' ', '\n'), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted, fontSize: 8.5, height: 1.1)),
        ]),
      ),
    );
  }
}
