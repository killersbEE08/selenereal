import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../data/api.dart';
import '../data/models.dart';

final cardInsightProvider = FutureProvider.family<String, String>((ref, cardId) => Api.cardInsight(cardId, false));

Future<void> toggleCollection(String cardId, bool saved) async {
  final ref = userRef().collection('collection').doc(cardId);
  saved ? await ref.delete() : await ref.set({'savedAt': FieldValue.serverTimestamp()});
}

class CardMeaningsScreen extends ConsumerStatefulWidget {
  const CardMeaningsScreen({super.key, this.initialCardId, this.collectionOnly = false});
  final String? initialCardId;
  final bool collectionOnly;
  @override
  ConsumerState<CardMeaningsScreen> createState() => _CardMeaningsState();
}

class _CardMeaningsState extends ConsumerState<CardMeaningsScreen> {
  String _query = '';
  late String _filter = widget.collectionOnly ? 'saved' : 'all';
  String? _selected;
  int _tab = 0;
  String _sort = 'major';

  static const _filters = [('all', Ic.grid, 'All cards'), ('major', Ic.star, 'Major Arcana'), ('minor', Ic.cards, 'Minor Arcana'), ('love', Ic.heart, 'Love'), ('career', Ic.briefcase, 'Career'), ('saved', Ic.bookmark, 'My collection')];

  List<TarotCard> _apply(List<TarotCard> cards, Set<String> saved) {
    final q = _query.toLowerCase();
    var l = cards.where((c) {
      final matchQ = q.isEmpty ||
          c.name.toLowerCase().contains(q) ||
          c.keywords.any((k) => k.toLowerCase().contains(q)) ||
          (c.suit ?? '').contains(q);
      final matchF = switch (_filter) {
        'major' => c.isMajor,
        'minor' => !c.isMajor,
        'love' => c.love.toLowerCase().contains(RegExp('love|romance|partner')) && c.yesNo == 'yes',
        'career' => c.career.toLowerCase().contains(RegExp('success|career|promotion|achievement')) && c.yesNo != 'no',
        'saved' => saved.contains(c.id),
        _ => true,
      };
      return matchQ && matchF;
    }).toList();
    if (_sort == 'az') l.sort((a, b) => a.name.compareTo(b.name));
    if (_sort == 'suit') l.sort((a, b) => (a.suit ?? '').compareTo(b.suit ?? ''));
    return l;
  }

  @override
  Widget build(BuildContext context) {
    final cards = ref.watch(cardsProvider).value ?? [];
    final saved = ref.watch(collectionProvider).value ?? {};
    if (cards.isEmpty) return const SubPage(child: Loading());
    final list = _apply(cards, saved);
    final featured = cards.firstWhere((c) => c.id == (_selected ?? widget.initialCardId ?? 'major_19'), orElse: () => cards[19]);
    final tabs = ['Upright Meaning', 'Reversed Meaning', 'Symbolism', 'In Love', 'In Career'];
    final tabText = [featured.upright, featured.reversed, featured.symbolism, featured.love, featured.career][_tab];
    final tabIcon = [Ic.sun, Ic.refresh, Ic.eye, Ic.heart, Ic.briefcase][_tab];

    return SubPage(
      child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        HeroHeader(
          title: 'Card Meanings',
          subtitle: 'Learn, explore and get AI insights',
          image: 'assets/images/hero_cards.webp',
          headingLead: 'Discover the Stories Behind Every',
          headingAccent: 'Card',
          description: 'Learn the meaning, symbolism and real-life guidance for each tarot card.',
          action: OutlinePillButton(label: 'My Collection', icon: Ic.bookmark, onPressed: () => setState(() => _filter = 'saved')),
          height: 380,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(prefixIcon: Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: AppIcon(Ic.search, size: 20, color: AppColors.textMuted)), prefixIconConstraints: BoxConstraints(minWidth: 44), hintText: 'Search cards (e.g. The Sun, Love, Success...)'),
          ),
        ),
        const SizedBox(height: 12),
        ChipRow(children: [
          for (final f in _filters) PillChip(label: f.$3, icon: f.$2, selected: _filter == f.$1, onTap: () => setState(() => _filter = f.$1)),
        ]),
        const SizedBox(height: 12),
        // Featured card
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: GlowCard(
            child: Column(children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                GestureDetector(
                  onTap: () => context.push('/cards/${featured.id}'),
                  child: TarotCardView(image: featured.image, width: 118, label: featured.name),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Tag(featured.isMajor ? 'Major Arcana' : _cap(featured.suit ?? ''), color: AppColors.gold, icon: featured.isMajor ? Ic.star : Ic.cards),
                      const Spacer(),
                      IconButton(
                        tooltip: saved.contains(featured.id) ? 'Remove from collection' : 'Save to collection',
                        onPressed: () => toggleCollection(featured.id, saved.contains(featured.id)),
                        icon: AppIcon(saved.contains(featured.id) ? Ic.bookmarkFill : Ic.bookmark, color: AppColors.gold),
                      ),
                    ]),
                    Text(featured.name, style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 6),
                    Wrap(spacing: 4, runSpacing: 4, children: [for (final k in featured.keywords) Tag(k)]),
                    const SizedBox(height: 8),
                    Text(featured.description, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                  ]),
                ),
              ]),
              const Divider(color: AppColors.border, height: 24),
              _AiInsight(cardId: featured.id),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        ChipRow(children: [for (final (i, t) in tabs.indexed) PillChip(label: t, selected: _tab == i, onTap: () => setState(() => _tab = i))]),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: GlowCard(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              IconBadge(tabIcon, color: AppColors.gold, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tabs[_tab], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(tabText, style: const TextStyle(color: AppColors.textSecondary, height: 1.45)),
                ]),
              ),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 12, 8),
          child: Row(children: [
            Expanded(child: Text(_filter == 'saved' ? 'My Collection (${list.length})' : 'All Tarot Cards (${list.length})', style: Theme.of(context).textTheme.titleLarge)),
            DropdownButton<String>(
              value: _sort,
              dropdownColor: AppColors.cardElevated,
              underline: const SizedBox(),
              style: const TextStyle(color: AppColors.glow),
              items: const [
                DropdownMenuItem(value: 'major', child: Text('Sort: Deck order')),
                DropdownMenuItem(value: 'az', child: Text('Sort: A–Z')),
                DropdownMenuItem(value: 'suit', child: Text('Sort: Suit')),
              ],
              onChanged: (v) => setState(() => _sort = v ?? 'major'),
            ),
          ]),
        ),
        if (list.isEmpty)
          const MascotMessage(title: 'No cards found', message: 'Try another search or filter.')
        else
          SizedBox(
            height: 210,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final c = list[i];
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _selected = c.id;
                      _tab = 0;
                    }),
                    onLongPress: () => context.push('/cards/${c.id}'),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TarotCardView(image: c.image, width: 86, selected: c.id == featured.id, label: c.name),
                      const SizedBox(height: 4),
                      SizedBox(width: 90, child: Text(c.name, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12))),
                      Text(c.roman, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    ]),
                  ),
                );
              },
            ),
          ),
      ]),
    );
  }
}

String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

class _AiInsight extends ConsumerWidget {
  const _AiInsight({required this.cardId});
  final String cardId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insight = ref.watch(cardInsightProvider(cardId));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [
        AppIcon(Ic.sparklesFill, color: AppColors.gold, size: 18),
        SizedBox(width: 6),
        Text('AI insight', style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppColors.glow.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.glow.withValues(alpha: 0.3))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const CircleAvatar(radius: 20, backgroundImage: AssetImage('assets/images/reader_selene.webp')),
          const SizedBox(width: 10),
          Expanded(
            child: insight.when(
              loading: () => const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator(color: AppColors.glow, backgroundColor: AppColors.border)),
              error: (e, _) => GestureDetector(
                onTap: () => ref.invalidate(cardInsightProvider(cardId)),
                child: const Text('Selene is resting. Tap to try again.', style: TextStyle(color: AppColors.textSecondary)),
              ),
              data: (t) => Text(t, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4)),
            ),
          ),
        ]),
      ),
    ]);
  }
}

class CardDetailScreen extends ConsumerWidget {
  const CardDetailScreen({super.key, required this.cardId});
  final String cardId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final card = ref.watch(cardMapProvider).value?[cardId];
    final saved = ref.watch(collectionProvider).value ?? {};
    if (card == null) return const SubPage(child: Loading());
    Widget section(String icon, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GlowCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [IconBadge(icon, color: AppColors.gold, size: 30), const SizedBox(width: 10), Expanded(child: Text(title, style: AppType.ui(size: 15, weight: FontWeight.w700)))]),
              const SizedBox(height: 6),
              Text(body, style: const TextStyle(color: AppColors.textSecondary, height: 1.5)),
            ]),
          ),
        );
    return SubPage(
      child: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            CircleIconButton(icon: Ic.left, tooltip: 'Back', onTap: () => context.pop()),
            const Spacer(),
            CircleIconButton(
              icon: saved.contains(card.id) ? Ic.bookmarkFill : Ic.bookmark,
              tooltip: 'Save to collection',
              onTap: () => toggleCollection(card.id, saved.contains(card.id)),
            ),
          ]),
          const SizedBox(height: 12),
          Center(child: TarotCardView(image: card.image, width: 180, label: card.name)),
          const SizedBox(height: 16),
          Center(child: Text(card.name, style: Theme.of(context).textTheme.headlineSmall!.copyWith(fontSize: 28))),
          Center(
            child: Text(
              '${card.isMajor ? 'Major Arcana ${card.roman}' : '${_cap(card.suit ?? '')} · Minor Arcana'} · ${card.element} · ${card.astrology}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 10),
          Center(child: Wrap(spacing: 6, runSpacing: 6, children: [for (final k in card.keywords) Tag(k), Tag('Yes/No: ${card.yesNo}', color: AppColors.gold)])),
          const SizedBox(height: 16),
          section(Ic.book, 'Overview', card.description),
          _AiInsight(cardId: card.id),
          const SizedBox(height: 12),
          section(Ic.sun, 'Upright', card.upright),
          section(Ic.refresh, 'Reversed · ${card.reversedKeywords.join(', ')}', card.reversed),
          section(Ic.eye, 'Symbolism', card.symbolism),
          section(Ic.heart, 'In love', card.love),
          section(Ic.briefcase, 'In career', card.career),
          GradientButton(
            label: 'Ask Selene about this card',
            icon: Ic.chat,
            onPressed: () => context.push('/chat/selene?q=${Uri.encodeComponent('What does ${card.name} mean for me right now?')}'),
          ),
        ]),
      ),
    );
  }
}
