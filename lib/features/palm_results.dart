import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../data/api.dart';
import '../data/models.dart';
import 'palm.dart';
import 'palm_overlay.dart';

/// Loads a reading + local photo and renders [builder], handling loading/missing states.
class _PalmLoader extends ConsumerWidget {
  const _PalmLoader({required this.readingId, required this.builder});
  final String readingId;
  final Widget Function(BuildContext, PalmReading, Uint8List?, Map<String, dynamic>) builder;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doc = ref.watch(palmReadingDocProvider(readingId));
    final photo = ref.watch(palmPhotoProvider(readingId)).value;
    return doc.when(
      loading: () => const SubPage(child: Loading()),
      error: (e, _) => const SubPage(
        child: Center(
          child: MascotMessage(title: 'Could not load reading', message: 'Check your connection and try again.'),
        ),
      ),
      data: (d) {
        final r = palmFromDoc(d);
        if (r == null) {
          return const SubPage(
            child: Center(
              child: MascotMessage(title: 'Reading not found', message: 'It may have been deleted.'),
            ),
          );
        }
        return builder(context, r, photo, d!);
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, this.action, this.icon});
  final String title;
  final String? icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
    child: Row(
      children: [
        CircleIconButton(icon: Ic.left, tooltip: 'Back', onTap: () => context.canPop() ? context.pop() : context.go('/palm')),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[AppIcon(icon!, size: 18, color: AppColors.gold), const SizedBox(width: 8)],
              Flexible(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.ui(size: 17, weight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        action ?? const SizedBox(width: 46),
      ],
    ),
  );
}

// ---------------- Results (flow screens 3-5) ----------------

class PalmResultScreen extends ConsumerStatefulWidget {
  const PalmResultScreen({super.key, required this.readingId, this.initialTab = 0});
  final String readingId;
  final int initialTab;
  @override
  ConsumerState<PalmResultScreen> createState() => _PalmResultState();
}

/// Whose palm a reading is ("Riya's" for someone else's palm, else "Your").
String _owner(Map<String, dynamic> doc) {
  final s = doc['subject'];
  final name = s is Map ? '${s['name'] ?? ''}'.trim() : '';
  return name.isEmpty ? 'Your' : "$name's";
}

class _PalmResultState extends ConsumerState<PalmResultScreen> {
  late int _tab = widget.initialTab;
  @override
  Widget build(BuildContext context) {
    final premium = ref.watch(isPremiumProvider);
    return _PalmLoader(
      readingId: widget.readingId,
      builder: (context, r, photo, doc) => SubPage(
        child: SafeArea(
          child: Column(
            children: [
              _TopBar(
                title: '${_owner(doc)} Palm Reading',
                action: CircleIconButton(icon: Ic.share, tooltip: 'Save & Share', onTap: () => context.push('/palm/share/${widget.readingId}')),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedTabs(
                  labels: const ['Overview', 'Line Analysis', 'Personality'],
                  icons: premium ? null : const [null, null, Ic.lockFill],
                  index: _tab,
                  onChanged: (i) => setState(() => _tab = i),
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: switch (_tab) {
                    0 => _Overview(key: const ValueKey(0), r: r, photo: photo, readingId: widget.readingId, premium: premium, onDetails: () => setState(() => _tab = 1)),
                    1 => _Lines(key: const ValueKey(1), r: r, photo: photo, premium: premium),
                    _ =>
                      premium
                          ? _Personality(key: const ValueKey(2), r: r)
                          : _LockedPreview(
                              key: const ValueKey(3),
                              child: _Personality(r: r),
                            ),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Free-tier teaser: the real content, blurred, with an unlock call to action on top.
class _LockedPreview extends StatelessWidget {
  const _LockedPreview({super.key, required this.child, this.title = 'Unlock your full reading', this.height});
  final Widget child;
  final String title;
  final double? height;
  @override
  Widget build(BuildContext context) {
    final body = Stack(
      children: [
        Positioned.fill(
          child: ExcludeSemantics(
            child: IgnorePointer(
              child: ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7), child: child),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [const Color(0x330A0916), const Color(0xE60A0916).withValues(alpha: 0.9)]),
            ),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.cta),
                  child: const Center(child: AppIcon(Ic.lockFill, color: AppColors.onGold, size: 26)),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AppType.display(size: 22, weight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                Text('Every line, mount, personality trait and prediction with Premium.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 16),
                SizedBox(
                  width: 240,
                  child: GradientButton(label: 'Unlock with Premium', icon: Ic.crownFill, trailing: false, height: 50, onPressed: () => context.push('/paywall')),
                ),
              ],
            ),
          ),
        ),
      ],
    );
    return height == null ? body : SizedBox(height: height, child: body);
  }
}

class _Overview extends StatelessWidget {
  const _Overview({super.key, required this.r, required this.photo, required this.readingId, required this.premium, required this.onDetails});
  final PalmReading r;
  final Uint8List? photo;
  final String readingId;
  final bool premium;
  final VoidCallback onDetails;
  @override
  Widget build(BuildContext context) {
    final o = r.overview;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        const Center(child: GradientHeading('Your Reading is', 'Ready!', size: 28)),
        const SizedBox(height: 6),
        Text(r.headline, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 16),
        PalmLineViewer(photo: photo, reading: r),
        const SizedBox(height: 16),
        // Content-sized rows (a fixed-aspect grid overflowed with longer AI text / larger fonts).
        for (final (icon, title, key, section) in const [
          (Ic.heart, 'Love & Relationships', 'love', 'love'),
          (Ic.briefcase, 'Career & Success', 'career', 'career'),
          (Ic.compass, 'Life Path & Future', 'life_path', 'life'),
          (Ic.lotus, 'Personality Insights', 'personality', 'personality'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InsightCard(
              icon: premium ? icon : Ic.lockFill,
              title: premium ? title : '$title · Premium',
              body: PalmReading.strOf(o, key),
              bodyMaxLines: premium ? 3 : 1,
              onTap: () => context.push(premium ? '/palm/result/$readingId/$section' : '/paywall'),
            ),
          ),
        const SizedBox(height: 6),
        if (premium)
          GradientButton(label: 'View Detailed Analysis', icon: null, onPressed: onDetails)
        else ...[
          GradientButton(label: 'Unlock Full Reading', icon: Ic.crownFill, trailing: false, onPressed: () => context.push('/paywall')),
          const SizedBox(height: 10),
          OutlinePillButton(label: 'See your Heart Line free', icon: Ic.heart, onPressed: onDetails),
        ],
        const DisclaimerText(),
      ],
    );
  }
}

class _Lines extends StatelessWidget {
  const _Lines({super.key, required this.r, required this.photo, required this.premium});
  final PalmReading r;
  final Uint8List? photo;
  final bool premium;
  @override
  Widget build(BuildContext context) {
    // Free tier: the heart line is a full free sample; everything else is a blurred teaser.
    final lines = r.lines;
    final free = premium ? lines : lines.where((l) => l.name == 'heart').toList();
    final locked = premium ? const <PalmLine>[] : lines.where((l) => l.name != 'heart').toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        for (final l in free) _lineCard(context, l),
        if (locked.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: _LockedPreview(
              title: 'Unlock ${locked.length} more lines & your mounts',
              height: 150.0 * locked.length + 60,
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Column(children: [for (final l in locked) _lineCard(context, l, interactive: false)]),
              ),
            ),
          ),
        if (premium && r.mounts.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Mounts', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          for (final m in r.mounts)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InsightCard(icon: Ic.mountain, title: 'Mount of ${_cap(PalmReading.strOf(m, 'name'))} · ${_cap(PalmReading.strOf(m, 'prominence'))}', body: PalmReading.strOf(m, 'meaning')),
            ),
        ],
      ],
    );
  }

  Widget _lineCard(BuildContext context, PalmLine l, {bool interactive = true}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: GlowCard(
      padding: const EdgeInsets.all(10),
      onTap: !interactive
          ? null
          : () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (l.drawable)
                        SizedBox(
                          height: 240,
                          child: PalmOverlay(photo: photo, lines: [l], palmBox: r.palmBox, strokeScale: 1.2),
                        ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Text(
                            l.title,
                            style: TextStyle(color: AppColors.lineColor(l.name), fontSize: 20, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(width: 8),
                          StatusBadge(l.status),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'What we see',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      Text(l.observation, style: const TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 12),
                      const Text(
                        'What it means',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      Text(l.meaning, style: const TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            height: 116,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: PalmOverlay(photo: photo, lines: [l], palmBox: r.palmBox, animate: interactive),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.title,
                        style: TextStyle(color: AppColors.lineColor(l.name), fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                    ),
                    StatusBadge(l.status),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  l.meaning,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                ),
              ],
            ),
          ),
          if (interactive) const AppIcon(Ic.right, color: Colors.white),
        ],
      ),
    ),
  );
}

String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

const _elementIcon = {'water': Ic.moon, 'fire': Ic.flash, 'earth': Ic.leaf, 'air': Ic.sparkles2};
const _traitIcons = [Ic.sparkles, Ic.heart, Ic.bulb, Ic.compass, Ic.star, Ic.lotus];

class _Personality extends StatelessWidget {
  const _Personality({super.key, required this.r});
  final PalmReading r;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
    children: [
      GlowCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Your Hand Type',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                ),
                AppIcon(Ic.hand, color: AppColors.head.withValues(alpha: 0.8), size: 48),
              ],
            ),
            Row(
              children: [
                IconBadge(_elementIcon[r.element] ?? Ic.hand, color: AppColors.gold, size: 34),
                const SizedBox(width: 8),
                Text(
                  r.handTypeName,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final t in r.handTags) Tag(t)]),
            const SizedBox(height: 10),
            Text(r.handDescription, style: const TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Text('Key Personality Traits', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      for (final t in r.traits)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InsightCard(icon: _traitIcons[r.traits.indexOf(t) % _traitIcons.length], title: PalmReading.strOf(t, 'text')),
        ),
    ],
  );
}

// ---------------- Section detail (flow screens 6-8) ----------------

class PalmSectionScreen extends ConsumerWidget {
  const PalmSectionScreen({super.key, required this.readingId, required this.section});
  final String readingId, section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final premium = ref.watch(isPremiumProvider);
    return _PalmLoader(
      readingId: readingId,
      builder: (context, r, photo, _) {
        if (!premium) {
          // Deep links / back stack can land here; section details are Premium.
          return SubPage(
            child: SafeArea(
              child: Column(
                children: [
                  const _TopBar(title: 'Premium Insight'),
                  Expanded(
                    child: _LockedPreview(child: _Personality(r: r)),
                  ),
                ],
              ),
            ),
          );
        }
        if (section == 'personality') {
          return SubPage(
            child: SafeArea(
              child: Column(
                children: [
                  const _TopBar(title: 'Personality Analysis'),
                  Expanded(child: _Personality(r: r)),
                ],
              ),
            ),
          );
        }
        final (emoji, title, image, data) = switch (section) {
          'love' => (Ic.heart, 'Love & Relationships', 'assets/images/spread_relationship.webp', r.love),
          'career' => (Ic.briefcase, 'Career & Success', 'assets/images/spread_career.webp', r.career),
          _ => (Ic.compass, 'Life Path & Future', 'assets/images/cloud_moon.webp', r.lifePath),
        };
        return SubPage(
          child: SafeArea(
            child: Column(
              children: [
                _TopBar(title: title, icon: emoji),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.asset(image, height: 190, fit: BoxFit.cover, excludeFromSemantics: true),
                      ),
                      const SizedBox(height: 14),
                      Text(PalmReading.strOf(data, 'summary'), style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.5)),
                      const SizedBox(height: 16),
                      ..._sectionBody(context, section, data),
                      if (section == 'life' && r.quote.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        GlowCard(
                          child: Row(
                            children: [
                              const AppIcon(Ic.quote, size: 26, color: AppColors.gold),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  r.quote,
                                  style: const TextStyle(color: Colors.white, fontStyle: FontStyle.italic),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const DisclaimerText(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _sectionBody(BuildContext context, String s, Map<String, dynamic> d) {
    Widget card(String icon, String title, Color color, List<Widget> rows) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlowCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconBadge(icon, color: color, size: 30),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: AppType.ui(size: 15, weight: FontWeight.w700, color: color),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...rows,
          ],
        ),
      ),
    );
    Widget bullet(String t, String i, Color c) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(i, size: 18, color: c),
          const SizedBox(width: 8),
          Expanded(
            child: Text(t, style: const TextStyle(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
    switch (s) {
      case 'love':
        return [
          card(Ic.heart, 'Your strengths', AppColors.heart, [for (final t in PalmReading.listOf(d, 'strengths')) bullet(t, Ic.check, AppColors.success)]),
          card(Ic.info, 'Be mindful of', AppColors.head, [for (final t in PalmReading.listOf(d, 'mindful_of')) bullet(t, Ic.sparkles2, AppColors.head)]),
          card(Ic.star, 'Future outlook', AppColors.gold, [Text(PalmReading.strOf(d, 'outlook'), style: const TextStyle(color: AppColors.textSecondary))]),
        ];
      case 'career':
        return [
          Text('Best Career Areas', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final a in PalmReading.mapsOf(d, 'best_areas')) PillChip(label: PalmReading.strOf(a, 'label'), icon: Ic.briefcase)],
          ),
          const SizedBox(height: 16),
          card(Ic.star, 'Future outlook', AppColors.gold, [Text(PalmReading.strOf(d, 'outlook'), style: const TextStyle(color: AppColors.textSecondary))]),
        ];
      default:
        return [
          Text('Key Predictions', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final p in PalmReading.mapsOf(d, 'predictions'))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InsightCard(icon: Ic.compass, title: PalmReading.strOf(p, 'text')),
            ),
        ];
    }
  }
}

// ---------------- Save & Share (flow screen 9) ----------------

class PalmShareScreen extends StatefulWidget {
  const PalmShareScreen({super.key, required this.readingId});
  final String readingId;
  @override
  State<PalmShareScreen> createState() => _PalmShareState();
}

class _PalmShareState extends State<PalmShareScreen> {
  final _key = GlobalKey();
  bool _busy = false;

  Future<Uint8List> _render() async {
    final boundary = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  }

  String get _fileName => 'selene_palm_${widget.readingId}.png';

  Future<String> _tempPath(Uint8List bytes) async {
    final path = '${(await getTemporaryDirectory()).path}/$_fileName';
    await XFile.fromData(bytes, mimeType: 'image/png').saveTo(path);
    return path;
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final bytes = await _render();
      if (kIsWeb) {
        // Browsers download the file (cross_file's web saveTo triggers a download).
        await XFile.fromData(bytes, mimeType: 'image/png', name: _fileName).saveTo(_fileName);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Image downloaded.')));
      } else {
        if (!await Gal.hasAccess()) await Gal.requestAccess();
        await Gal.putImage(await _tempPath(bytes), album: 'Selene');
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved to your gallery.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save the image. Please allow photo access and try again.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final bytes = await _render();
      final file = kIsWeb ? XFile.fromData(bytes, mimeType: 'image/png', name: _fileName) : XFile(await _tempPath(bytes), mimeType: 'image/png');
      await SharePlus.instance.share(ShareParams(files: [file], fileNameOverrides: [_fileName], text: 'My AI palm reading from Selene'));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not share the image. Please try again.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _PalmLoader(
    readingId: widget.readingId,
    builder: (context, r, photo, doc) {
      final lines = r.lines;
      return SubPage(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(child: Text('Save & Share', style: Theme.of(context).textTheme.headlineSmall)),
                    IconButton(
                      onPressed: () => context.pop(),
                      icon: const AppIcon(Ic.close, color: Colors.white),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: RepaintBoundary(
                    key: _key,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF221B4A), Color(0xFF0E0C21)]),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppColors.gold.withValues(alpha: 0.6), width: 1.2),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const AppIcon(Ic.handFill, color: AppColors.gold, size: 18),
                              const SizedBox(width: 6),
                              const Text(
                                'AI PALM READING',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 1),
                              ),
                              const Spacer(),
                              Text(DateFormat.yMMMd().format(DateTime.now()), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 130,
                                height: 160,
                                child: PalmOverlay(photo: photo, lines: lines, palmBox: r.palmBox, animate: false),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Hand Type', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                                    Text(
                                      r.handTypeName,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 8),
                                    for (final l in lines)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 2),
                                        child: Row(
                                          children: [
                                            AppIcon(Ic.heartFill, size: 10, color: AppColors.lineColor(l.name)),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(l.title, style: TextStyle(color: AppColors.lineColor(l.name), fontSize: 12)),
                                            ),
                                            Text(_cap(l.status.replaceAll('_', ' ')), style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(child: _ShareChip(Ic.heart, 'Love', PalmReading.strOf(r.love, 'chip'))),
                              const SizedBox(width: 6),
                              Expanded(child: _ShareChip(Ic.briefcase, 'Career', PalmReading.strOf(r.career, 'chip'))),
                              const SizedBox(width: 6),
                              Expanded(child: _ShareChip(Ic.compass, 'Future', PalmReading.strOf(r.lifePath, 'chip'))),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            '“${r.quote}”',
                            textAlign: TextAlign.center,
                            style: AppType.display(size: 16, weight: FontWeight.w400, style: FontStyle.italic, height: 1.35),
                          ),
                          const SizedBox(height: 12),
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AppIcon(Ic.moonStarsFill, color: AppColors.gold, size: 18),
                              SizedBox(width: 6),
                              Text(
                                'Selene',
                                style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: 16),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: GradientButton(label: 'Save to Gallery', icon: Ic.download, trailing: false, loading: _busy, onPressed: _save),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinePillButton(label: 'Share Reading', icon: Ic.share, onPressed: _busy ? null : _share),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ShareChip extends StatelessWidget {
  const _ShareChip(this.e, this.t, this.v);
  final String e, t, v;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: const Color(0x0DFFFFFF),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      children: [
        AppIcon(e, size: 15, color: AppColors.gold),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t,
                style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
              ),
              Text(
                v,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
