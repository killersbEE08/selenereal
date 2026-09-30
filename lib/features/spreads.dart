import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../data/api.dart';
import '../data/models.dart';
import 'tarot.dart';

class SpreadsScreen extends ConsumerStatefulWidget {
  const SpreadsScreen({super.key});
  @override
  ConsumerState<SpreadsScreen> createState() => _SpreadsState();
}

class _SpreadsState extends ConsumerState<SpreadsScreen> {
  String _cat = 'popular';
  static const _cats = [('popular', Ic.star, 'Popular'), ('love', Ic.heart, 'Love'), ('career', Ic.briefcase, 'Career'), ('growth', Ic.lotus, 'Growth'), ('custom', Ic.grid, 'Custom')];

  void _open(Spread s) => showSpreadSheet(context, ref, s);

  @override
  Widget build(BuildContext context) {
    final spreads = ref.watch(spreadsProvider).value ?? [];
    final custom = ref.watch(customSpreadsProvider).value ?? [];
    final premium = ref.watch(isPremiumProvider);
    final list = _cat == 'custom' ? custom : spreads.where((s) => s.categories.contains(_cat)).toList();
    final more = spreads.where((s) => !s.categories.contains('popular')).toList();

    return SubPage(
      child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        HeroHeader(
          title: 'Tarot Spreads',
          subtitle: 'Explore, create and get deeper insights',
          image: 'assets/images/hero_readers.webp',
          headingLead: 'Go Deeper with',
          headingAccent: 'Spreads',
          description: 'Ask bigger questions, explore different perspectives and get more detailed guidance.',
          height: 360,
        ),
        ChipRow(children: [
          for (final c in _cats) PillChip(label: c.$3, icon: c.$2, selected: _cat == c.$1, onTap: () => setState(() => _cat = c.$1)),
        ]),
        SectionTitle(_cat == 'custom' ? 'My Spreads' : '${_cats.firstWhere((c) => c.$1 == _cat).$3} Tarot Spreads'),
        if (list.isEmpty)
          MascotMessage(
            title: 'No custom spreads yet',
            message: 'Design a spread with your own positions and questions.',
            action: 'Create Spread',
            onAction: () => premium ? context.push('/spreads/create') : context.push('/paywall'),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.82,
              children: [
                for (final s in list)
                  FeatureTile(
                    image: s.image,
                    title: s.name,
                    subtitle: s.subtitle,
                    body: s.description,
                    badge: s.premium && !premium ? const PremiumBadge() : null,
                    onTap: () => _open(s),
                  ),
              ],
            ),
          ),
        if (_cat != 'custom') ...[
          const SectionTitle('More Spreads'),
          SizedBox(
            height: 170,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
              for (final s in more)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: SizedBox(
                    width: 150,
                    child: FeatureTile(image: s.image, title: s.name, subtitle: s.subtitle, badge: s.premium && !premium ? const PremiumBadge() : null, onTap: () => _open(s)),
                  ),
                ),
            ]),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
          child: GlowCard(
            onTap: () => premium ? context.push('/spreads/create') : context.push('/paywall'),
            child: Row(children: [
              const IconBadge(Ic.pencil, color: AppColors.gold, size: 52, circle: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Create your own spread', style: AppType.ui(size: 16, weight: FontWeight.w700)),
                  Text('Design a custom spread for your unique questions.', style: AppType.ui(size: 12.5, weight: FontWeight.w400, color: AppColors.textSecondary)),
                ]),
              ),
              if (!premium) const PremiumBadge() else const ArrowDot(),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Opens the spread detail sheet (positions, question, draw button). Premium spreads route to
/// the paywall for free users. Shared by the Tarot tab and the Spreads screen.
Future<void> showSpreadSheet(BuildContext context, WidgetRef ref, Spread s, {String question = '', String? topic, bool aiEnabled = true}) async {
  if (s.premium && !ref.read(isPremiumProvider)) {
    await context.push('/paywall');
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => SpreadSheet(spread: s, initialQuestion: question, topic: topic, aiEnabled: aiEnabled),
  );
}

/// Spread details + question entry, then start the draw.
class SpreadSheet extends ConsumerStatefulWidget {
  const SpreadSheet({super.key, required this.spread, this.initialQuestion = '', this.topic, this.aiEnabled = true});
  final Spread spread;
  final String initialQuestion;
  final String? topic;
  final bool aiEnabled;
  @override
  ConsumerState<SpreadSheet> createState() => _SpreadSheetState();
}

class _SpreadSheetState extends ConsumerState<SpreadSheet> {
  late final _q = TextEditingController(text: widget.initialQuestion);

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _draw() {
    final s = widget.spread;
    final router = GoRouter.of(context);
    final topic = widget.topic ??
        (s.categories.contains('love') ? 'love' : s.categories.contains('career') ? 'career' : s.categories.contains('growth') ? 'growth' : 'general');
    final req = TarotRequest(question: _q.text.trim(), topic: topic, spread: s, aiEnabled: widget.aiEnabled, readerId: ref.read(userDocProvider).value?.preferredReaderId);
    Navigator.pop(context);
    router.push('/tarot/draw', extra: req);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.spread;
    final n = s.positions.length;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.asset(s.image, width: 56, height: 56, fit: BoxFit.cover, excludeFromSemantics: true)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$n CARD${n == 1 ? '' : 'S'}', style: AppType.overline(color: AppColors.gold)),
                Text(s.name, style: AppType.display(size: 24, weight: FontWeight.w500)),
              ]),
            ),
          ]),
          const SizedBox(height: 8),
          Text(s.description, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView(shrinkWrap: true, children: [
              for (final p in s.positions)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.gold.withValues(alpha: 0.14), border: Border.all(color: AppColors.gold.withValues(alpha: 0.45))),
                      child: Text('${p.index + 1}', style: AppType.ui(size: 12, weight: FontWeight.w700, color: AppColors.gold)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.label, style: AppType.ui(size: 14, weight: FontWeight.w700)),
                        Text(p.meaning, style: AppType.ui(size: 12.5, weight: FontWeight.w400, color: AppColors.textSecondary)),
                      ]),
                    ),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _q,
            maxLength: 200,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _draw(),
            decoration: const InputDecoration(hintText: 'Your question (optional)', counterText: ''),
          ),
          const SizedBox(height: 12),
          GradientButton(label: 'Draw $n Card${n == 1 ? '' : 's'}', icon: Ic.cards, onPressed: _draw),
        ]),
      ),
    );
  }
}

class CreateSpreadScreen extends StatefulWidget {
  const CreateSpreadScreen({super.key});
  @override
  State<CreateSpreadScreen> createState() => _CreateSpreadState();
}

class _CreateSpreadState extends State<CreateSpreadScreen> {
  final _name = TextEditingController();
  final _positions = <(TextEditingController, TextEditingController)>[(TextEditingController(text: 'Situation'), TextEditingController(text: 'Where I stand now'))];
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    for (final p in _positions) {
      p.$1.dispose();
      p.$2.dispose();
    }
    super.dispose();
  }

  void _removePosition(int i) {
    final p = _positions.removeAt(i);
    p.$1.dispose();
    p.$2.dispose();
    setState(() {});
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final pos = _positions.where((p) => p.$1.text.trim().isNotEmpty).map((p) => {'label': p.$1.text.trim(), 'meaning': p.$2.text.trim()}).toList();
    if (name.isEmpty || pos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add a name and at least one position.')));
      return;
    }
    setState(() => _busy = true);
    try {
      await userRef().collection('customSpreads').add({'name': name, 'positions': pos, 'createdAt': FieldValue.serverTimestamp()});
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save your spread. Check your connection and try again.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SubPage(
        child: SafeArea(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              CircleIconButton(icon: Ic.left, tooltip: 'Back', onTap: () => context.pop()),
              const SizedBox(width: 12),
              const Expanded(child: GradientHeading('Create Your', 'Spread', size: 28, sparkle: false)),
            ]),
            const SizedBox(height: 16),
            TextField(controller: _name, maxLength: 40, decoration: const InputDecoration(hintText: 'Spread name, e.g. Full Moon Check-in')),
            const SizedBox(height: 8),
            for (final (i, p) in _positions.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GlowCard(
                  padding: const EdgeInsets.all(12),
                  child: Column(children: [
                    Row(children: [
                      CircleAvatar(radius: 13, backgroundColor: AppColors.primary, child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 12))),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(controller: p.$1, maxLength: 30, decoration: const InputDecoration(hintText: 'Position label', counterText: ''))),
                      IconButton(
                        tooltip: 'Remove position',
                        onPressed: _positions.length == 1 ? null : () => _removePosition(i),
                        icon: const AppIcon(Ic.delete, color: AppColors.textSecondary),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    TextField(controller: p.$2, maxLength: 80, decoration: const InputDecoration(hintText: 'What this position means', counterText: '')),
                  ]),
                ),
              ),
            if (_positions.length < 10)
              OutlinePillButton(
                label: 'Add Position',
                icon: Ic.add,
                onPressed: () => setState(() => _positions.add((TextEditingController(), TextEditingController()))),
              ),
            const SizedBox(height: 16),
            GradientButton(label: 'Save Spread', loading: _busy, onPressed: _save, icon: Ic.check),
          ]),
        ),
      );
}
