import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme.dart';
import 'core/widgets.dart';
import 'features/auth.dart';
import 'features/cards.dart';
import 'features/chat.dart';
import 'features/history.dart';
import 'features/home.dart';
import 'features/horoscope.dart';
import 'features/palm.dart';
import 'features/palm_results.dart';
import 'features/paywall.dart';
import 'features/profile.dart';
import 'features/spreads.dart';
import 'features/tarot.dart';

final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

/// Listens to auth + user profile so the router can redirect.
class AuthGate extends ChangeNotifier {
  AuthGate(this.prefs) {
    _authSub = FirebaseAuth.instance.authStateChanges().listen((u) {
      _docSub?.cancel();
      _docSub = null;
      user = u;
      needsEmailVerification = u != null && userNeedsEmailVerification(u);
      if (u == null) {
        profileComplete = false;
        ready = true;
        notifyListeners();
      } else if (needsEmailVerification) {
        // Firestore rules refuse unverified email accounts, so don't subscribe to the profile yet.
        profileComplete = false;
        ready = true;
        notifyListeners();
      } else {
        _watchProfile(u);
      }
    });
    // emailVerified only changes after reload(), which fires userChanges (not authStateChanges).
    _verifySub = FirebaseAuth.instance.userChanges().listen((u) {
      if (u == null || !needsEmailVerification || userNeedsEmailVerification(u)) return;
      needsEmailVerification = false;
      ready = false; // splash while the profile loads, instead of flashing the setup screen
      notifyListeners();
      _watchProfile(u);
    });
  }

  void _watchProfile(User u) {
    _docSub?.cancel();
    var first = true;
    _docSub = FirebaseFirestore.instance.doc('users/${u.uid}').snapshots().listen((s) {
      // Only refresh the router when something routing-relevant changed. The user doc is also
      // updated by the backend (usage quotas) at the start of every tarot/palm reading, and a
      // router refresh rebuilds pushed routes without their `extra` (-> blank screen).
      final complete = s.data()?['profileComplete'] == true;
      if (!first && complete == profileComplete) return;
      first = false;
      profileComplete = complete;
      ready = true;
      notifyListeners();
    }, onError: (_) {
      if (!first) return;
      first = false;
      ready = true;
      notifyListeners();
    });
  }

  final SharedPreferences prefs;
  late final StreamSubscription<User?> _authSub, _verifySub;
  StreamSubscription<DocumentSnapshot>? _docSub;
  User? user;
  bool profileComplete = false;
  bool ready = false;
  bool needsEmailVerification = false;
  bool get onboardingSeen => prefs.getBool('onboardingSeen') ?? false;
  void refresh() => notifyListeners();

  /// One-shot route to reopen after the OS killed the app (e.g. while the camera was open).
  String? takeResumeRoute() {
    final r = prefs.getString(resumeRouteKey);
    if (r == null) return null;
    prefs.remove(resumeRouteKey);
    return const ['/palm'].contains(r) ? r : null;
  }

  // Web only: top-level pages that are safe to open directly (no `extra`, closable when root).
  static const _deepLinkable = ['/home', '/tarot', '/horoscope', '/palm', '/profile', '/paywall'];
  String? _deepLink;

  void rememberDeepLink(Uri uri) {
    if (!kIsWeb || _deepLink != null || !_deepLinkable.contains(uri.path)) return;
    _deepLink = uri.toString();
  }

  String? takeDeepLink() {
    final l = _deepLink;
    _deepLink = null;
    return l;
  }

  @override
  void dispose() {
    _authSub.cancel();
    _verifySub.cancel();
    _docSub?.cancel();
    super.dispose();
  }
}

/// Email/password accounts must confirm their address (Google and guest accounts are exempt).
/// Mirrors `needsEmailVerification` in functions/src/quota.ts and `verified()` in firestore.rules.
bool userNeedsEmailVerification(User u) =>
    !u.isAnonymous && !u.emailVerified && u.providerData.any((p) => p.providerId == 'password');

// Last request passed to the extra-based routes (see the route definitions below).
TarotRequest? _lastTarot;
PalmRequest? _lastPalm;

final authGateProvider = Provider<AuthGate>((ref) {
  final g = AuthGate(ref.watch(prefsProvider));
  ref.onDispose(g.dispose);
  return g;
});

final routerProvider = Provider<GoRouter>((ref) {
  final gate = ref.watch(authGateProvider);
  return GoRouter(
    initialLocation: '/home',
    refreshListenable: gate,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      const gateRoutes = ['/splash', '/onboarding', '/signin', '/verify', '/setup'];
      // Web: a page load / return from checkout starts at a real URL; keep it through the splash.
      if (!gateRoutes.contains(loc)) gate.rememberDeepLink(state.uri);
      if (!gate.ready) return loc == '/splash' ? null : '/splash';
      if (!gate.onboardingSeen) return loc == '/onboarding' ? null : '/onboarding';
      if (gate.user == null) return loc == '/signin' ? null : '/signin';
      if (gate.needsEmailVerification) return loc == '/verify' ? null : '/verify';
      if (!gate.profileComplete) return loc == '/setup' ? null : '/setup';
      if (gateRoutes.contains(loc)) return gate.takeResumeRoute() ?? gate.takeDeepLink() ?? '/home';
      gate.takeDeepLink(); // already there
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: '/signin', builder: (_, _) => const SignInScreen()),
      GoRoute(path: '/verify', builder: (_, _) => const VerifyEmailScreen()),
      GoRoute(path: '/setup', builder: (_, _) => const ProfileSetupScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => MainShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, _) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/tarot', builder: (_, _) => const TarotReadingScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/horoscope', builder: (_, _) => const HoroscopeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/palm', builder: (_, _) => const PalmHomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen())]),
        ],
      ),
      // extra is lost if Android kills and restores the app (-> redirect back), and go_router also
      // rebuilds pushed routes with a null extra on refreshListenable ticks, so remember the last one.
      GoRoute(
        path: '/tarot/draw',
        redirect: (_, s) => (s.extra is TarotRequest || _lastTarot != null) ? null : '/tarot',
        builder: (_, s) => CardDrawScreen(request: _lastTarot = (s.extra as TarotRequest?) ?? _lastTarot!),
      ),
      GoRoute(path: '/tarot/result/:id', builder: (_, s) => TarotResultScreen(readingId: s.pathParameters['id']!)),
      GoRoute(path: '/spreads', builder: (_, _) => const SpreadsScreen()),
      GoRoute(path: '/spreads/create', builder: (_, _) => const CreateSpreadScreen()),
      GoRoute(path: '/cards', builder: (_, s) => CardMeaningsScreen(initialCardId: s.uri.queryParameters['card'], collectionOnly: s.uri.queryParameters['collection'] == '1')),
      GoRoute(path: '/cards/:id', builder: (_, s) => CardDetailScreen(cardId: s.pathParameters['id']!)),
      GoRoute(path: '/readers', builder: (_, _) => const ReadersScreen()),
      GoRoute(
        path: '/chat/:readerId',
        builder: (_, s) => ChatScreen(readerId: s.pathParameters['readerId']!, chatId: s.uri.queryParameters['chat'], initialText: s.uri.queryParameters['q'], tarotReadingId: s.uri.queryParameters['reading']),
      ),
      GoRoute(
        path: '/palm/analyze',
        redirect: (_, s) => (s.extra is PalmRequest || _lastPalm != null) ? null : '/palm',
        builder: (_, s) => PalmAnalyzingScreen(request: _lastPalm = (s.extra as PalmRequest?) ?? _lastPalm!),
      ),
      GoRoute(path: '/palm/result/:id', builder: (_, s) => PalmResultScreen(readingId: s.pathParameters['id']!, initialTab: int.tryParse(s.uri.queryParameters['tab'] ?? '') ?? 0)),
      GoRoute(path: '/palm/result/:id/:section', builder: (_, s) => PalmSectionScreen(readingId: s.pathParameters['id']!, section: s.pathParameters['section']!)),
      GoRoute(path: '/palm/share/:id', builder: (_, s) => PalmShareScreen(readingId: s.pathParameters['id']!)),
      GoRoute(path: '/readings', builder: (_, s) => MyReadingsScreen(initialFilter: s.uri.queryParameters['type'])),
      GoRoute(path: '/paywall', pageBuilder: (_, s) => MaterialPage(fullscreenDialog: true, child: PaywallScreen(checkoutReturn: s.uri.queryParameters['checkout'] == 'return'))),
    ],
  );
});

class SeleneApp extends ConsumerWidget {
  const SeleneApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
        title: 'Selene',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        routerConfig: ref.watch(routerProvider),
        // Respect the user's font size, but cap it so the art-heavy layouts stay usable.
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 0.85, maxScaleFactor: 1.3)),
            child: child!,
          );
        },
      );
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: CosmicBackground(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(30), boxShadow: [BoxShadow(color: AppColors.gold.withValues(alpha: 0.18), blurRadius: 40)]),
                child: ClipRRect(borderRadius: BorderRadius.circular(30), child: Image.asset('assets/images/app_icon.webp', width: 112)),
              ),
              const SizedBox(height: 20),
              Text('Selene', style: AppType.display(size: 34, weight: FontWeight.w500)),
              const SizedBox(height: 6),
              Text('YOUR NIGHT-SKY GUIDE', style: AppType.overline(color: AppColors.gold)),
            ]),
          ),
        ),
      );
}

/// Bottom navigation shell: Home · Tarot · Horoscope · Palm · Profile.
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  static const _items = [
    (Ic.homeFill, Ic.home, 'Home'),
    (Ic.cardsFill, Ic.cards, 'Tarot'),
    (Ic.moonStarsFill, Ic.moonStars, 'Stars'),
    (Ic.handFill, Ic.hand, 'Palm'),
    (Ic.userFill, Ic.user, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) => PopScope(
        // Android system back on a secondary tab returns to Home first; the app only exits
        // when back is pressed from the Home tab (canPop lets the root route handle it).
        canPop: shell.currentIndex == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) shell.goBranch(0);
        },
        child: Scaffold(
        extendBody: true,
        body: CosmicBackground(child: shell),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: Container(
            height: 68,
            decoration: BoxDecoration(
              color: const Color(0xF2100E24),
              borderRadius: BorderRadius.circular(AppRadius.nav),
              border: Border.all(color: AppColors.border),
              boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 24, offset: Offset(0, 8))],
            ),
            child: Row(children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: Semantics(
                    selected: shell.currentIndex == i,
                    button: true,
                    label: _items[i].$3,
                    excludeSemantics: true,
                    child: InkResponse(
                      onTap: () => shell.goBranch(i, initialLocation: i == shell.currentIndex),
                      child: _NavItem(icon: shell.currentIndex == i ? _items[i].$1 : _items[i].$2, label: _items[i].$3, selected: shell.currentIndex == i),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
      );
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.selected});
  final String icon, label;
  final bool selected;
  @override
  Widget build(BuildContext context) => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(color: selected ? AppColors.gold.withValues(alpha: 0.14) : Colors.transparent, borderRadius: BorderRadius.circular(999)),
          child: AppIcon(icon, size: 23, color: selected ? AppColors.gold : AppColors.textMuted),
        ),
        const SizedBox(height: 3),
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppType.ui(size: 11, weight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? AppColors.text : AppColors.textMuted)),
      ]);
}

/// Standard secondary screen scaffold (no bottom nav).
class SubPage extends StatelessWidget {
  const SubPage({super.key, required this.child, this.bottom});
  final Widget child;
  final Widget? bottom;
  @override
  Widget build(BuildContext context) => Scaffold(body: CosmicBackground(child: child), bottomNavigationBar: bottom);
}
