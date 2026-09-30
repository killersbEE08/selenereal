import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../data/api.dart';
import '../data/models.dart';

const chatSuggestions = [
  (Ic.sparkles, 'What does my future look like?'),
  (Ic.heart, 'Is there someone special coming?'),
  (Ic.briefcase, 'Give me guidance for my career'),
  (Ic.cards, 'Pull one card for today'),
];

class ReadersScreen extends ConsumerStatefulWidget {
  const ReadersScreen({super.key});
  @override
  ConsumerState<ReadersScreen> createState() => _ReadersState();
}

class _ReadersState extends ConsumerState<ReadersScreen> {
  String _filter = 'all';
  static const _filters = ['all', 'mystical', 'empathetic', 'practical', 'spiritual', 'fun'];

  void _chat(Reader r, {String? q}) {
    if (r.premium && !ref.read(isPremiumProvider)) {
      context.push('/paywall');
      return;
    }
    context.push('/chat/${r.id}${q == null ? '' : '?q=${Uri.encodeComponent(q)}'}');
  }

  @override
  Widget build(BuildContext context) {
    final readers = ref.watch(readersProvider).value ?? [];
    final premium = ref.watch(isPremiumProvider);
    final list = _filter == 'all' ? readers : readers.where((r) => r.filters.contains(_filter)).toList();
    final selene = readers.where((r) => r.id == 'selene').firstOrNull;
    return SubPage(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const HeroHeader(
            title: 'Choose Your AI Tarot Reader',
            subtitle: 'Different energies, unique guidance',
            image: 'assets/images/hero_readers.webp',
            headingLead: 'Meet Your',
            headingAccent: 'Guides',
            description: 'Each AI reader has a unique personality, style and spiritual approach. Choose the one that resonates with you.',
            height: 380,
          ),
          ChipRow(
            children: [for (final f in _filters) PillChip(label: f == 'all' ? 'All' : '${f[0].toUpperCase()}${f.substring(1)}', selected: _filter == f, onTap: () => setState(() => _filter = f))],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.56,
              children: [for (final r in list) _ReaderCard(r: r, locked: r.premium && !premium, onChat: () => _chat(r))],
            ),
          ),
          if (selene != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
              child: GlowCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(radius: 26, backgroundImage: AssetImage(selene.image)),
                        const SizedBox(width: 10),
                        const Text(
                          'Chat with Selene',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
                        ),
                        const SizedBox(width: 8),
                        const CircleAvatar(radius: 4, backgroundColor: AppColors.success),
                        const Text(' Online', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _Bubble(text: selene.greeting, fromUser: false),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in chatSuggestions.take(3))
                          PillChip(
                            label: s.$2,
                            icon: s.$1,
                            dense: true,
                            onTap: () => _chat(selene, q: s.$2),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReaderCard extends StatelessWidget {
  const _ReaderCard({required this.r, required this.locked, required this.onChat});
  final Reader r;
  final bool locked;
  final VoidCallback onChat;
  @override
  Widget build(BuildContext context) => GlowCard(
    selected: r.popular,
    padding: EdgeInsets.zero,
    onTap: onChat,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ShaderMask(
                shaderCallback: (b) =>
                    const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black, Colors.black, Colors.transparent], stops: [0, 0.75, 1]).createShader(b),
                blendMode: BlendMode.dstIn,
                child: Image.asset(r.image, fit: BoxFit.cover, alignment: Alignment.topCenter, excludeFromSemantics: true),
              ),
              if (r.popular) const Positioned(right: 8, top: 8, child: PremiumBadge(label: 'Popular')),
              if (r.premium) const Positioned(right: 8, top: 8, child: PremiumBadge()),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                r.name,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17),
              ),
              const SizedBox(height: 4),
              Wrap(spacing: 4, runSpacing: 4, children: [for (final t in r.tags) Tag(t)]),
              const SizedBox(height: 6),
              Text(
                r.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
              ),
              const SizedBox(height: 8),
              GradientButton(label: locked ? 'Unlock' : 'Chat Now', icon: locked ? Ic.lockFill : Ic.chat, height: 40, onPressed: onChat),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.fromUser, this.cards = const [], this.cardMap = const {}});
  final String text;
  final bool fromUser;
  final List<Map<String, dynamic>> cards;
  final Map<String, TarotCard> cardMap;
  @override
  Widget build(BuildContext context) => Align(
    alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: fromUser ? AppColors.violet : null,
          color: fromUser ? null : const Color(0xFF17142F),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(fromUser ? 18 : 4),
            bottomRight: Radius.circular(fromUser ? 4 : 18),
          ),
          border: fromUser ? null : Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (cards.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                children: [
                  for (final c in cards)
                    GestureDetector(
                      onTap: () => context.push('/cards/${c['cardId']}'),
                      child: Column(
                        children: [
                          TarotCardView(image: cardMap[c['cardId']]?.image ?? 'assets/images/card_back.webp', reversed: c['reversed'] == true, width: 60, label: cardMap[c['cardId']]?.name),
                          SizedBox(
                            width: 70,
                            child: Text(
                              cardMap[c['cardId']]?.name ?? '',
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              style: const TextStyle(color: AppColors.gold, fontSize: 10),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            SelectableText(text, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4)),
          ],
        ),
      ),
    ),
  );
}

final _messagesProvider = StreamProvider.family<List<Map<String, dynamic>>, String>((ref, chatId) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return Stream.value([]);
  return FirebaseFirestore.instance.collection('users/$uid/chats/$chatId/messages').orderBy('createdAt').snapshots().map((q) => q.docs.map((d) => d.data()).toList());
});

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.readerId, this.chatId, this.initialText, this.tarotReadingId});
  final String readerId;
  final String? chatId, initialText, tarotReadingId;
  @override
  ConsumerState<ChatScreen> createState() => _ChatState();
}

class _ChatState extends ConsumerState<ChatScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  late String? _chatId = widget.chatId;
  final _pending = <String>[];
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // Rebuild so the send button reflects whether there is text to send.
    _text.addListener(_onTextChanged);
    if (widget.initialText != null && widget.initialText!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _send(widget.initialText!));
    }
  }

  void _onTextChanged() => setState(() {});

  @override
  void dispose() {
    _text.removeListener(_onTextChanged);
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    text = text.trim();
    if (text.isEmpty || _sending) return;
    final user = ref.read(userDocProvider).value;
    if (user != null && user.freeChatsLeft <= 0 && !useEmulator) {
      context.push('/paywall');
      return;
    }
    setState(() {
      _sending = true;
      _pending.add(text);
      _text.clear();
    });
    _toBottom();
    try {
      final res = await Api.chat(chatId: _chatId, readerId: widget.readerId, text: text, tarotReadingId: _chatId == null ? widget.tarotReadingId : null);
      if (mounted) setState(() => _chatId = res['chatId'] as String?);
    } catch (e) {
      if (mounted) {
        if (_text.text.isEmpty) _text.text = text; // keep what the user typed so they can retry
        showApiError(context, e);
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _pending.remove(text);
        });
        _toBottom();
      }
    }
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent + 200, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  });

  @override
  Widget build(BuildContext context) {
    final reader = (ref.watch(readersProvider).value ?? []).where((r) => r.id == widget.readerId).firstOrNull;
    final cards = ref.watch(cardMapProvider).value ?? {};
    final msgs = _chatId == null ? const <Map<String, dynamic>>[] : (ref.watch(_messagesProvider(_chatId!)).value ?? const []);
    if (reader == null) return const SubPage(child: Loading());
    final shownUserTexts = msgs.where((m) => m['role'] == 'user').map((m) => m['text']).toSet();
    ref.listen(_messagesProvider(_chatId ?? '_'), (_, _) => _toBottom());

    return SubPage(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  CircleIconButton(icon: Ic.left, tooltip: 'Back', onTap: () => context.pop()),
                  const SizedBox(width: 10),
                  CircleAvatar(radius: 22, backgroundImage: AssetImage(reader.image)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          reader.name,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
                        ),
                        Text(_sending ? 'Reading the stars…' : reader.tags.join(' · '), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                  OutlinePillButton(label: 'Change', icon: Ic.transfer, onPressed: () => context.pushReplacement('/readers')),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  _Bubble(text: reader.greeting, fromUser: false),
                  for (final m in msgs)
                    _Bubble(
                      text: '${m['text'] ?? ''}',
                      fromUser: m['role'] == 'user',
                      cards: (m['cards'] as List? ?? []).cast<Map>().map((e) => Map<String, dynamic>.from(e)).toList(),
                      cardMap: cards,
                    ),
                  for (final p in _pending.where((p) => !shownUserTexts.contains(p))) _Bubble(text: p, fromUser: true),
                  if (_sending)
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 40,
                          child: LinearProgressIndicator(color: AppColors.gold, backgroundColor: AppColors.border),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (msgs.isEmpty && !_sending)
              ChipRow(
                children: [for (final s in chatSuggestions) PillChip(label: s.$2, icon: s.$1, dense: true, onTap: () => _send(s.$2))],
              ),
            _FreeMessagesBar(user: ref.watch(userDocProvider).value),
            if ((ref.watch(userDocProvider).value?.freeChatsLeft ?? 1) <= 0 && !useEmulator)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: GradientButton(label: 'Go Premium to keep chatting', icon: Ic.crownFill, trailing: false, onPressed: () => context.push('/paywall')),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _text,
                        maxLength: 600,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: _send,
                        decoration: InputDecoration(hintText: 'Ask ${reader.name} anything…', counterText: ''),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Builder(builder: (context) {
                      final canSend = _text.text.trim().isNotEmpty && !_sending;
                      return Semantics(
                        button: true,
                        enabled: canSend,
                        label: 'Send',
                        excludeSemantics: true,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 150),
                          opacity: canSend ? 1 : 0.45,
                          child: InkResponse(
                            onTap: canSend ? () => _send(_text.text) : null,
                            radius: 30,
                            child: Container(
                              width: 50,
                              height: 50,
                              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.cta),
                              child: Center(
                                child: _sending
                                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.onGold))
                                    : const AppIcon(Ic.send, color: AppColors.onGold),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "2 of 3 free messages left today · Go Premium" strip for free users.
class _FreeMessagesBar extends StatelessWidget {
  const _FreeMessagesBar({required this.user});
  final AppUser? user;
  @override
  Widget build(BuildContext context) {
    if (user == null || user!.premium) return const SizedBox.shrink();
    final left = user!.freeChatsLeft;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Semantics(
        button: true,
        label: '$left of $freeChatDaily free messages left today. Go Premium for unlimited chat.',
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
            child: Row(
              children: [
                const AppIcon(Ic.chat, size: 16, color: AppColors.gold),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    left > 0 ? '$left of $freeChatDaily free messages left today' : "You've used today's free messages",
                    style: AppType.ui(size: 12.5, weight: FontWeight.w500, color: AppColors.text),
                  ),
                ),
                Text(
                  'Go Premium',
                  style: AppType.ui(size: 12.5, weight: FontWeight.w700, color: AppColors.gold),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
