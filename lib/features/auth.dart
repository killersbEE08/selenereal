import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../app.dart';
import '../core/astro.dart';
import '../core/birth_fields.dart';
import '../core/theme.dart';
import '../core/validators.dart';
import '../core/widgets.dart';
import '../data/api.dart';
import '../data/google_auth.dart';
import '../data/models.dart';
import 'legal.dart';

/// White "Continue with Google" pill (Google branding guidelines: white bg, multicolor G).
class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: Opacity(
          opacity: onPressed == null ? 0.6 : 1,
          child: Material(
            color: Colors.white,
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onPressed,
              child: SizedBox(
                height: 54,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const _GoogleG(size: 22),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(label,
                        overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF1F1F1F), fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}

/// Google "G" drawn with four arcs (no network or extra asset needed).
class _GoogleG extends StatelessWidget {
  const _GoogleG({required this.size});
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: const CustomPaint(painter: _GPainter()));
}

class _GPainter extends CustomPainter {
  const _GPainter();
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width * 0.2;
    final r = Rect.fromLTWH(w / 2, w / 2, s.width - w, s.height - w);
    Paint p(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = w;
    // Flutter arcs: 0° = 3 o'clock, positive sweep = clockwise. The G opens between -45° and 0°.
    const d = 3.14159265 / 180;
    canvas.drawArc(r, 0, 45 * d, false, p(const Color(0xFF4285F4))); // blue (right, lower)
    canvas.drawArc(r, 45 * d, 90 * d, false, p(const Color(0xFF34A853))); // green (bottom)
    canvas.drawArc(r, 135 * d, 90 * d, false, p(const Color(0xFFFBBC05))); // yellow (left)
    canvas.drawArc(r, 225 * d, 90 * d, false, p(const Color(0xFFEA4335))); // red (top)
    canvas.drawLine(Offset(s.width / 2, s.height / 2), Offset(s.width - w / 2, s.height / 2), p(const Color(0xFF4285F4)));
  }

  @override
  bool shouldRepaint(_GPainter old) => false;
}

/// First-run onboarding: a short, interactive welcome.
///
///  1. Welcome — who Selene is.
///  2. Intent — "what's on your mind?" (pre-fills the profile focus areas).
///  3. A first card — tap one of three face-down cards to reveal it (instant value, no account needed).
///  4. What you can do + privacy promise → Get started.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingState();
}

/// Prefs key holding the focus areas picked during onboarding (read by profile setup).
const onboardingFocusKey = 'onboardingFocus';

const onboardingIntents = [
  ('love', Ic.heart, 'Love', 'Crushes, partners, heartbreak'),
  ('career', Ic.briefcase, 'Career', 'Work, money, big decisions'),
  ('growth', Ic.lotus, 'Growth', 'Confidence, habits, purpose'),
  ('health', Ic.leaf, 'Wellbeing', 'Energy, balance, rest'),
  ('spirituality', Ic.crystalBall, 'Spirit', 'Intuition, signs, meaning'),
];

class _OnboardingState extends ConsumerState<OnboardingScreen> {
  final _pc = PageController();
  int _page = 0;
  final Set<String> _intents = {};
  int? _picked; // which of the three face-down cards was tapped
  static const _count = 4;

  Future<void> _finish() async {
    final prefs = ref.read(prefsProvider);
    if (_intents.isNotEmpty) await prefs.setStringList(onboardingFocusKey, _intents.toList());
    await prefs.setBool('onboardingSeen', true);
    ref.read(authGateProvider).refresh();
  }

  void _next() {
    if (_page == _count - 1) {
      _finish();
      return;
    }
    FocusScope.of(context).unfocus();
    _pc.nextPage(duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
  }

  void _back() => _pc.previousPage(duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);

  String get _cta => switch (_page) {
        0 => 'Begin',
        1 => _intents.isEmpty ? 'Skip for now' : 'Continue',
        2 => _picked == null ? 'Pick a card to continue' : 'Continue',
        _ => 'Get started',
      };

  @override
  Widget build(BuildContext context) {
    final canContinue = !(_page == 2 && _picked == null);
    return Scaffold(
      body: CosmicBackground(
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(children: [
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _page == 0 ? 0 : 1,
                  child: IgnorePointer(ignoring: _page == 0, child: CircleIconButton(icon: Ic.left, tooltip: 'Back', onTap: _back)),
                ),
                const SizedBox(width: 12),
                Expanded(child: _Progress(page: _page, count: _count)),
                const SizedBox(width: 4),
                TextButton(onPressed: _finish, child: Text('Skip', style: AppType.ui(size: 14, weight: FontWeight.w600, color: AppColors.textSecondary))),
              ]),
            ),
            Expanded(
              child: PageView(
                controller: _pc,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  const _WelcomePage(),
                  _IntentPage(selected: _intents, onToggle: (id) => setState(() => _intents.contains(id) ? _intents.remove(id) : _intents.add(id))),
                  _FirstCardPage(picked: _picked, onPick: (i) => setState(() => _picked = i)),
                  const _FeaturesPage(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: GradientButton(key: const Key('onboardingNext'), label: _cta, icon: _page == _count - 1 ? Ic.sparkles : null, onPressed: canContinue ? _next : null),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 12),
              child: Text(disclaimer, textAlign: TextAlign.center, style: AppType.ui(size: 10.5, weight: FontWeight.w500, color: AppColors.textMuted)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.page, required this.count});
  final int page, count;
  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Step ${page + 1} of $count',
        child: Row(children: [
          for (var i = 0; i < count; i++)
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                height: 4,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: i <= page ? AppColors.cta : null,
                  color: i <= page ? null : AppColors.border,
                ),
              ),
            ),
        ]),
      );
}

/// Shared page layout: art on top, overline + serif heading + body, then optional content.
class _OnbPage extends StatelessWidget {
  const _OnbPage({required this.overline, required this.lead, required this.accent, required this.body, this.art, this.child});
  final String overline, lead, accent, body;
  final Widget? art, child;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight - 24),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (art != null) Center(child: art!.animate().fadeIn(duration: 500.ms).scale(begin: const Offset(0.94, 0.94), curve: Curves.easeOutCubic)),
              const SizedBox(height: 20),
              Text(overline.toUpperCase(), style: AppType.overline(color: AppColors.gold)).animate().fadeIn(delay: 80.ms, duration: 400.ms),
              const SizedBox(height: 8),
              GradientHeading(lead, accent, size: 34).animate().fadeIn(delay: 140.ms, duration: 450.ms).slideY(begin: 0.15, curve: Curves.easeOutCubic),
              const SizedBox(height: 10),
              Text(body, style: AppType.ui(size: 15, weight: FontWeight.w400, color: AppColors.textSecondary, height: 1.55)).animate().fadeIn(delay: 220.ms, duration: 450.ms),
              if (child != null) ...[const SizedBox(height: 22), child!],
            ]),
          ),
        ),
      );
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage();
  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return _OnbPage(
      overline: 'Welcome',
      lead: 'Meet',
      accent: 'Selene',
      body: 'Your night-sky guide. Ask the cards, check the stars, read your palm, and talk it through with a reader who listens.',
      art: SizedBox(
        height: (h * 0.36).clamp(200, 320),
        child: Stack(alignment: Alignment.center, children: [
          Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [AppColors.gold.withValues(alpha: 0.22), AppColors.primary.withValues(alpha: 0.10), Colors.transparent], stops: const [0, 0.55, 1]),
            ),
          ),
          Image.asset('assets/images/selene_cutout.webp', fit: BoxFit.contain, excludeFromSemantics: true)
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .moveY(begin: 0, end: -8, duration: 2600.ms, curve: Curves.easeInOut),
        ]),
      ),
      child: const Wrap(spacing: 8, runSpacing: 8, children: [
        Tag('Tarot', icon: Ic.cards, color: AppColors.gold),
        Tag('Horoscope', icon: Ic.moonStars, color: AppColors.glow),
        Tag('Palm reading', icon: Ic.hand, color: AppColors.magenta),
        Tag('AI readers', icon: Ic.chat, color: AppColors.head),
      ]),
    );
  }
}

class _IntentPage extends StatelessWidget {
  const _IntentPage({required this.selected, required this.onToggle});
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  @override
  Widget build(BuildContext context) => _OnbPage(
        overline: 'Make it yours',
        lead: 'What’s on your',
        accent: 'mind?',
        body: 'Pick as many as you like. Your readings will lean into what matters to you right now.',
        child: Column(children: [
          for (final (i, o) in onboardingIntents.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Semantics(
                button: true,
                selected: selected.contains(o.$1),
                child: GlowCard(
                  selected: selected.contains(o.$1),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  onTap: () => onToggle(o.$1),
                  child: Row(children: [
                    IconBadge(o.$2, color: selected.contains(o.$1) ? AppColors.gold : AppColors.glow, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(o.$3, style: AppType.ui(size: 15.5, weight: FontWeight.w700)),
                        Text(o.$4, style: AppType.ui(size: 12.5, weight: FontWeight.w400, color: AppColors.textSecondary)),
                      ]),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: selected.contains(o.$1)
                          ? const AppIcon(Ic.checkCircleFill, key: ValueKey('on'), color: AppColors.gold, size: 24)
                          : Container(
                              key: const ValueKey('off'),
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.borderStrong, width: 1.5)),
                            ),
                    ),
                  ]),
                ),
              ).animate().fadeIn(delay: (260 + i * 60).ms, duration: 350.ms).slideX(begin: 0.06, curve: Curves.easeOutCubic),
            ),
        ]),
      );
}

/// Three face-down cards; tapping one reveals a Major Arcana card with its keywords.
class _FirstCardPage extends ConsumerWidget {
  const _FirstCardPage({required this.picked, required this.onPick});
  final int? picked;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = (ref.watch(cardsProvider).value ?? const <TarotCard>[]).where((c) => c.isMajor).toList();
    final today = DateTime.now();
    final seed = today.year * 10000 + today.month * 100 + today.day;
    final card = cards.isEmpty ? null : cards[(seed + (picked ?? 0) * 7) % cards.length];
    final w = MediaQuery.of(context).size.width;
    final cw = ((w - 48 - 24) / 3).clamp(70.0, 108.0);
    return _OnbPage(
      overline: 'Try it now',
      lead: 'Draw your',
      accent: 'first card',
      body: picked == null ? 'Take a breath, think of today, and tap the card that calls to you.' : 'This is the energy around you today.',
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          for (var i = 0; i < 3; i++)
            Semantics(
              button: picked == null,
              label: picked == null ? 'Pick card ${i + 1}' : (i == picked ? card?.name : null),
              child: GestureDetector(
                onTap: picked == null && card != null ? () => onPick(i) : null,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 350),
                  opacity: picked == null || picked == i ? 1 : 0.25,
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutBack,
                    scale: picked == i ? 1.08 : 1,
                    child: TarotCardView(image: card?.image ?? 'assets/images/card_back.webp', faceUp: picked == i, width: cw, selected: picked == i),
                  ),
                ),
              ),
            ).animate().fadeIn(delay: (280 + i * 90).ms, duration: 400.ms).slideY(begin: 0.12, curve: Curves.easeOutCubic),
        ]),
        const SizedBox(height: 18),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: picked == null || card == null
              ? const SizedBox(height: 70, key: ValueKey('empty'))
              : GlowCard(
                  key: const ValueKey('revealed'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const AppIcon(Ic.sparklesFill, size: 16, color: AppColors.gold),
                      const SizedBox(width: 8),
                      Expanded(child: Text(card.name, style: AppType.display(size: 20, weight: FontWeight.w500, color: AppColors.gold))),
                    ]),
                    const SizedBox(height: 6),
                    Text(card.keywords.take(3).join(' · '), style: AppType.ui(size: 13, weight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(card.description, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.ui(size: 13, weight: FontWeight.w400, color: AppColors.textSecondary, height: 1.5)),
                  ]),
                ),
        ),
      ]),
    );
  }
}

class _FeaturesPage extends StatelessWidget {
  const _FeaturesPage();
  static const _rows = [
    ('assets/images/tarot_sun_star_moon.webp', 'Tarot readings', 'Ask anything, draw a spread, get a reading written for you.'),
    ('assets/images/zodiac_wheel.webp', 'Horoscope & moon', 'Daily guidance for your sign and a live moon calendar.'),
    ('assets/images/palm_aura.webp', 'Palm reading', 'Snap your palm and see your lines traced and explained.'),
    ('assets/images/readers_trio.webp', 'Six AI readers', 'Pick a voice that fits you and talk it through.'),
  ];
  @override
  Widget build(BuildContext context) => _OnbPage(
        overline: 'Everything in one place',
        lead: 'Your guide for',
        accent: 'every night',
        body: 'Free to start. No credit card needed.',
        child: Column(children: [
          for (final (i, r) in _rows.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GlowCard(
                padding: const EdgeInsets.all(10),
                child: Row(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.asset(r.$1, width: 58, height: 58, fit: BoxFit.cover, excludeFromSemantics: true)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r.$2, style: AppType.ui(size: 15, weight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(r.$3, style: AppType.ui(size: 12.5, weight: FontWeight.w400, color: AppColors.textSecondary, height: 1.4)),
                    ]),
                  ),
                ]),
              ),
            ).animate().fadeIn(delay: (260 + i * 70).ms, duration: 350.ms).slideY(begin: 0.1, curve: Curves.easeOutCubic),
          const SizedBox(height: 6),
          Row(children: [
            const AppIcon(Ic.shield, size: 16, color: AppColors.success),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Private by default: palm photos are deleted from our servers right after your reading.',
                  style: AppType.ui(size: 12, weight: FontWeight.w500, color: AppColors.textSecondary)),
            ),
          ]),
        ]),
      );
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInState();
}

class _SignInState extends State<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false, _create = false, _showPass = false;
  // Client-side brake on repeated failed sign-ins (Firebase also throttles server-side).
  int _failures = 0;
  DateTime? _lockedUntil;

  @override
  void initState() {
    super.initState();
    _pass.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } on FirebaseAuthException catch (e) {
      if (mounted) _snack(_authMessage(e));
    } catch (e) {
      if (mounted) _snack('Sign in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _authMessage(FirebaseAuthException e) => switch (e.code) {
        'invalid-email' => 'That email address looks invalid.',
        'weak-password' || 'password-does-not-meet-requirements' => 'Choose a stronger password (8+ characters with upper, lower, number and symbol).',
        // Same wording for "exists" and "wrong password" so the form can't be used to discover accounts.
        'email-already-in-use' => 'Could not create an account with that email. If it’s yours, sign in or reset your password.',
        'invalid-credential' || 'wrong-password' || 'user-not-found' || 'invalid-login-credentials' => 'Email or password is incorrect.',
        'too-many-requests' => 'Too many attempts. Please wait a few minutes and try again.',
        'user-disabled' => 'This account has been disabled.',
        'operation-not-allowed' => 'This sign-in method is not enabled yet.',
        'account-exists-with-different-credential' => 'This email already has an account. Sign in with your email and password.',
        'network-request-failed' => "You're offline. Check your connection and try again.",
        _ => 'Sign in failed. Please try again.',
      };

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_lockedUntil != null && DateTime.now().isBefore(_lockedUntil!)) {
      _snack('Too many attempts. Try again in ${_lockedUntil!.difference(DateTime.now()).inSeconds + 1}s.');
      return;
    }
    if (!(_form.currentState?.validate() ?? false)) return;
    final email = _email.text.trim(), pass = _pass.text;
    final auth = FirebaseAuth.instance;
    await _run(() async {
      try {
        if (_create) {
          final cred = await auth.createUserWithEmailAndPassword(email: email, password: pass);
          // The router sends unverified email accounts to the "Verify your email" screen.
          await cred.user?.sendEmailVerification();
        } else {
          final cred = await auth.signInWithEmailAndPassword(email: email, password: pass);
          final u = cred.user;
          if (u != null && userNeedsEmailVerification(u)) {
            await u.sendEmailVerification().catchError((Object _) {}); // throttled by Firebase; screen offers resend
          }
        }
        _failures = 0;
        // Let Android offer to save the just-used credentials.
        TextInput.finishAutofillContext();
      } on FirebaseAuthException catch (e) {
        if (!_create && const ['invalid-credential', 'wrong-password', 'user-not-found', 'invalid-login-credentials'].contains(e.code)) {
          _failures++;
          if (_failures >= 5) {
            _lockedUntil = DateTime.now().add(Duration(seconds: 30 * (_failures - 4)));
          }
        }
        rethrow;
      }
    });
  }

  Future<void> _resetPassword() => _run(() async {
        final err = Validators.email(_email.text);
        if (err != null) {
          _snack('Enter your email above first.');
          return;
        }
        try {
          await FirebaseAuth.instance.sendPasswordResetEmail(email: _email.text.trim());
        } on FirebaseAuthException catch (e) {
          if (e.code == 'too-many-requests' || e.code == 'network-request-failed') rethrow;
        }
        // Same message whether or not the account exists (don't reveal registered emails).
        if (mounted) _snack('If an account exists for that email, a reset link is on its way.');
      });

  InputDecoration _field(String hint, String icon, {Widget? suffix}) => InputDecoration(
        hintText: hint,
        counterText: '',
        prefixIcon: Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: AppIcon(icon, size: 20, color: AppColors.textMuted)),
        prefixIconConstraints: const BoxConstraints(minWidth: 44),
        suffixIcon: suffix,
        errorMaxLines: 3,
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        body: CosmicBackground(
          child: SafeArea(
            child: AutofillGroup(
              child: Form(
              key: _form,
              child: ListView(padding: const EdgeInsets.all(24), keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, children: [
              const SizedBox(height: 4),
              Center(child: Image.asset('assets/images/selene_cutout.webp', height: 190, excludeFromSemantics: true).animate().fadeIn(duration: 500.ms)),
              const SizedBox(height: 12),
              Center(child: Text(_create ? 'CREATE YOUR ACCOUNT' : 'ONE LAST STEP', style: AppType.overline(color: AppColors.gold))),
              const SizedBox(height: 6),
              Center(child: GradientHeading(_create ? 'Join' : 'Save your', _create ? 'Selene' : 'readings', size: 32, textAlign: TextAlign.center)),
              const SizedBox(height: 8),
              Text('Sign in so your readings, chats and Premium follow you to any device.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 24),
              _GoogleButton(
                label: _create ? 'Sign up with Google' : 'Continue with Google',
                onPressed: _busy ? null : () => _run(() => GoogleAuth.signIn().then((_) {})),
              ),
              const SizedBox(height: 12),
              Row(children: [const Expanded(child: Divider()), Padding(padding: const EdgeInsets.all(10), child: Text('or use email', style: AppType.ui(size: 12, color: AppColors.textMuted))), const Expanded(child: Divider())]),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                inputFormatters: Validators.emailFormatters,
                maxLength: Validators.emailMax,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: Validators.email,
                decoration: _field('Email', Ic.mail),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('password'),
                controller: _pass,
                obscureText: !_showPass,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: _create ? TextInputAction.next : TextInputAction.done,
                autofillHints: [_create ? AutofillHints.newPassword : AutofillHints.password],
                inputFormatters: Validators.passwordFormatters,
                maxLength: Validators.passwordMax,
                autovalidateMode: _create ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
                validator: _create ? Validators.newPassword : Validators.existingPassword,
                onFieldSubmitted: (_) => _create ? null : _submit(),
                decoration: _field(
                  'Password',
                  Ic.lock,
                  suffix: IconButton(
                    tooltip: _showPass ? 'Hide password' : 'Show password',
                    onPressed: () => setState(() => _showPass = !_showPass),
                    icon: AppIcon(_showPass ? Ic.eyeClose : Ic.eye, size: 20, color: AppColors.textMuted),
                  ),
                ),
              ),
              if (_create) ...[
                const SizedBox(height: 10),
                _PasswordChecklist(password: _pass.text),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('confirmPassword'),
                  controller: _confirm,
                  obscureText: !_showPass,
                  autocorrect: false,
                  enableSuggestions: false,
                  inputFormatters: Validators.passwordFormatters,
                  maxLength: Validators.passwordMax,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: (v) => v != _pass.text ? 'Passwords don’t match.' : null,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: _field('Confirm password', Ic.lock),
                ),
              ],
              const SizedBox(height: 16),
              GradientButton(key: const Key('submitAuth'), label: _create ? 'Create account' : 'Sign in', icon: Ic.door, loading: _busy, onPressed: _submit),
              TextButton(
                onPressed: () => setState(() {
                  _create = !_create;
                  _confirm.clear();
                  _form.currentState?.reset();
                }),
                child: Text(_create ? 'Already have an account? Sign in' : 'New here? Create an account'),
              ),
              if (!_create)
                TextButton(
                  onPressed: _busy ? null : _resetPassword,
                  child: Text('Forgot password?', style: AppType.ui(size: 13.5, weight: FontWeight.w600, color: AppColors.textSecondary)),
                ),
              const SizedBox(height: 4),
              Row(children: [const Expanded(child: Divider()), Padding(padding: const EdgeInsets.all(10), child: Text('or', style: AppType.ui(size: 12, color: AppColors.textMuted))), const Expanded(child: Divider())]),
              const SizedBox(height: 4),
              OutlinePillButton(
                label: 'Continue as Guest',
                icon: Ic.user,
                onPressed: _busy ? null : () => _run(() => FirebaseAuth.instance.signInAnonymously().then((_) {})),
              ),
              const SizedBox(height: 20),
              Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('By continuing you agree to our', style: AppType.ui(size: 11.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                TextButton(onPressed: () => openLegal(context, LegalLinks.terms), style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: const Size(0, 32)), child: Text('Terms', style: AppType.ui(size: 11.5, weight: FontWeight.w700, color: AppColors.glow))),
                Text('and', style: AppType.ui(size: 11.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                TextButton(onPressed: () => openLegal(context, LegalLinks.privacy), style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: const Size(0, 32)), child: Text('Privacy Policy', style: AppType.ui(size: 11.5, weight: FontWeight.w700, color: AppColors.glow))),
              ]),
              const SizedBox(height: 4),
              Text(disclaimer, textAlign: TextAlign.center, style: AppType.ui(size: 11, weight: FontWeight.w500, color: AppColors.textMuted, height: 1.45)),
            ]),
            ),
            ),
          ),
        ),
      );
}

/// Live checklist of the password rules shown while creating an account.
class _PasswordChecklist extends StatelessWidget {
  const _PasswordChecklist({required this.password});
  final String password;
  @override
  Widget build(BuildContext context) {
    final checks = Validators.passwordChecks(password);
    final met = checks.where((c) => c.$2).length;
    final color = met <= 2 ? AppColors.error : met <= 4 ? AppColors.warning : AppColors.success;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        for (var i = 0; i < checks.length; i++)
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              height: 4,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: i < met ? color : AppColors.border),
            ),
          ),
      ]),
      const SizedBox(height: 8),
      for (final c in checks)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            AppIcon(c.$2 ? Ic.checkCircleFill : Ic.checkCircle, size: 15, color: c.$2 ? AppColors.success : AppColors.textMuted),
            const SizedBox(width: 8),
            Text(c.$1, style: AppType.ui(size: 12.5, weight: FontWeight.w500, color: c.$2 ? AppColors.text : AppColors.textMuted)),
          ]),
        ),
    ]);
  }
}

/// Shown to email/password accounts until they confirm their address. Firestore rules and the
/// Cloud Functions reject unverified email accounts too, so this can't be bypassed by the app.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});
  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailState();
}

class _VerifyEmailState extends ConsumerState<VerifyEmailScreen> with WidgetsBindingObserver {
  Timer? _poll, _tick;
  int _cooldown = 0;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Check quietly every 5 s so the app continues on its own once the link is tapped.
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _check(silent: true));
    _startCooldown(45); // a verification email was just sent at sign-up
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _check(silent: true); // back from the mail app
  }

  void _startCooldown(int s) {
    _tick?.cancel();
    setState(() => _cooldown = s);
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> _check({bool silent = false}) async {
    if (_checking) return;
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    setState(() => _checking = !silent);
    try {
      await u.reload();
      final fresh = FirebaseAuth.instance.currentUser;
      if (fresh?.emailVerified == true) {
        await fresh!.getIdToken(true); // new token carries email_verified=true for rules/functions
        ref.read(authGateProvider).refresh();
      } else if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not verified yet. Tap the link in the email, then try again.')));
      }
    } catch (_) {
      if (!silent && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't check right now. Please try again.")));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _resend() async {
    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      _startCooldown(60);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verification email sent. Check your inbox and spam folder.')));
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.code == 'too-many-requests' ? 'Too many requests. Please wait a few minutes.' : 'Could not send the email. Please try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? 'your email';
    return Scaffold(
      body: CosmicBackground(
        child: SafeArea(
          child: ListView(padding: const EdgeInsets.all(24), children: [
            const SizedBox(height: 32),
            const Center(child: IconBadge(Ic.mail, color: AppColors.gold, size: 84, circle: true))
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .moveY(begin: 0, end: -6, duration: 1800.ms, curve: Curves.easeInOut),
            const SizedBox(height: 24),
            Center(child: Text('ONE QUICK CHECK', style: AppType.overline(color: AppColors.gold))),
            const SizedBox(height: 6),
            const Center(child: GradientHeading('Verify your', 'email', size: 32, textAlign: TextAlign.center)),
            const SizedBox(height: 12),
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'We sent a link to '),
                TextSpan(text: email, style: AppType.ui(size: 14.5, weight: FontWeight.w700, color: AppColors.text)),
                const TextSpan(text: '. Tap it to confirm it’s you, then come back here. We’ll continue automatically.'),
              ]),
              textAlign: TextAlign.center,
              style: AppType.ui(size: 14.5, weight: FontWeight.w400, color: AppColors.textSecondary, height: 1.55),
            ),
            const SizedBox(height: 28),
            GradientButton(key: const Key('verifiedButton'), label: 'I’ve verified my email', icon: Ic.checkCircle, loading: _checking, onPressed: () => _check()),
            const SizedBox(height: 12),
            OutlinePillButton(
              label: _cooldown > 0 ? 'Resend email in ${_cooldown}s' : 'Resend email',
              icon: Ic.send,
              onPressed: _cooldown > 0 ? null : _resend,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
              },
              child: const Text('Use a different account'),
            ),
            const SizedBox(height: 16),
            Row(children: [
              const AppIcon(Ic.info, size: 16, color: AppColors.textMuted),
              const SizedBox(width: 8),
              Expanded(child: Text('Can’t find it? Check your spam or promotions folder.', style: AppType.ui(size: 12, weight: FontWeight.w500, color: AppColors.textMuted))),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Profile setup: name, DOB → zodiac, focus areas, reader, language, consent.
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key, this.editing = false});
  final bool editing;
  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupState();
}

const focusOptions = [('love', 'Love', Ic.heart), ('career', 'Career', Ic.briefcase), ('growth', 'Growth', Ic.lotus), ('health', 'Wellbeing', Ic.leaf), ('spirituality', 'Spirit', Ic.crystalBall)];

class _ProfileSetupState extends ConsumerState<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scroll = ScrollController();
  // Anchors for scroll-to-first-error.
  final _nameKey = GlobalKey();
  final _dobKey = GlobalKey();
  final _timeKey = GlobalKey();
  final _placeKey = GlobalKey();
  final _consentKey = GlobalKey();
  final _name = TextEditingController();
  final _place = TextEditingController();
  DateTime? _dob;
  TimeOfDay? _birthTime;
  bool _timeUnknown = false;
  // Inline validation messages for the non-text-field inputs.
  String? _dobErr, _timeErr;
  bool _consentErr = false;
  final Set<String> _focus = {'love', 'career'};
  String _reader = 'selene', _lang = 'en';
  bool _consent = false, _busy = false, _loaded = false;

  @override
  void dispose() {
    _name.dispose();
    _place.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _load() {
    final u = ref.read(userDocProvider).value;
    if (_loaded || u == null) return;
    _loaded = true;
    final picked = ref.read(prefsProvider).getStringList(onboardingFocusKey);
    if (picked != null && picked.isNotEmpty) _focus..clear()..addAll(picked);
    // Google display names can contain digits/symbols; keep only what the name rules allow.
    final raw = u.displayName.isNotEmpty ? u.displayName : (FirebaseAuth.instance.currentUser?.displayName ?? '');
    _name.text = Validators.sanitizeName(raw);
    if (u.dob != null) _dob = DateTime.tryParse(u.dob!);
    _birthTime = parseBirthTime(u.birthTime);
    // An existing profile without a time means the user said "I don't know".
    _timeUnknown = u.profileComplete && _birthTime == null && u.j.containsKey('birthTime');
    _place.text = u.birthPlace ?? '';
    if (u.focusAreas.isNotEmpty) _focus..clear()..addAll(u.focusAreas);
    _reader = u.preferredReaderId;
    _lang = u.language;
    _consent = u.profileComplete;
  }

  int _age(DateTime d) {
    final n = DateTime.now();
    return n.year - d.year - ((n.month < d.month || (n.month == d.month && n.day < d.day)) ? 1 : 0);
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final name = _name.text.trim();
    final place = _place.text.trim();
    final nameError = Validators.name(name);
    final placeError = Validators.place(place);
    // Inline messages for the picker/checkbox inputs (text fields validate through the Form).
    setState(() {
      _dobErr = _dob == null
          ? 'Please add your date of birth.'
          : _age(_dob!) < 13
              ? 'Selene is for users aged 13 and over.'
              : null;
      _timeErr = (_birthTime == null && !_timeUnknown) ? "Add your birth time, or tick \"I don't know\"." : null;
      _consentErr = !_consent;
    });
    // Force the text-field validators to surface their messages inline.
    _formKey.currentState?.validate();

    // Scroll to the first field with a problem so the user always sees what to fix.
    final firstBad = nameError != null
        ? _nameKey
        : _dobErr != null
            ? _dobKey
            : _timeErr != null
                ? _timeKey
                : placeError != null
                    ? _placeKey
                    : _consentErr
                        ? _consentKey
                        : null;
    if (firstBad != null) {
      final ctx = firstBad.currentContext;
      if (ctx != null) {
        await Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic, alignment: 0.1);
      }
      return;
    }

    setState(() => _busy = true);
    try {
      await userRef().set({
        'displayName': name,
        'dob': DateFormat('yyyy-MM-dd').format(_dob!),
        'birthTime': _timeUnknown || _birthTime == null ? null : formatBirthTime(_birthTime!),
        'birthPlace': place,
        'zodiac': sunSignFor(_dob!).id,
        'focusAreas': _focus.toList(),
        'preferredReaderId': _reader,
        'language': _lang,
        'profileComplete': true,
        'email': FirebaseAuth.instance.currentUser?.email,
        'updatedAt': FieldValue.serverTimestamp(),
        if (!widget.editing) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await FirebaseAuth.instance.currentUser?.updateDisplayName(name);
      if (widget.editing && mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save your profile. Check your connection and try again.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    _load();
    final readers = ref.watch(readersProvider).value ?? [];
    final sign = _dob == null ? null : sunSignFor(_dob!);
    return Scaffold(
      body: CosmicBackground(
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(controller: _scroll, padding: const EdgeInsets.all(20), keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, children: [
            Row(children: [
              if (widget.editing) CircleIconButton(icon: Ic.left, tooltip: 'Back', onTap: () => Navigator.of(context).pop()),
              if (widget.editing) const SizedBox(width: 12),
              Expanded(child: GradientHeading(widget.editing ? 'Edit' : 'Tell us about', widget.editing ? 'Profile' : 'you', size: 30)),
            ]),
            const SizedBox(height: 8),
            Text(widget.editing ? 'Update what your readers know about you.' : 'Your birth date, time and place shape your sign and make every reading personal.', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 20),
            KeyedSubtree(key: _nameKey, child: _label('Your name')),
            TextFormField(
              key: const Key('nameField'),
              controller: _name,
              textCapitalization: TextCapitalization.words,
              autocorrect: false,
              inputFormatters: Validators.nameFormatters,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: Validators.name,
              decoration: const InputDecoration(hintText: 'e.g. Priya Sharma', helperText: 'Letters and spaces only'),
            ),
            const SizedBox(height: 16),
            KeyedSubtree(key: _dobKey, child: _label('Date of birth')),
            GlowCard(
              selected: _dobErr != null,
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _dob ?? DateTime(2000, 1, 1),
                  firstDate: DateTime(1920),
                  lastDate: DateTime.now(),
                );
                if (d != null) {
                  setState(() {
                    _dob = d;
                    _dobErr = null;
                  });
                }
              },
              child: Row(children: [
                const IconBadge(Ic.cake, color: AppColors.gold, size: 36),
                const SizedBox(width: 12),
                Expanded(child: Text(_dob == null ? 'Select your birthday' : DateFormat.yMMMMd().format(_dob!), style: AppType.ui(size: 15, weight: FontWeight.w500, color: _dob == null ? AppColors.textMuted : AppColors.text))),
                if (sign != null) ...[
                  Image.asset(sign.image, width: 36),
                  const SizedBox(width: 6),
                  Text(sign.name, style: AppType.ui(size: 14, weight: FontWeight.w700, color: AppColors.gold)),
                ],
              ]),
            ),
            if (_dobErr != null) _fieldError(_dobErr!),
            const SizedBox(height: 16),
            KeyedSubtree(key: _timeKey, child: _label('Time of birth')),
            BirthTimeField(
              time: _birthTime,
              unknown: _timeUnknown,
              onTime: (t) => setState(() {
                _birthTime = t;
                _timeErr = null;
              }),
              onUnknown: (v) => setState(() {
                _timeUnknown = v;
                if (v) {
                  _timeErr = null;
                }
              }),
            ),
            if (_timeErr != null) _fieldError(_timeErr!),
            const SizedBox(height: 8),
            KeyedSubtree(key: _placeKey, child: _label('Place of birth')),
            BirthPlaceField(controller: _place, fieldKey: const Key('birthPlaceField')),
            const SizedBox(height: 16),
            _label('What would you like guidance on?'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final f in focusOptions)
                PillChip(
                  label: f.$2,
                  icon: f.$3,
                  selected: _focus.contains(f.$1),
                  onTap: () => setState(() => _focus.contains(f.$1) ? _focus.remove(f.$1) : _focus.add(f.$1)),
                ),
            ]),
            const SizedBox(height: 16),
            _label('Your favourite reader'),
            SizedBox(
              height: 96,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final r in readers.where((r) => !r.premium))
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: GestureDetector(
                      onTap: () => setState(() => _reader = r.id),
                      child: Column(children: [
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(shape: BoxShape.circle, gradient: _reader == r.id ? AppColors.cta : null, border: _reader == r.id ? null : Border.all(color: AppColors.border)),
                          child: CircleAvatar(radius: 30, backgroundImage: AssetImage(r.image)),
                        ),
                        const SizedBox(height: 4),
                        Text(r.name, style: TextStyle(fontSize: 12, color: _reader == r.id ? Colors.white : AppColors.textSecondary)),
                      ]),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 16),
            _label('Reading language'),
            Row(children: [
              PillChip(label: 'English', selected: _lang == 'en', onTap: () => setState(() => _lang = 'en')),
              const SizedBox(width: 8),
              PillChip(label: 'हिन्दी', selected: _lang == 'hi', onTap: () => setState(() => _lang = 'hi')),
            ]),
            const SizedBox(height: 16),
            KeyedSubtree(
              key: _consentKey,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CheckboxListTile(
                  value: _consent,
                  onChanged: (v) => setState(() {
                    _consent = v ?? false;
                    if (_consent) {
                      _consentErr = false;
                    }
                  }),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'I am 13 or older and agree that my photos and questions are processed by AI (Google Gemini) to create readings. '
                    'Readings are for entertainment only.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.45),
                  ),
                ),
                if (_consentErr) _fieldError('Please accept the terms to continue.'),
              ]),
            ),
            const SizedBox(height: 12),
            GradientButton(label: widget.editing ? 'Save' : 'Continue', loading: _busy, onPressed: _save),
          ]),
          ),
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(t.toUpperCase(), style: AppType.overline(color: AppColors.textSecondary)));

  Widget _fieldError(String msg) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const AppIcon(Ic.info, size: 14, color: AppColors.error),
          const SizedBox(width: 6),
          Expanded(child: Text(msg, style: AppType.ui(size: 12, weight: FontWeight.w500, color: AppColors.error))),
        ]),
      );
}
