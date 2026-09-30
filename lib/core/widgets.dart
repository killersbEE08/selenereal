import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/api.dart' show ApiException;
import 'icons.dart';
import 'theme.dart';

export 'icons.dart';

/// Full-screen night-sky background used by every screen: ink gradient, two faint nebula
/// glows and a slow star twinkle (static when the OS asks for reduced motion).
class CosmicBackground extends StatelessWidget {
  const CosmicBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.background),
      child: Stack(children: [
        const Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(center: Alignment(-0.9, -0.85), radius: 1.1, colors: [Color(0x336E56CF), Color(0x00000000)]),
              ),
            ),
          ),
        ),
        const Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(center: Alignment(1.1, 0.7), radius: 0.9, colors: [Color(0x1FF2A7C3), Color(0x00000000)]),
              ),
            ),
          ),
        ),
        Positioned.fill(child: IgnorePointer(child: reduce ? const CustomPaint(painter: _StarPainter(0)) : const _Twinkle())),
        child,
      ]),
    );
  }
}

class _Twinkle extends StatefulWidget {
  const _Twinkle();
  @override
  State<_Twinkle> createState() => _TwinkleState();
}

class _TwinkleState extends State<_Twinkle> with SingleTickerProviderStateMixin {
  late final c = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: AnimatedBuilder(animation: c, builder: (_, _) => CustomPaint(painter: _StarPainter(c.value))),
      );
}

class _StarPainter extends CustomPainter {
  const _StarPainter(this.t);
  final double t;
  @override
  void paint(Canvas canvas, Size size) {
    final r = math.Random(11);
    final p = Paint();
    for (var i = 0; i < 60; i++) {
      final x = r.nextDouble() * size.width, y = r.nextDouble() * size.height;
      final phase = r.nextDouble();
      final a = 0.18 + 0.5 * (0.5 + 0.5 * math.sin(2 * math.pi * (t + phase)));
      final warm = i % 7 == 0;
      p.color = (warm ? const Color(0xFFF5DDAA) : Colors.white).withValues(alpha: a * (i % 4 == 0 ? 0.9 : 0.5));
      canvas.drawCircle(Offset(x, y), i % 11 == 0 ? 1.4 : 0.8, p);
    }
  }

  @override
  bool shouldRepaint(_StarPainter old) => old.t != t;
}

/// Primary call to action: gilt pill with ink text.
class GradientButton extends StatelessWidget {
  const GradientButton({super.key, required this.label, this.onPressed, this.icon = Ic.sparkles, this.trailing = true, this.loading = false, this.height = 56});
  final String label;
  final VoidCallback? onPressed;
  final String? icon;
  final bool trailing, loading;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: enabled || loading ? 1 : 0.45,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            gradient: AppColors.cta,
            borderRadius: BorderRadius.circular(999),
            boxShadow: enabled ? [BoxShadow(color: AppColors.gold.withValues(alpha: 0.28), blurRadius: 22, offset: const Offset(0, 8))] : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              splashColor: Colors.white24,
              onTap: enabled ? onPressed : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  if (trailing) const SizedBox(width: 24),
                  Expanded(
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      if (loading)
                        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.onGold))
                      else if (icon != null)
                        AppIcon(icon!, color: AppColors.onGold, size: 20),
                      if (loading || icon != null) const SizedBox(width: 10),
                      Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: AppType.ui(size: 16, weight: FontWeight.w700, color: AppColors.onGold))),
                    ]),
                  ),
                  if (trailing) const AppIcon(Ic.arrowRight, color: AppColors.onGold, size: 20),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OutlinePillButton extends StatelessWidget {
  const OutlinePillButton({super.key, required this.label, required this.onPressed, this.icon});
  final String label;
  final VoidCallback? onPressed;
  final String? icon;
  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text,
          minimumSize: const Size(48, 48),
          side: const BorderSide(color: AppColors.borderStrong),
          backgroundColor: const Color(0x0DFFFFFF),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          textStyle: AppType.ui(size: 13.5, weight: FontWeight.w600),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[AppIcon(icon!, size: 17, color: onPressed == null ? AppColors.textMuted : AppColors.text), const SizedBox(width: 7)],
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ]),
      );
}

/// Selectable pill chip: quiet when idle, lavender-tinted when selected.
class PillChip extends StatelessWidget {
  const PillChip({super.key, required this.label, this.selected = false, this.onTap, this.leading, this.icon, this.dense = false});
  final String label;
  final bool selected, dense;
  final VoidCallback? onTap;
  final Widget? leading;
  final String? icon;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            constraints: const BoxConstraints(minHeight: 40),
            padding: EdgeInsets.symmetric(horizontal: dense ? 13 : 16, vertical: dense ? 7 : 9),
            decoration: BoxDecoration(
              color: selected ? AppColors.glow.withValues(alpha: 0.16) : const Color(0x0AFFFFFF),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: selected ? AppColors.glow.withValues(alpha: 0.75) : AppColors.border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[AppIcon(icon!, size: dense ? 15 : 17, color: selected ? AppColors.glow : AppColors.textSecondary), const SizedBox(width: 7)],
              if (leading != null) ...[leading!, const SizedBox(width: 6)],
              Flexible(
                child: Text(label,
                    style: AppType.ui(size: dense ? 12.5 : 13.5, weight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? AppColors.text : AppColors.textSecondary)),
              ),
            ]),
          ),
        ),
      );
}

/// Horizontal scroll of chips.
class ChipRow extends StatelessWidget {
  const ChipRow({super.key, required this.children, this.padding = const EdgeInsets.symmetric(horizontal: 16)});
  final List<Widget> children;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 46,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: padding,
          itemCount: children.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) => Center(child: children[i]),
        ),
      );
}

/// Glass card with a hairline border; lavender edge + soft glow when selected.
class GlowCard extends StatelessWidget {
  const GlowCard({super.key, required this.child, this.selected = false, this.padding = const EdgeInsets.all(16), this.onTap, this.radius = AppRadius.card, this.color});
  final Widget child;
  final bool selected;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: color ?? (selected ? AppColors.cardElevated : AppColors.card),
          gradient: color == null && !selected
              ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xF0171433), Color(0xE60F0D22)])
              : null,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: selected ? AppColors.glow.withValues(alpha: 0.85) : AppColors.border, width: selected ? 1.4 : 1),
          boxShadow: selected ? [BoxShadow(color: AppColors.glow.withValues(alpha: 0.22), blurRadius: 24)] : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Material(
            color: Colors.transparent,
            child: InkWell(onTap: onTap, splashColor: AppColors.glow.withValues(alpha: 0.08), highlightColor: Colors.white.withValues(alpha: 0.03), child: Padding(padding: padding, child: child)),
          ),
        ),
      );
}

/// Serif heading with the accent word in gilt italic ("Your destiny in your *hands*").
class GradientHeading extends StatelessWidget {
  const GradientHeading(this.lead, this.accent, {super.key, this.size = 36, this.sparkle = false, this.textAlign});
  final String lead, accent;
  final double size;
  final bool sparkle;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final style = AppType.display(size: size, weight: FontWeight.w500);
    return Text.rich(
      textAlign: textAlign,
      TextSpan(children: [
        TextSpan(text: lead.isEmpty ? '' : '$lead ', style: style),
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: ShaderMask(
            shaderCallback: (r) => AppColors.headingGradient.createShader(r),
            child: Text(accent, style: style.copyWith(color: Colors.white, fontStyle: FontStyle.italic, fontWeight: FontWeight.w600)),
          ),
        ),
        if (sparkle)
          WidgetSpan(
            alignment: PlaceholderAlignment.top,
            child: Padding(padding: const EdgeInsets.only(left: 4), child: AppIcon(Ic.sparklesFill, size: size * 0.42, color: AppColors.gold)),
          ),
      ]),
    );
  }
}

class CircleIconButton extends StatelessWidget {
  const CircleIconButton({super.key, required this.icon, required this.onTap, this.tooltip, this.badge = false, this.color});
  final String icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool badge;
  final Color? color;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: tooltip,
        child: InkResponse(
          onTap: onTap,
          radius: 28,
          // 48dp minimum tap target (WCAG / Material) while the visible circle stays 46.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0x99121027), border: Border.all(color: AppColors.border)),
                child: Center(child: AppIcon(icon, color: color ?? AppColors.text, size: 21)),
              ),
              if (badge) const Positioned(right: 3, top: 3, child: CircleAvatar(radius: 5, backgroundColor: AppColors.gold)),
            ]),
          ),
        ),
      );
}

/// Hero header used across feature screens: back button, title, subtitle, right action, character art, big heading.
class HeroHeader extends StatelessWidget {
  const HeroHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.image,
    required this.headingLead,
    required this.headingAccent,
    required this.description,
    this.action,
    this.showBack = true,
    this.height = 380,
    this.imageAlignment = Alignment.centerRight,
  });
  final String title, subtitle, image, headingLead, headingAccent, description;
  final Widget? action;
  final bool showBack;
  final double height;
  final Alignment imageAlignment;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final width = MediaQuery.of(context).size.width;
    // minHeight (not a fixed height) so long headings / large system font sizes grow the header
    // instead of overflowing it.
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: height + top, minWidth: width),
      child: Stack(children: [
        Positioned(
          right: -width * 0.12,
          top: top + 40,
          bottom: 0,
          width: width * 0.92,
          child: ShaderMask(
            shaderCallback: (r) => const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Colors.transparent, Colors.black, Colors.black],
              stops: [0, 0.4, 1],
            ).createShader(r),
            blendMode: BlendMode.dstIn,
            child: ShaderMask(
              shaderCallback: (r) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black, Colors.black, Colors.transparent],
                stops: [0, 0.72, 1],
              ).createShader(r),
              blendMode: BlendMode.dstIn,
              child: Image.asset(image, fit: BoxFit.cover, alignment: imageAlignment, excludeFromSemantics: true),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, top + 10, 16, 28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              if (showBack) ...[
                CircleIconButton(icon: Ic.left, tooltip: 'Back', onTap: () => context.canPop() ? context.pop() : context.go('/home')),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title.toUpperCase(), style: AppType.overline(color: AppColors.gold)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppType.ui(size: 13, weight: FontWeight.w500, color: AppColors.textSecondary)),
                ]),
              ),
              ?action,
            ]),
            const SizedBox(height: 40),
            SizedBox(
              width: width * 0.58,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                GradientHeading(headingLead, headingAccent, size: 34),
                const SizedBox(height: 12),
                Text(description, style: AppType.ui(size: 14, weight: FontWeight.w400, color: AppColors.textSecondary, height: 1.5)),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action, this.onAction, this.overline});
  final String title;
  final String? action, overline;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 8, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (overline != null) ...[Text(overline!.toUpperCase(), style: AppType.overline()), const SizedBox(height: 4)],
              Text(title, style: AppType.display(size: 22, weight: FontWeight.w500)),
            ]),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(action!, style: AppType.ui(size: 13.5, weight: FontWeight.w600, color: AppColors.glow)),
                const SizedBox(width: 4),
                const AppIcon(Ic.right, size: 16, color: AppColors.glow),
              ]),
            ),
        ]),
      );
}

/// Feature tile with art, title, subtitle and a round arrow (Home grid, spreads).
class FeatureTile extends StatelessWidget {
  const FeatureTile({super.key, required this.image, required this.title, required this.subtitle, required this.onTap, this.selected = false, this.badge, this.body});
  final String image, title, subtitle;
  final String? body;
  final VoidCallback onTap;
  final bool selected;
  final Widget? badge;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: title,
        child: GlowCard(
          selected: selected,
          padding: EdgeInsets.zero,
          onTap: onTap,
          child: Stack(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(
                child: ShaderMask(
                  shaderCallback: (r) => const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black, Colors.black, Colors.transparent], stops: [0, 0.65, 1]).createShader(r),
                  blendMode: BlendMode.dstIn,
                  child: Image.asset(image, fit: BoxFit.cover, excludeFromSemantics: true),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 42, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.ui(size: 14.5, weight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.ui(size: 12, weight: FontWeight.w500, color: AppColors.textSecondary)),
                  if (body != null) ...[
                    const SizedBox(height: 4),
                    Text(body!, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.ui(size: 11.5, weight: FontWeight.w400, color: AppColors.textMuted)),
                  ],
                ]),
              ),
            ]),
            Positioned(right: 10, bottom: 12, child: selected ? const _CheckDot() : const ArrowDot()),
            if (badge != null) Positioned(right: 8, top: 8, child: badge!),
          ]),
        ),
      );
}

class _CheckDot extends StatelessWidget {
  const _CheckDot();
  @override
  Widget build(BuildContext context) => Container(
        width: 28,
        height: 28,
        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.cta),
        child: const Center(child: AppIcon(Ic.check, color: AppColors.onGold, size: 16)),
      );
}

class ArrowDot extends StatelessWidget {
  const ArrowDot({super.key, this.size = 28});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0x14FFFFFF), border: Border.all(color: AppColors.border)),
        child: Center(child: AppIcon(Ic.right, color: AppColors.text, size: size * 0.55)),
      );
}

class Tag extends StatelessWidget {
  const Tag(this.label, {super.key, this.color, this.icon});
  final String label;
  final Color? color;
  final String? icon;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: (color ?? Colors.white).withValues(alpha: color == null ? 0.06 : 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color == null ? AppColors.border : color!.withValues(alpha: 0.45)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[AppIcon(icon!, size: 12, color: color ?? AppColors.textSecondary), const SizedBox(width: 4)],
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: AppType.ui(size: 11.5, weight: FontWeight.w600, color: color ?? AppColors.textSecondary))),
        ]),
      );
}

class PremiumBadge extends StatelessWidget {
  const PremiumBadge({super.key, this.label = 'Premium'});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(gradient: AppColors.cta, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const AppIcon(Ic.crownFill, color: AppColors.onGold, size: 12),
          const SizedBox(width: 4),
          Text(label, style: AppType.ui(size: 10.5, weight: FontWeight.w800, color: AppColors.onGold, spacing: 0.2)),
        ]),
      );
}

/// Insight card with an icon tile, title and body (Love & Relationships etc.).
class InsightCard extends StatelessWidget {
  const InsightCard({super.key, required this.icon, required this.title, this.body, this.onTap, this.color, this.bodyMaxLines});
  final String icon, title;
  final String? body;
  final VoidCallback? onTap;
  final Color? color;
  final int? bodyMaxLines;
  @override
  Widget build(BuildContext context) => GlowCard(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          IconBadge(icon, color: color ?? AppColors.glow, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(title, style: AppType.ui(size: 15, weight: FontWeight.w700)),
              ),
              if (body != null && body!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  body!,
                  maxLines: bodyMaxLines,
                  overflow: bodyMaxLines == null ? null : TextOverflow.ellipsis,
                  style: AppType.ui(size: 14, weight: FontWeight.w400, color: AppColors.textSecondary, height: 1.5),
                ),
              ],
            ]),
          ),
          if (onTap != null) ...[const SizedBox(width: 8), const Padding(padding: EdgeInsets.only(top: 6), child: ArrowDot(size: 26))],
        ]),
      );
}

/// Tarot card image, optionally reversed and with a flip animation from the card back.
class TarotCardView extends StatelessWidget {
  const TarotCardView({super.key, required this.image, this.reversed = false, this.faceUp = true, this.width = 90, this.selected = false, this.label});
  final String image;
  final bool reversed, faceUp, selected;
  final double width;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final h = width * 1.72;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      label: label,
      image: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: faceUp ? 1 : 0),
        duration: reduce ? Duration.zero : const Duration(milliseconds: 550),
        curve: Curves.easeInOut,
        builder: (context, v, _) {
          // 2D "squash" flip (scaleX = |cos|) instead of a 3D perspective rotateY: perspective
          // transforms passing edge-on (90°) with clip + shadow render unreliably on some
          // Android GPUs (blank/white frames).
          final showFront = v >= 0.5;
          final sx = math.max(0.02, (math.cos((1 - v) * math.pi)).abs());
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(sx, 1, 1),
            child: Container(
              width: width,
              height: h,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(width * 0.08),
                border: Border.all(color: selected ? AppColors.gold : AppColors.gold.withValues(alpha: 0.45), width: selected ? 2 : 1),
                boxShadow: [BoxShadow(color: (selected ? AppColors.gold : Colors.black).withValues(alpha: selected ? 0.35 : 0.45), blurRadius: selected ? 18 : 12, offset: const Offset(0, 6))],
              ),
              clipBehavior: Clip.antiAlias,
              child: showFront
                  ? RotatedBox(quarterTurns: reversed ? 2 : 0, child: Image.asset(image, fit: BoxFit.cover))
                  : Image.asset('assets/images/card_back.webp', fit: BoxFit.cover),
            ),
          );
        },
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) {
    final label = status.replaceAll('_', ' ');
    final color = switch (status) {
      'strong' || 'deep' => AppColors.success,
      'clear' => AppColors.head,
      'balanced' || 'curved' => AppColors.heart,
      'visible' => AppColors.fate,
      _ => AppColors.warning,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999), border: Border.all(color: color.withValues(alpha: 0.5))),
      child: Text(label.isEmpty ? '' : '${label[0].toUpperCase()}${label.substring(1)}', style: AppType.ui(size: 11, weight: FontWeight.w700, color: color)),
    );
  }
}

/// Segmented control: the selected segment is a light pill with ink text.
class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({super.key, required this.labels, required this.index, required this.onChanged, this.icons});
  final List<String> labels;
  final List<String?>? icons;
  final int index;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: const Color(0x0DFFFFFF), borderRadius: BorderRadius.circular(999), border: Border.all(color: AppColors.border)),
        child: Row(children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                selected: i == index,
                button: true,
                child: GestureDetector(
                  onTap: () => onChanged(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: i == index ? const Color(0xFFEDE8FF) : Colors.transparent, borderRadius: BorderRadius.circular(999)),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      if (icons != null && icons![i] != null) ...[
                        AppIcon(icons![i]!, size: 14, color: i == index ? AppColors.onGold : AppColors.textMuted),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: Text(labels[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.ui(size: 12.5, weight: i == index ? FontWeight.w700 : FontWeight.w500, color: i == index ? AppColors.onGold : AppColors.textSecondary)),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      );
}

/// Empty / error state with the cat mascot.
class MascotMessage extends StatelessWidget {
  const MascotMessage({super.key, required this.title, required this.message, this.action, this.onAction, this.image = 'assets/images/neon_cat.webp'});
  final String title, message, image;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Image.asset(image, height: 132, excludeFromSemantics: true),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center, style: AppType.display(size: 22, weight: FontWeight.w500)),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
          if (action != null) ...[
            const SizedBox(height: 18),
            SizedBox(width: 240, child: GradientButton(label: action!, onPressed: onAction, trailing: false, icon: null, height: 48)),
          ],
        ]),
      );
}

/// User-facing text for any error: our own server messages pass through, everything else
/// (stack traces, plugin/Firebase internals) becomes a calm generic line.
String friendlyError(Object? e, [String fallback = 'Something went wrong. Please try again.']) => e is ApiException ? e.message : fallback;

/// Shows an error; if the backend says a Premium upgrade is needed, opens the paywall.
void showApiError(BuildContext context, Object e) {
  final msg = friendlyError(e);
  final needsPremium = e is ApiException && e.needsPremium;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    action: needsPremium ? SnackBarAction(label: 'Go Premium', textColor: AppColors.gold, onPressed: () => context.push('/paywall')) : null,
  ));
}

class Loading extends StatelessWidget {
  const Loading({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.gold, semanticsLabel: 'Loading')));
}

const disclaimer = 'For entertainment and self-reflection only. Not medical, legal or financial advice.';

class DisclaimerText extends StatelessWidget {
  const DisclaimerText({super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
        child: Text(disclaimer, textAlign: TextAlign.center, style: AppType.ui(size: 11.5, weight: FontWeight.w500, color: AppColors.textMuted, height: 1.4)),
      );
}
