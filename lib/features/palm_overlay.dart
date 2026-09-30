import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../data/models.dart';

/// Palm photo with the four major lines traced as smooth, glowing curves.
///
/// - Lines are Catmull-Rom splines through the model's points (lightly de-jittered), so they
///   follow the crease instead of zig-zagging.
/// - When the reading has a palm box, the view zooms onto the palm so lines are large and clear.
/// - No text is painted on the photo (labels overlapped and hid the lines); use [PalmLegend].
/// - [highlight] dims every other line so one can be inspected.
class PalmOverlay extends StatefulWidget {
  const PalmOverlay({super.key, required this.photo, required this.lines, this.palmBox, this.highlight, this.animate = true, this.strokeScale = 1});
  final Uint8List? photo;
  final List<PalmLine> lines;
  final (double, double, double, double)? palmBox;
  final String? highlight;
  final bool animate;
  final double strokeScale;

  @override
  State<PalmOverlay> createState() => _PalmOverlayState();

  // Small LRU: decoded 1000px photos are ~4 MB each, so keep only the most recent few.
  static final _cache = <Uint8List, Future<ui.Image>>{};
  static const _cacheMax = 6;
  static Future<ui.Image> decode(Uint8List bytes) {
    final hit = _cache.remove(bytes);
    if (hit != null) return _cache[bytes] = hit; // re-insert as most recent
    if (_cache.length >= _cacheMax) _cache.remove(_cache.keys.first);
    return _cache[bytes] = () async {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 1000);
      return (await codec.getNextFrame()).image;
    }();
  }
}

class _PalmOverlayState extends State<PalmOverlay> with SingleTickerProviderStateMixin {
  late final _draw = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  Future<ui.Image>? _img;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PalmOverlay old) {
    super.didUpdateWidget(old);
    if (!identical(old.photo, widget.photo)) _load();
  }

  void _load() {
    _img = widget.photo == null ? null : PalmOverlay.decode(widget.photo!);
    _img?.then((_) {
      if (!mounted) return;
      final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (widget.animate && !reduce) {
        _draw.forward(from: 0);
      } else {
        _draw.value = 1;
      }
    });
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final drawable = widget.lines.where((l) => l.drawable).toList();
    final semantics = drawable.isEmpty ? 'Palm photo' : 'Palm photo with ${drawable.map((l) => l.title).join(', ')} traced';
    if (_img == null) {
      // Server copy is deleted after reading and no local copy exists (e.g. new device): show the stylised hand.
      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.asset('assets/images/palm_celestial.webp', fit: BoxFit.cover, semanticLabel: 'Palm illustration'),
      );
    }
    return Semantics(
      image: true,
      label: semantics,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: FutureBuilder<ui.Image>(
          future: _img,
          builder: (context, snap) {
            if (!snap.hasData) return const ColoredBox(color: AppColors.field, child: Loading());
            return AnimatedBuilder(
              animation: _draw,
              builder: (_, _) => CustomPaint(
                size: Size.infinite,
                painter: PalmOverlayPainter(
                  img: snap.data!,
                  lines: drawable,
                  palmBox: widget.palmBox,
                  highlight: widget.highlight,
                  progress: Curves.easeInOutCubic.transform(_draw.value),
                  strokeScale: widget.strokeScale,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class PalmOverlayPainter extends CustomPainter {
  PalmOverlayPainter({required this.img, required this.lines, this.palmBox, this.highlight, this.progress = 1, this.strokeScale = 1});
  final ui.Image img;
  final List<PalmLine> lines;
  final (double, double, double, double)? palmBox;
  final String? highlight;
  final double progress, strokeScale;

  /// Image → canvas transform: zoom so the (padded) palm box is fully visible and centred,
  /// while the photo always covers the whole canvas (no empty bands).
  static (double scale, Offset offset) fit(Size size, double iw, double ih, (double, double, double, double)? box) {
    final cover = math.max(size.width / iw, size.height / ih);
    if (box == null) return (cover, Offset((size.width - iw * cover) / 2, (size.height - ih * cover) / 2));
    // Extra room above for the heart line / finger bases, a little on the other sides.
    final w = box.$3 - box.$1, h = box.$4 - box.$2;
    final l = (box.$1 - w * 0.10).clamp(0.0, 1.0), r = (box.$3 + w * 0.10).clamp(0.0, 1.0);
    final t = (box.$2 - h * 0.18).clamp(0.0, 1.0), b = (box.$4 + h * 0.06).clamp(0.0, 1.0);
    final rw = (r - l) * iw, rh = (b - t) * ih;
    final s = math.max(cover, math.min(size.width / rw, size.height / rh));
    final cx = (l + r) / 2 * iw, cy = (t + b) / 2 * ih;
    final dx = (size.width / 2 - cx * s).clamp(size.width - iw * s, 0.0);
    final dy = (size.height / 2 - cy * s).clamp(size.height - ih * s, 0.0);
    return (s, Offset(dx, dy));
  }

  /// Removes model jitter with one light smoothing pass (endpoints stay put).
  static List<Offset> smooth(List<Offset> p) {
    if (p.length < 3) return p;
    return [p.first, for (var i = 1; i < p.length - 1; i++) p[i - 1] * 0.25 + p[i] * 0.5 + p[i + 1] * 0.25, p.last];
  }

  /// Centripetal-ish Catmull-Rom spline through all points as cubic Béziers.
  static Path spline(List<Offset> p) {
    final path = Path()..moveTo(p.first.dx, p.first.dy);
    if (p.length == 2) return path..lineTo(p.last.dx, p.last.dy);
    for (var i = 0; i < p.length - 1; i++) {
      final p0 = i == 0 ? p[0] : p[i - 1];
      final p1 = p[i], p2 = p[i + 1];
      final p3 = i + 2 < p.length ? p[i + 2] : p2;
      final c1 = p1 + (p2 - p0) / 6, c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final iw = img.width.toDouble(), ih = img.height.toDouble();
    final (s, o) = fit(size, iw, ih, palmBox);
    canvas.drawImageRect(img, Rect.fromLTWH(0, 0, iw, ih), Rect.fromLTWH(o.dx, o.dy, iw * s, ih * s), Paint()..filterQuality = FilterQuality.medium);
    // Darken slightly so the neon lines pop on any skin tone / lighting.
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0x520A0916));

    final base = (size.shortestSide / 110).clamp(1.6, 3.4) * strokeScale;
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      // Stagger: each line starts drawing a bit after the previous one.
      final start = i * 0.12, t = ((progress - start) / (1 - 0.12 * (lines.length - 1).clamp(0, 3))).clamp(0.0, 1.0);
      if (t <= 0) continue;
      final dim = highlight != null && highlight != l.name;
      final color = AppColors.lineColor(l.name).withValues(alpha: dim ? 0.28 : 1);
      final pts = smooth([for (final p in l.points) Offset(o.dx + p.$1 * iw * s, o.dy + p.$2 * ih * s)]);
      final full = spline(pts);
      final metric = full.computeMetrics().firstOrNull;
      if (metric == null) continue;
      final path = metric.extractPath(0, metric.length * t);
      final w = highlight == l.name ? base * 1.35 : base;

      if (!dim) {
        canvas.drawPath(
          path,
          Paint()
            ..color = color.withValues(alpha: 0.55)
            ..style = PaintingStyle.stroke
            ..strokeWidth = w * 3.2
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 2.2),
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      if (!dim) {
        // Thin bright core for a crisp neon look.
        canvas.drawPath(
          path,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.65)
            ..style = PaintingStyle.stroke
            ..strokeWidth = w * 0.35
            ..strokeCap = StrokeCap.round,
        );
      }
      // Start marker + moving tip while drawing.
      canvas.drawCircle(pts.first, w * 1.3, Paint()..color = color);
      if (t < 1) {
        final tip = metric.getTangentForOffset(metric.length * t)?.position;
        if (tip != null) canvas.drawCircle(tip, w * 1.6, Paint()..color = Colors.white.withValues(alpha: 0.9));
      } else {
        canvas.drawCircle(pts.last, w * 0.9, Paint()..color = color);
      }
    }
  }

  @override
  bool shouldRepaint(PalmOverlayPainter o) => o.img != img || o.lines != lines || o.progress != progress || o.highlight != highlight || o.palmBox != palmBox || o.strokeScale != strokeScale;
}

/// Colour key under the overlay. Tapping a line highlights it on the photo.
class PalmLegend extends StatelessWidget {
  const PalmLegend({super.key, required this.lines, this.selected, this.onSelect});
  final List<PalmLine> lines;
  final String? selected;
  final ValueChanged<String?>? onSelect;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    alignment: WrapAlignment.center,
    children: [
      for (final l in lines)
        Semantics(
          button: onSelect != null,
          selected: selected == l.name,
          label: '${l.title}${l.drawable ? '' : ', not clearly visible'}',
          excludeSemantics: true,
          child: GestureDetector(
            onTap: onSelect == null || !l.drawable ? null : () => onSelect!(selected == l.name ? null : l.name),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: selected == l.name ? AppColors.lineColor(l.name).withValues(alpha: 0.18) : const Color(0x0DFFFFFF),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: selected == l.name ? AppColors.lineColor(l.name) : AppColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 18,
                    height: 4,
                    decoration: BoxDecoration(
                      color: l.drawable ? AppColors.lineColor(l.name) : AppColors.textMuted,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: l.drawable ? [BoxShadow(color: AppColors.lineColor(l.name).withValues(alpha: 0.6), blurRadius: 6)] : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l.drawable ? l.title : '${l.title} · faint',
                    style: AppType.ui(size: 12.5, weight: FontWeight.w600, color: l.drawable ? AppColors.text : AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}

/// Overlay + legend with tap-to-highlight, used on the results overview.
class PalmLineViewer extends StatefulWidget {
  const PalmLineViewer({super.key, required this.photo, required this.reading, this.aspectRatio = 0.85});
  final Uint8List? photo;
  final PalmReading reading;
  final double aspectRatio;
  @override
  State<PalmLineViewer> createState() => _PalmLineViewerState();
}

class _PalmLineViewerState extends State<PalmLineViewer> {
  String? _selected;
  @override
  Widget build(BuildContext context) {
    final lines = widget.reading.lines;
    return Column(
      children: [
        AspectRatio(
          aspectRatio: widget.aspectRatio,
          child: GestureDetector(
            onTap: () => setState(() => _selected = null),
            child: PalmOverlay(photo: widget.photo, lines: lines, palmBox: widget.reading.palmBox, highlight: _selected, strokeScale: 1.1),
          ),
        ),
        if (widget.photo != null) ...[
          const SizedBox(height: 12),
          PalmLegend(lines: lines, selected: _selected, onSelect: (n) => setState(() => _selected = n)),
          const SizedBox(height: 6),
          Text(
            'Tap a line to highlight it',
            style: AppType.ui(size: 11.5, weight: FontWeight.w400, color: AppColors.textMuted),
          ),
        ],
      ],
    );
  }
}
