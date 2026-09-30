import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/astro.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../data/api.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userDocProvider).value;
    final premium = ref.watch(isPremiumProvider);
    final top = MediaQuery.of(context).padding.top;
    final w = MediaQuery.of(context).size.width;
    final moon = moonPhase(DateTime.now());
    final tiles = [
      ('assets/images/tarot_sun_star_moon.webp', 'Tarot Reading', 'Reveal what’s next', '/tarot'),
      ('assets/images/zodiac_wheel.webp', 'Horoscope', 'Daily insights & moon calendar', '/horoscope'),
      ('assets/images/palm_aura.webp', 'AI Palm Reading', 'Discover your life path', '/palm'),
      ('assets/images/grimoire.webp', 'Card Meanings', 'Learn & get insights', '/cards'),
      ('assets/images/tarot_trio.webp', 'Tarot Spreads', 'Explore & create spreads', '/spreads'),
      ('assets/images/readers_trio.webp', 'AI Readers', 'Choose your guide', '/readers'),
    ];

    return ListView(padding: const EdgeInsets.only(bottom: 110), children: [
      // Hero — minHeight (not fixed) so long headings / large system font sizes grow it instead of overflowing.
      ConstrainedBox(
        constraints: BoxConstraints(minHeight: 440 + top),
        child: Stack(children: [
          Positioned(
            right: -w * 0.22,
            top: top + 10,
            bottom: 0,
            width: w * 1.05,
            child: ShaderMask(
              shaderCallback: (r) => const LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [Colors.transparent, Colors.black], stops: [0.08, 0.45]).createShader(r),
              blendMode: BlendMode.dstIn,
              child: ShaderMask(
                shaderCallback: (r) => const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black, Colors.black, Colors.transparent], stops: [0, 0.7, 1]).createShader(r),
                blendMode: BlendMode.dstIn,
                child: Image.asset('assets/images/hero_home.webp', fit: BoxFit.cover, alignment: Alignment.centerRight, excludeFromSemantics: true),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, top + 12, 16, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const AppIcon(Ic.moonStarsFill, color: AppColors.gold, size: 24),
                const SizedBox(width: 8),
                Expanded(child: Text('Selene', style: AppType.display(size: 24, weight: FontWeight.w500))),
                CircleIconButton(icon: Ic.history, tooltip: 'My readings', onTap: () => context.push('/readings')),
              ]),
              const SizedBox(height: 56),
              Text(
                (user != null && user.firstName.isNotEmpty ? 'Good ${_partOfDay()}, ${user.firstName}' : 'Good ${_partOfDay()}').toUpperCase(),
                style: AppType.overline(color: AppColors.gold),
              ),
              const SizedBox(height: 10),
              SizedBox(width: w * 0.6, child: const GradientHeading('Your answers', 'await', size: 40)),
              const SizedBox(height: 12),
              SizedBox(
                width: w * 0.56,
                child: Text('Tarot, the stars and your palm, read for you. Whenever you need a little clarity.',
                    style: AppType.ui(size: 14, weight: FontWeight.w400, color: AppColors.textSecondary, height: 1.5)),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: w * 0.62,
                child: GradientButton(
                  label: 'Ask Selene',
                  icon: Ic.chat,
                  onPressed: () => context.push('/chat/${user?.preferredReaderId ?? 'selene'}'),
                ),
              ),
              const SizedBox(height: 14),
              Row(children: [
                MoonGlyph(moon: moon, size: 18),
                const SizedBox(width: 8),
                Text('${moon.name} · ${(moon.illumination * 100).round()}% lit', style: AppType.ui(size: 12, weight: FontWeight.w600, color: AppColors.textSecondary)),
              ]),
            ]),
          ),
        ]),
      ),
      // Feature grid
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.72,
          children: [
            for (final t in tiles) FeatureTile(image: t.$1, title: t.$2, subtitle: t.$3, onTap: () => context.push(t.$4)),
          ],
        ),
      ),
      if (!premium)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
          child: GlowCard(
            padding: EdgeInsets.zero,
            onTap: () => context.push('/paywall'),
            child: Stack(children: [
              Positioned.fill(child: Image.asset('assets/images/cloud_moon.webp', fit: BoxFit.cover, opacity: const AlwaysStoppedAnimation(0.35))),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  const IconBadge(Ic.crownFill, color: AppColors.gold, size: 48, circle: true),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Selene Premium', style: AppType.display(size: 18, weight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      Text('Unlimited readings, every spread, deeper guidance.', style: AppType.ui(size: 12.5, weight: FontWeight.w400, color: AppColors.textSecondary)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(gradient: AppColors.cta, borderRadius: BorderRadius.circular(999)),
                    child: Text('Explore', style: AppType.ui(size: 13, weight: FontWeight.w800, color: AppColors.onGold)),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      SectionTitle('Today’s sky', overline: 'Daily', action: 'See more', onAction: () => context.go('/horoscope')),
      SizedBox(
        height: 110,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
          _VibeCard(
            leading: Image.asset('assets/images/card_back.webp', width: 40),
            title: 'Daily Tarot',
            body: 'A new message for you',
            onTap: () => showDailyCard(context),
          ),
          _VibeCard(
            leading: MoonGlyph(moon: moon, size: 46),
            title: 'Moon Phase',
            body: '${moon.name}\n${moon.meaning.split(' ').take(4).join(' ')}…',
            onTap: () => context.go('/horoscope'),
          ),
          _VibeCard(
            leading: const IconBadge(Ic.starFill, color: AppColors.gold, size: 40, circle: true),
            title: 'Daily Horoscope',
            body: user?.zodiac == null ? 'Your zodiac insights' : '${signById(user!.zodiac).name} insights',
            onTap: () => context.go('/horoscope'),
          ),
        ]),
      ),
      const DisclaimerText(),
    ]);
  }
}

String _partOfDay([DateTime? now]) {
  final h = (now ?? DateTime.now()).hour;
  return h < 5 ? 'evening' : h < 12 ? 'morning' : h < 17 ? 'afternoon' : 'evening';
}

class _VibeCard extends StatelessWidget {
  const _VibeCard({required this.leading, required this.title, required this.body, required this.onTap});
  final Widget leading;
  final String title, body;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 10),
        child: SizedBox(
          width: 200,
          child: GlowCard(
            onTap: onTap,
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              leading,
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(body, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ]),
              ),
              const ArrowDot(size: 24),
            ]),
          ),
        ),
      );
}

/// Draws a moon with the correct illuminated fraction.
class MoonGlyph extends StatelessWidget {
  const MoonGlyph({super.key, required this.moon, this.size = 40});
  final MoonInfo moon;
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
        label: '${moon.name}, ${(moon.illumination * 100).round()} percent illuminated',
        child: CustomPaint(size: Size.square(size), painter: _MoonPainter(moon.illumination, moon.waxing)),
      );
}

class _MoonPainter extends CustomPainter {
  _MoonPainter(this.illum, this.waxing);
  final double illum;
  final bool waxing;
  @override
  void paint(Canvas canvas, Size s) {
    final r = s.width / 2;
    final c = Offset(r, r);
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF26223F));
    canvas.drawCircle(c, r + 2, Paint()
      ..color = AppColors.gold.withValues(alpha: 0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    // Lit region = half disc + ellipse whose width depends on illumination.
    final lit = Path();
    final rect = Rect.fromCircle(center: c, radius: r);
    final ew = (2 * illum - 1).abs() * r;
    final half = Path()..addArc(rect, waxing ? -1.5708 : 1.5708, 3.14159);
    final ellipse = Path()..addOval(Rect.fromCenter(center: c, width: ew * 2, height: r * 2));
    if (illum >= 0.5) {
      lit.addPath(Path.combine(PathOperation.union, half, ellipse), Offset.zero);
    } else {
      lit.addPath(Path.combine(PathOperation.difference, half, ellipse), Offset.zero);
    }
    canvas.drawPath(lit, Paint()..shader = const RadialGradient(colors: [Color(0xFFFFF8E8), Color(0xFFEAD9B2)]).createShader(rect));
  }

  @override
  bool shouldRepaint(_MoonPainter o) => o.illum != illum || o.waxing != waxing;
}

/// Bottom sheet with today's card and personal message (Cloud Function `getDailyCard`).
Future<void> showDailyCard(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _DailyCardSheet(),
    );

class _DailyCardSheet extends ConsumerStatefulWidget {
  const _DailyCardSheet();
  @override
  ConsumerState<_DailyCardSheet> createState() => _DailyCardSheetState();
}

class _DailyCardSheetState extends ConsumerState<_DailyCardSheet> {
  bool _revealed = false;
  @override
  Widget build(BuildContext context) {
    final daily = ref.watch(dailyCardProvider);
    final cards = ref.watch(cardMapProvider).value;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: daily.when(
          loading: () => const SizedBox(height: 300, child: Loading()),
          error: (e, _) => MascotMessage(title: 'The stars are cloudy', message: friendlyError(e, 'Could not load today’s card. Check your connection.'), action: 'Try again', onAction: () => ref.invalidate(dailyCardProvider)),
          data: (d) {
            final card = cards?[d['cardId']];
            if (card == null) return const SizedBox(height: 300, child: Loading());
            final reversed = d['reversed'] == true;
            return Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Your Card for Today', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => setState(() => _revealed = true),
                child: TarotCardView(image: card.image, reversed: reversed, faceUp: _revealed, width: 140, label: card.name),
              ),
              const SizedBox(height: 12),
              if (!_revealed)
                const Text('Tap the card to reveal', style: TextStyle(color: AppColors.textSecondary))
              else ...[
                Text('${card.name}${reversed ? ' (Reversed)' : ''}', style: Theme.of(context).textTheme.titleMedium!.copyWith(color: AppColors.gold)),
                const SizedBox(height: 8),
                Text('${d['message'] ?? ''}', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 12),
                OutlinePillButton(
                  label: 'Learn about this card',
                  icon: Ic.book,
                  onPressed: () {
                    Navigator.pop(context);
                    context.push('/cards/${card.id}');
                  },
                ),
              ],
            ]);
          },
        ),
      ),
    );
  }
}
