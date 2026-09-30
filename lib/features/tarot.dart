import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../data/api.dart';
import '../data/models.dart';
import 'spreads.dart' show showSpreadSheet;

class TarotRequest {
  TarotRequest({required this.question, required this.topic, required this.spread, required this.aiEnabled, this.readerId});
  final String question, topic;
  final Spread spread;
  final bool aiEnabled;
  final String? readerId;
}

/// Seam so widget tests can stub the backend draw.
final startTarotProvider = Provider<Future<Map<String, dynamic>> Function({
  required String question,
  required String topic,
  String? spreadId,
  String? customSpreadId,
  required bool aiEnabled,
  String? readerId,
})>((ref) => Api.startTarot);

const tarotTopics = [
  ('general', Ic.sparkles, 'General'),
  ('love', Ic.heart, 'Love'),
  ('career', Ic.briefcase, 'Career'),
  ('relationships', Ic.userHeart, 'Relationships'),
  ('growth', Ic.lotus, 'Growth'),
];

/// Starter questions per topic: tapping one fills the question box.
const tarotQuestionIdeas = {
  'general': ['What do I most need to know right now?', 'What energy is guiding me this month?', 'What is holding me back?'],
  'love': ['What does my love life need from me right now?', 'How can I open my heart to the right person?', 'What is the next step in my relationship?'],
  'career': ['What should I focus on in my career this month?', 'Is this the right time to make a change at work?', 'How can I grow my finances?'],
  'relationships': ['How can I heal a difficult relationship?', 'What does this person need from me?', 'How can I set healthier boundaries?'],
  'growth': ['What lesson is the universe teaching me?', 'How can I become more confident?', 'What habit should I let go of?'],
};

class TarotReadingScreen extends ConsumerStatefulWidget {
  const TarotReadingScreen({super.key});
  @override
  ConsumerState<TarotReadingScreen> createState() => _TarotReadingState();
}

class _TarotReadingState extends ConsumerState<TarotReadingScreen> {
  final _q = TextEditingController();
  final _focus = FocusNode();
  String _topic = 'general';
  String _spreadId = 'three_card';
  bool _ai = true;

  static const _featured = ['one_card', 'three_card', 'relationship', 'celtic_cross', 'career', 'decision'];

  @override
  void initState() {
    super.initState();
    _q.addListener(() => setState(() {}));
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _q.dispose();
    _focus.dispose();
    super.dispose();
  }

  Spread? _spread(List<Spread> spreads) => spreads.where((s) => s.id == _spreadId).firstOrNull ?? spreads.firstOrNull;

  void _useIdea(String q) {
    _q.value = TextEditingValue(text: q, selection: TextSelection.collapsed(offset: q.length));
    _focus.unfocus();
  }

  /// Tapping a spread selects it and opens its detail sheet (positions + draw button), the same
  /// flow as "See all", carrying the question typed on this screen.
  void _openSpread(Spread s) {
    setState(() => _spreadId = s.id);
    _focus.unfocus();
    showSpreadSheet(context, ref, s, question: _q.text.trim(), topic: _topic, aiEnabled: _ai);
  }

  void _start(List<Spread> spreads) {
    final spread = _spread(spreads);
    if (spread == null) return;
    _focus.unfocus();
    if (spread.premium && !ref.read(isPremiumProvider)) {
      context.push('/paywall');
      return;
    }
    context.push('/tarot/draw', extra: TarotRequest(question: _q.text.trim(), topic: _topic, spread: spread, aiEnabled: _ai, readerId: ref.read(userDocProvider).value?.preferredReaderId));
  }

  @override
  Widget build(BuildContext context) {
    final spreads = ref.watch(spreadsProvider).value ?? [];
    final premium = ref.watch(isPremiumProvider);
    final featured = [for (final id in _featured) ...spreads.where((s) => s.id == id)];
    final spread = _spread(spreads);
    final n = spread?.positions.length ?? 0;
    final hasQuestion = _q.text.trim().isNotEmpty;
    final ideas = tarotQuestionIdeas[_topic] ?? tarotQuestionIdeas['general']!;

    return ListView(padding: const EdgeInsets.only(bottom: 120), keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, children: [
      HeroHeader(
        title: 'Tarot',
        subtitle: 'Ask. Draw. Reflect.',
        image: 'assets/images/hero_tarot.webp',
        headingLead: 'Reveal what’s',
        headingAccent: 'next',
        description: 'Ask a question, choose a spread and receive a reading written for you.',
        showBack: false,
        action: OutlinePillButton(label: 'History', icon: Ic.history, onPressed: () => context.push('/readings?type=tarot')),
        height: 340,
      ),
      // Step 1 — the question
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GlowCard(
          selected: _focus.hasFocus,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const IconBadge(Ic.thought, color: AppColors.gold, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('STEP 1', style: AppType.overline()),
                  Text('What would you like to know?', style: AppType.ui(size: 16, weight: FontWeight.w700)),
                ]),
              ),
              Text('${_q.text.length}/200', style: AppType.ui(size: 11.5, color: AppColors.textMuted)),
            ]),
            const SizedBox(height: 12),
            TextField(
              key: const Key('tarotQuestion'),
              controller: _q,
              focusNode: _focus,
              maxLength: 200,
              maxLines: 3,
              minLines: 2,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onTapOutside: (_) => _focus.unfocus(),
              onSubmitted: (_) => spreads.isEmpty ? null : _start(spreads),
              buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
              style: AppType.ui(size: 15, weight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: 'Type your question, or pick an idea below',
                suffixIcon: hasQuestion
                    ? IconButton(tooltip: 'Clear question', onPressed: _q.clear, icon: const AppIcon(Ic.close, size: 18, color: AppColors.textMuted))
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final t in tarotTopics) PillChip(label: t.$3, icon: t.$2, selected: _topic == t.$1, dense: true, onTap: () => setState(() => _topic = t.$1)),
            ]),
            const SizedBox(height: 14),
            Text('TRY ASKING', style: AppType.overline()),
            const SizedBox(height: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Column(
                key: ValueKey(_topic),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (final idea in ideas) _IdeaRow(text: idea, selected: _q.text == idea, onTap: () => _useIdea(idea))],
              ),
            ),
          ]),
        ),
      ),
      // Step 2 — the spread
      SectionTitle('Choose a spread', overline: 'Step 2', action: 'See all', onAction: () => context.push('/spreads')),
      SizedBox(
        height: 214,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
          for (final s in featured)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 156,
                child: FeatureTile(
                  image: s.image,
                  title: s.name,
                  subtitle: '${s.positions.length} card${s.positions.length == 1 ? '' : 's'} · ${s.subtitle}',
                  selected: _spreadId == s.id,
                  badge: s.premium && !premium ? const PremiumBadge() : null,
                  onTap: () => _openSpread(s),
                ),
              ),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: GlowCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(children: [
            const IconBadge(Ic.crystalBall, color: AppColors.glow, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('AI interpretation', style: AppType.ui(size: 14.5, weight: FontWeight.w700)),
                Text('Personal insight, advice and follow-up questions.', style: AppType.ui(size: 12.5, weight: FontWeight.w400, color: AppColors.textSecondary)),
              ]),
            ),
            Switch(value: _ai, onChanged: (v) => setState(() => _ai = v)),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
        child: GradientButton(
          key: const Key('startReading'),
          label: spread == null ? 'Start reading' : 'Draw $n card${n == 1 ? '' : 's'} · ${spread.name}',
          icon: Ic.cards,
          onPressed: spreads.isEmpty ? null : () => _start(spreads),
        ),
      ),
      _FreeReadingsBar(user: ref.watch(userDocProvider).value),
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          hasQuestion ? 'Your question is set. Focus on it as you draw.' : 'No question? You’ll get general guidance.',
          textAlign: TextAlign.center,
          style: AppType.ui(size: 12, weight: FontWeight.w500, color: AppColors.textMuted),
        ),
      ),
      const DisclaimerText(),
    ]);
  }
}

class _IdeaRow extends StatelessWidget {
  const _IdeaRow({required this.text, required this.selected, required this.onTap});
  final String text;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            child: Row(children: [
              AppIcon(selected ? Ic.checkCircleFill : Ic.sparkles2, size: 16, color: selected ? AppColors.gold : AppColors.glow),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: AppType.ui(size: 13.5, weight: FontWeight.w500, color: selected ? AppColors.text : AppColors.textSecondary))),
              const AppIcon(Ic.add, size: 16, color: AppColors.textMuted),
            ]),
          ),
        ),
      );
}

/// "1 free reading left today · Go Premium" strip for free users on the tarot home.
/// Mirrors the chat _FreeMessagesBar; the server (freeTarotDaily) stays authoritative.
class _FreeReadingsBar extends StatelessWidget {
  const _FreeReadingsBar({required this.user});
  final AppUser? user;
  @override
  Widget build(BuildContext context) {
    if (user == null || user!.premium) return const SizedBox.shrink();
    final left = user!.freeTarotLeft;
    final exhausted = left <= 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Semantics(
        button: true,
        label: exhausted
            ? "You've used today's free reading. Go Premium for unlimited readings."
            : '$left of $freeTarotDaily free readings left today. Go Premium for unlimited readings.',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: () => context.push('/paywall'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
            ),
            child: Row(children: [
              AppIcon(exhausted ? Ic.crownFill : Ic.sparkles, size: 16, color: AppColors.gold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  exhausted ? "You've used today's free reading" : '$left of $freeTarotDaily free readings left today',
                  style: AppType.ui(size: 12.5, weight: FontWeight.w500, color: AppColors.text),
                ),
              ),
              Text('Go Premium', style: AppType.ui(size: 12.5, weight: FontWeight.w700, color: AppColors.gold)),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------- Card draw ----------------
class CardDrawScreen extends ConsumerStatefulWidget {
  const CardDrawScreen({super.key, required this.request});
  final TarotRequest request;
  @override
  ConsumerState<CardDrawScreen> createState() => _CardDrawState();
}

class _CardDrawState extends ConsumerState<CardDrawScreen> with SingleTickerProviderStateMixin {
  late final _shuffle = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..forward();
  final _picked = <int>[]; // deck indexes, in pick order (slot i <- _picked[i])
  final _landed = <int>{}; // slot indexes whose flying card has arrived
  final _flights = <OverlayEntry>[];
  late final _deckKeys = List.generate(_deckSize, (_) => GlobalKey());
  late final _slotKeys = List.generate(_need, (_) => GlobalKey());
  Map<String, dynamic>? _result;
  Object? _error;
  int _revealed = 0;
  static const _deckSize = 22;
  static const _deckCardW = 62.0;

  int get _need => widget.request.spread.positions.length;
  double _deckAngle(int i) => (i - _deckSize / 2) * 0.045;

  @override
  void initState() {
    super.initState();
    _call(); // start the server draw + interpretation while the user picks cards
  }

  Future<void> _call() async {
    setState(() => _error = null);
    try {
      final r = widget.request;
      final res = await ref.read(startTarotProvider)(
        question: r.question,
        topic: r.topic,
        spreadId: r.spread.custom ? null : r.spread.id,
        customSpreadId: r.spread.custom ? r.spread.id : null,
        aiEnabled: r.aiEnabled,
        readerId: r.readerId,
      );
      if (!mounted) return;
      setState(() => _result = res);
      _maybeReveal();
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.needsPremium) {
        showApiError(context, e);
        context.pop();
        return;
      }
      setState(() => _error = e);
    }
  }

  void _pick(int i) {
    if (_picked.contains(i) || _picked.length >= _need) return;
    final slot = _picked.length;
    HapticFeedback.selectionClick();
    final from = _deckKeys[i].currentContext?.findRenderObject() as RenderBox?;
    final to = _slotKeys[slot].currentContext?.findRenderObject() as RenderBox?;
    final overlay = Overlay.maybeOf(context);
    setState(() => _picked.add(i)); // hides the card in the deck; the flying copy takes its place

    if (MediaQuery.of(context).disableAnimations || from == null || to == null || !from.attached || !to.attached || overlay == null) {
      _land(slot);
      return;
    }
    // Centres via localToGlobal honour the fan rotation, so the copy starts exactly where the card was.
    final start = from.localToGlobal(from.size.center(Offset.zero));
    final end = to.localToGlobal(to.size.center(Offset.zero));
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _FlyingCard(
        from: start,
        to: end,
        fromWidth: _deckCardW,
        toWidth: to.size.width,
        fromAngle: _deckAngle(i),
        onDone: () {
          entry.remove();
          _flights.remove(entry);
          if (mounted) _land(slot);
        },
      ),
    );
    _flights.add(entry);
    overlay.insert(entry);
  }

  void _land(int slot) {
    HapticFeedback.lightImpact();
    setState(() => _landed.add(slot));
    _maybeReveal();
  }

  Future<void> _maybeReveal() async {
    if (_result == null || _landed.length < _need || _revealed > 0) return;
    for (var i = 1; i <= _need; i++) {
      await Future<void>.delayed(Duration(milliseconds: i == 1 ? 350 : 650));
      if (!mounted) return;
      setState(() => _revealed = i);
    }
  }

  @override
  void dispose() {
    for (final e in _flights) {
      e.remove();
    }
    _shuffle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cards = ref.watch(cardMapProvider).value ?? {};
    final drawn = (_result?['cards'] as List?)?.cast<Map>().map((m) => DrawnCard(Map<String, dynamic>.from(m))).toList() ?? [];
    final positions = widget.request.spread.positions;
    final done = _revealed >= _need && _result != null;
    final w = MediaQuery.of(context).size.width;
    final slotW = math.min(90.0, (w - 40) / math.min(_need, 5) - 8);

    return SubPage(
      child: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              CircleIconButton(icon: Ic.left, tooltip: 'Back', onTap: () => context.pop()),
              Expanded(
                child: Column(children: [
                  Text(widget.request.spread.name, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.ui(size: 18, weight: FontWeight.w700)),
                  Text(widget.request.question.isEmpty ? 'General guidance' : widget.request.question,
                      maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: AppType.ui(size: 12, weight: FontWeight.w500, color: AppColors.textSecondary)),
                ]),
              ),
              const SizedBox(width: 46),
            ]),
          ),
          // Slots for picked cards
          Expanded(
            flex: 5,
            child: Center(
              child: SingleChildScrollView(
                child: Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 10, children: [
                  for (var i = 0; i < _need; i++)
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(
                        key: _slotKeys[i],
                        width: slotW,
                        height: slotW * 1.72,
                        child: _landed.contains(i)
                            ? TarotCardView(
                                width: slotW,
                                image: i < drawn.length ? (cards[drawn[i].cardId]?.image ?? 'assets/images/card_back.webp') : 'assets/images/card_back.webp',
                                reversed: i < drawn.length && drawn[i].reversed,
                                faceUp: i < _revealed,
                                selected: i < _revealed,
                                label: i < _revealed && i < drawn.length ? cards[drawn[i].cardId]?.name : 'Card ${i + 1}',
                              )
                                // Settle into the slot with a small bounce and a gilt shimmer.
                                .animate(key: ValueKey('land$i'))
                                .scaleXY(begin: 1.12, end: 1, duration: 320.ms, curve: Curves.easeOutBack)
                                .shimmer(delay: 120.ms, duration: 700.ms, color: AppColors.gold.withValues(alpha: 0.55))
                            : _EmptySlot(index: i, next: i == _picked.length && _picked.length < _need),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: slotW + 10,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Text(
                            i < _revealed && i < drawn.length ? (cards[drawn[i].cardId]?.name ?? '') : positions[i].label,
                            key: ValueKey(i < _revealed),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            style: AppType.ui(size: 11, weight: FontWeight.w600, color: i < _revealed ? AppColors.gold : AppColors.textSecondary),
                          ),
                        ),
                      ),
                    ]),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text(
              _error != null
                  ? friendlyError(_error)
                  : done
                      ? 'Your cards have spoken'
                      : _picked.length < _need
                          ? 'Focus on your question and choose ${_need - _picked.length} card${_need - _picked.length == 1 ? '' : 's'}'
                          : 'Reading the cards...',
              textAlign: TextAlign.center,
              style: TextStyle(color: _error != null ? AppColors.error : Colors.white, fontSize: 15),
            ),
          ),
          // Fanned deck
          Expanded(
            flex: 4,
            child: AnimatedBuilder(
              animation: _shuffle,
              builder: (_, _) {
                final t = Curves.easeOutBack.transform(_shuffle.value.clamp(0, 1));
                return LayoutBuilder(builder: (context, c) {
                  const cw = _deckCardW;
                  return Stack(clipBehavior: Clip.none, children: [
                    for (var i = 0; i < _deckSize; i++)
                      if (!_picked.contains(i))
                        Positioned(
                          left: c.maxWidth / 2 - cw / 2 + (i - _deckSize / 2) * (c.maxWidth - cw - 20) / _deckSize * t,
                          top: 30 + ((i - _deckSize / 2).abs() * 2.2) * t,
                          child: Transform.rotate(
                            angle: _deckAngle(i) * t,
                            child: _DeckCard(
                              key: _deckKeys[i],
                              width: cw,
                              enabled: _picked.length < _need,
                              onTap: () => _pick(i),
                            ),
                          ),
                        ),
                  ]);
                });
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _error != null
                ? GradientButton(label: 'Try again', icon: Ic.refresh, onPressed: _call)
                : GradientButton(
                    label: widget.request.aiEnabled ? 'See My Reading' : 'See Card Meanings',
                    loading: _landed.length >= _need && !done,
                    onPressed: done ? () => context.pushReplacement('/tarot/result/${_result!['readingId']}') : null,
                  ),
          ),
        ]),
      ),
    );
  }
}

// ---------------- Draw animation pieces ----------------

/// A card in the fanned deck. Rises and glows while pressed so the pick feels physical.
class _DeckCard extends StatefulWidget {
  const _DeckCard({super.key, required this.width, required this.onTap, required this.enabled});
  final double width;
  final VoidCallback onTap;
  final bool enabled;
  @override
  State<_DeckCard> createState() => _DeckCardState();
}

class _DeckCardState extends State<_DeckCard> {
  bool _down = false;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        enabled: widget.enabled,
        label: 'Pick card',
        child: GestureDetector(
          onTapDown: widget.enabled ? (_) => setState(() => _down = true) : null,
          onTapCancel: () => setState(() => _down = false),
          onTap: widget.enabled
              ? () {
                  setState(() => _down = false);
                  widget.onTap();
                }
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(0, _down ? -18 : 0, 0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.width * 0.08),
              boxShadow: [BoxShadow(color: (_down ? AppColors.gold : Colors.black).withValues(alpha: _down ? 0.45 : 0.35), blurRadius: _down ? 18 : 6, offset: const Offset(0, 4))],
            ),
            child: Image.asset('assets/images/card_back.webp', width: widget.width, excludeFromSemantics: true),
          ),
        ),
      );
}

/// Dashed-feel placeholder; the next slot to be filled breathes in gold.
class _EmptySlot extends StatelessWidget {
  const _EmptySlot({required this.index, required this.next});
  final int index;
  final bool next;
  @override
  Widget build(BuildContext context) {
    final box = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: next ? AppColors.gold.withValues(alpha: 0.7) : AppColors.border, width: 1.4),
        color: next ? AppColors.gold.withValues(alpha: 0.06) : const Color(0x0AFFFFFF),
      ),
      child: Center(child: Text('${index + 1}', style: AppType.display(size: 22, weight: FontWeight.w400, color: next ? AppColors.gold : AppColors.textMuted))),
    );
    if (!next || MediaQuery.of(context).disableAnimations) return box;
    return box
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .custom(duration: 1100.ms, curve: Curves.easeInOut, builder: (_, v, child) => DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                boxShadow: [BoxShadow(color: AppColors.gold.withValues(alpha: 0.12 + 0.22 * v), blurRadius: 10 + 12 * v)],
              ),
              child: child,
            ));
  }
}

/// Card copy that flies (in an overlay, above everything) from the deck to its slot along an
/// arc: it lifts out of the fan, straightens up, grows to slot size, glows at the apex and
/// trails two faint afterimages.
class _FlyingCard extends StatefulWidget {
  const _FlyingCard({required this.from, required this.to, required this.fromWidth, required this.toWidth, required this.fromAngle, required this.onDone});
  final Offset from, to;
  final double fromWidth, toWidth, fromAngle;
  final VoidCallback onDone;
  @override
  State<_FlyingCard> createState() => _FlyingCardState();
}

class _FlyingCardState extends State<_FlyingCard> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 720))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    })
    ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  // Quadratic bezier with the control point lifted above both ends.
  Offset _at(double t) {
    final a = widget.from, b = widget.to;
    final ctrl = Offset((a.dx + b.dx) / 2 + (a.dx - b.dx) * 0.15, math.min(a.dy, b.dy) - 90);
    final u = 1 - t;
    return a * (u * u) + ctrl * (2 * u * t) + b * (t * t);
  }

  Widget _card(double t, {double opacity = 1}) {
    final e = Curves.easeInOutCubic.transform(t.clamp(0, 1));
    final w = widget.fromWidth + (widget.toWidth - widget.fromWidth) * e;
    final bump = 1 + 0.12 * math.sin(math.pi * e); // swell at the apex
    final angle = widget.fromAngle * (1 - e) + 0.35 * math.sin(math.pi * e) * (widget.to.dx > widget.from.dx ? 1 : -1);
    final p = _at(e);
    final h = w * 1.72;
    return Positioned(
      left: p.dx - w / 2,
      top: p.dy - h / 2,
      child: Opacity(
        opacity: opacity,
        child: Transform.rotate(
          angle: angle,
          child: Transform.scale(
            scale: bump,
            child: Container(
              width: w,
              height: h,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(w * 0.08),
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.7)),
                boxShadow: [BoxShadow(color: AppColors.gold.withValues(alpha: 0.2 + 0.4 * math.sin(math.pi * e)), blurRadius: 14 + 20 * math.sin(math.pi * e))],
              ),
              child: Image.asset('assets/images/card_back.webp', fit: BoxFit.cover, excludeFromSemantics: true),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) {
            final t = _c.value;
            return Stack(children: [
              if (t > 0.12) _card(t - 0.12, opacity: 0.12),
              if (t > 0.06) _card(t - 0.06, opacity: 0.25),
              _card(t),
            ]);
          },
        ),
      );
}

// ---------------- Result ----------------

final tarotReadingProvider = StreamProvider.family<TarotReading?, String>((ref, id) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return Stream.value(null);
  return FirebaseFirestore.instance.doc('users/$uid/tarotReadings/$id').snapshots().map((s) => s.exists ? TarotReading(s.id, s.data()!) : null);
});

class TarotResultScreen extends ConsumerWidget {
  const TarotResultScreen({super.key, required this.readingId});
  final String readingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(tarotReadingProvider(readingId));
    final cards = ref.watch(cardMapProvider).value ?? {};
    return SubPage(
      child: SafeArea(
        child: r.when(
          loading: () => const Loading(),
          error: (e, _) => const MascotMessage(title: 'Could not load', message: 'Check your connection and try again.'),
          data: (t) {
            if (t == null) return const Center(child: MascotMessage(title: 'Reading not found', message: 'It may have been deleted.'));
            return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
              Row(children: [
                CircleIconButton(icon: Ic.left, tooltip: 'Back', onTap: () => context.canPop() ? context.pop() : context.go('/tarot')),
                const SizedBox(width: 12),
                Expanded(child: Text(t.title, style: Theme.of(context).textTheme.headlineSmall)),
              ]),
              const SizedBox(height: 6),
              Text('${t.spreadName} · ${t.question.isEmpty ? 'General guidance' : '“${t.question}”'}', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 16),
              SizedBox(
                height: 230,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final c in t.cards)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: GestureDetector(
                        onTap: () => context.push('/cards/${c.cardId}'),
                        child: SizedBox(
                          width: 96,
                          child: Column(children: [
                            TarotCardView(image: cards[c.cardId]?.image ?? 'assets/images/card_back.webp', reversed: c.reversed, width: 86, label: cards[c.cardId]?.name),
                            const SizedBox(height: 6),
                            Text(c.positionLabel, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                          ]),
                        ),
                      ),
                    ),
                ]),
              ),
              if (t.safety) ...[
                GlowCard(child: Text(t.safetyMessage, style: const TextStyle(color: Colors.white))),
              ] else ...[
                for (final c in t.cards) _CardInterpretation(t: t, c: c, card: cards[c.cardId]),
                if (t.hasInterpretation) ...[
                  const SizedBox(height: 8),
                  GlowCard(
                    selected: true,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const _ResultHeading(icon: Ic.crystalBall, title: 'The big picture', color: AppColors.gold),
                      if (t.leaning != 'not_applicable' && t.leaning.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Tag('Leaning: ${t.leaning}', color: AppColors.gold, icon: Ic.compass),
                      ],
                      const SizedBox(height: 10),
                      Text(t.synthesis, style: AppType.ui(size: 14.5, weight: FontWeight.w400, color: AppColors.textSecondary, height: 1.6)),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  GlowCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const _ResultHeading(icon: Ic.compass, title: 'Guidance for you'),
                      const SizedBox(height: 10),
                      for (final (i, a) in t.advice.indexed)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Container(
                              width: 24,
                              height: 24,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.glow.withValues(alpha: 0.16), border: Border.all(color: AppColors.glow.withValues(alpha: 0.4))),
                              child: Text('${i + 1}', style: AppType.ui(size: 11.5, weight: FontWeight.w700, color: AppColors.glow)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Text(a, style: AppType.ui(size: 14, weight: FontWeight.w400, color: AppColors.textSecondary, height: 1.5))),
                          ]),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  GlowCard(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const AppIcon(Ic.quote, size: 26, color: AppColors.gold),
                      const SizedBox(width: 12),
                      Expanded(child: Text(t.affirmation, style: AppType.display(size: 18, weight: FontWeight.w400, style: FontStyle.italic, height: 1.35))),
                    ]),
                  ),
                  if (t.followUps.isNotEmpty) ...[
                    const SectionTitle('Ask a follow-up'),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final q in t.followUps)
                        PillChip(
                          label: q,
                          icon: Ic.chat,
                          dense: true,
                          onTap: () => context.push('/chat/${t.readerId.isEmpty ? 'selene' : t.readerId}?reading=${t.id}&q=${Uri.encodeComponent(q)}'),
                        ),
                    ]),
                  ],
                ],
              ],
              const SizedBox(height: 16),
              GradientButton(
                label: 'Discuss with a Reader',
                icon: Ic.chat,
                onPressed: () => context.push('/chat/${t.readerId.isEmpty ? 'selene' : t.readerId}?reading=${t.id}'),
              ),
              const DisclaimerText(),
            ]);
          },
        ),
      ),
    );
  }
}

class _ResultHeading extends StatelessWidget {
  const _ResultHeading({required this.icon, required this.title, this.color = AppColors.glow});
  final String icon, title;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(children: [
        IconBadge(icon, color: color, size: 32),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: AppType.display(size: 19, weight: FontWeight.w500))),
      ]);
}

class _CardInterpretation extends StatelessWidget {
  const _CardInterpretation({required this.t, required this.c, required this.card});
  final TarotReading t;
  final DrawnCard c;
  final TarotCard? card;
  @override
  Widget build(BuildContext context) {
    final ai = t.cardInterp(c.position);
    final headline = ai?['headline'] as String? ?? (c.reversed ? card?.reversedKeywords.join(' · ') : card?.keywords.join(' · ')) ?? '';
    final body = ai?['interpretation'] as String? ?? (c.reversed ? card?.reversed : card?.upright) ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlowCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Tag(c.positionLabel),
            Text('${card?.name ?? c.cardId}${c.reversed ? ' · Reversed' : ''}', style: AppType.ui(size: 14, weight: FontWeight.w700, color: AppColors.gold)),
          ]),
          const SizedBox(height: 10),
          Text(headline, style: AppType.ui(size: 15, weight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(body, style: AppType.ui(size: 14, weight: FontWeight.w400, color: AppColors.textSecondary, height: 1.55)),
        ]),
      ),
    );
  }
}
