import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../app.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../data/api.dart';
import '../data/palm_store.dart';
import 'palm.dart';

class MyReadingsScreen extends ConsumerStatefulWidget {
  const MyReadingsScreen({super.key, this.initialFilter});
  final String? initialFilter;
  @override
  ConsumerState<MyReadingsScreen> createState() => _MyReadingsState();
}

class _MyReadingsState extends ConsumerState<MyReadingsScreen> {
  late String _type = widget.initialFilter ?? 'all';

  String _date(Object? ts) => ts is Timestamp ? DateFormat.yMMMd().add_jm().format(ts.toDate()) : '';

  Future<bool> _confirmDelete() async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Delete reading?'),
          content: const Text('This cannot be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete', style: TextStyle(color: AppColors.error))),
          ],
        ),
      ) ??
      false;

  /// Confirms, runs the delete and gives the user feedback (Firestore deletes can fail offline).
  Future<void> _confirmAndDelete(Future<void> Function() op, [String done = 'Reading deleted.']) async {
    if (!await _confirmDelete()) return;
    try {
      await op();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palms = ref.watch(palmHistoryProvider).value ?? [];
    final tarots = ref.watch(tarotHistoryProvider).value ?? [];
    final chats = ref.watch(chatsProvider).value ?? [];
    final readers = {for (final r in ref.watch(readersProvider).value ?? []) r.id: r};
    final cards = ref.watch(cardMapProvider).value ?? {};

    final items = <(DateTime, Widget)>[];
    if (_type == 'all' || _type == 'palm') {
      for (final (id, d) in palms) {
        final r = palmFromDoc(d);
        items.add((
          (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000),
          _Item(
            key: ValueKey('p$id'),
            leading: Consumer(builder: (_, ref, _) {
              final f = ref.watch(palmPhotoProvider(id)).value;
              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: f != null ? Image.memory(f, width: 56, height: 56, fit: BoxFit.cover, cacheWidth: 168) : Image.asset('assets/images/palm_celestial.webp', width: 56, height: 56, fit: BoxFit.cover),
              );
            }),
            title: 'Palm reading · ${r?.handTypeName ?? ''}',
            subtitle: '${d['hand'] == 'right' ? 'Right' : 'Left'} hand · ${_date(d['createdAt'])}',
            onTap: () => context.push('/palm/result/$id'),
            onDelete: () => _confirmAndDelete(() async {
              await userRef().collection('palmReadings').doc(id).delete();
              await PalmStore.delete(id);
            }),
          ),
        ));
      }
    }
    if (_type == 'all' || _type == 'tarot') {
      for (final t in tarots) {
        final first = t.cards.isEmpty ? null : cards[t.cards.first.cardId];
        items.add((
          t.createdAt ?? DateTime(2000),
          _Item(
            key: ValueKey('t${t.id}'),
            leading: TarotCardView(image: first?.image ?? 'assets/images/card_back.webp', width: 34, reversed: t.cards.firstOrNull?.reversed ?? false),
            title: t.title,
            subtitle: '${t.spreadName} · ${t.createdAt == null ? '' : DateFormat.yMMMd().add_jm().format(t.createdAt!)}',
            onTap: () => context.push('/tarot/result/${t.id}'),
            onDelete: () => _confirmAndDelete(() => userRef().collection('tarotReadings').doc(t.id).delete()),
          ),
        ));
      }
    }
    if (_type == 'all' || _type == 'chat') {
      for (final (id, d) in chats) {
        final r = readers[d['readerId']];
        items.add((
          (d['lastMessageAt'] as Timestamp?)?.toDate() ?? DateTime(2000),
          _Item(
            key: ValueKey('c$id'),
            leading: CircleAvatar(radius: 26, backgroundImage: AssetImage(r?.image ?? 'assets/images/reader_selene.webp')),
            title: '${d['title'] ?? 'Chat with ${r?.name ?? 'reader'}'}',
            subtitle: '${r?.name ?? ''} · ${_date(d['lastMessageAt'])}',
            onTap: () => context.push('/chat/${d['readerId']}?chat=$id'),
            onDelete: () => _confirmAndDelete(() async {
              final ref = userRef().collection('chats').doc(id);
              final msgs = await ref.collection('messages').get();
              for (final m in msgs.docs) {
                await m.reference.delete();
              }
              await ref.delete();
            }, 'Chat deleted.'),
          ),
        ));
      }
    }
    items.sort((a, b) => b.$1.compareTo(a.$1));

    return SubPage(
      child: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              CircleIconButton(icon: Ic.left, tooltip: 'Back', onTap: () => context.pop()),
              const SizedBox(width: 12),
              Text('My Readings', style: Theme.of(context).textTheme.headlineSmall),
            ]),
          ),
          ChipRow(children: [
            for (final f in const [('all', 'All', Ic.grid), ('palm', 'Palm', Ic.hand), ('tarot', 'Tarot', Ic.cards), ('chat', 'Chats', Ic.chat)])
              PillChip(label: f.$2, icon: f.$3, selected: _type == f.$1, onTap: () => setState(() => _type = f.$1)),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: items.isEmpty
                ? const Center(child: MascotMessage(title: 'No readings yet', message: 'Your palm readings, tarot spreads and chats will appear here.'))
                : ListView(padding: const EdgeInsets.all(12), children: [for (final i in items) i.$2]),
          ),
        ]),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({super.key, required this.leading, required this.title, required this.subtitle, required this.onTap, required this.onDelete});
  final Widget leading;
  final String title, subtitle;
  final VoidCallback onTap, onDelete;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: GlowCard(
          onTap: onTap,
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            SizedBox(width: 56, child: Center(child: leading)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ]),
            ),
            IconButton(tooltip: 'Delete', onPressed: onDelete, icon: const AppIcon(Ic.delete, color: AppColors.textMuted)),
          ]),
        ),
      );
}
