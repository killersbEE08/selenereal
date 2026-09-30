import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:selene/app.dart';
import 'package:selene/core/astro.dart';
import 'package:selene/core/theme.dart';
import 'package:selene/data/api.dart';
import 'package:selene/data/models.dart';
import 'package:selene/features/auth.dart';
import 'package:selene/features/horoscope.dart';
import 'package:selene/features/paywall.dart';
import 'package:selene/features/spreads.dart';
import 'package:selene/features/tarot.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AuthGate without Firebase listeners (onboarding only calls refresh()).
class _FakeGate extends ChangeNotifier implements AuthGate {
  _FakeGate(this.prefs);
  @override
  final SharedPreferences prefs;
  @override
  void refresh() => notifyListeners();
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Map<String, dynamic> _reading(int n) {
  final labels = ['Past', 'Present', 'Future', 'Obstacle', 'Advice'];
  final ids = ['major_19', 'major_00', 'cups_01', 'swords_10', 'wands_05'];
  return {
    'readingId': 'r1',
    'question': 'What does my future look like in career and love this year?',
    'topic': 'career',
    'spreadName': 'Three Card Spread',
    'aiEnabled': true,
    'readerId': 'selene',
    'safety': false,
    'safetyMessage': null,
    'cards': [
      for (var i = 0; i < n; i++) {'cardId': ids[i], 'reversed': i == 1, 'position': i, 'positionLabel': labels[i], 'positionMeaning': 'meaning'},
    ],
    'interpretation': {
      'title': 'A Bright and Hopeful Turn Toward Something Entirely New in Your Life',
      'cards': [
        for (var i = 0; i < n; i++) {'position_index': i, 'card_id': ids[i], 'headline': 'Joy and clarity ' * 3, 'interpretation': 'Long interpretation text. ' * 20},
      ],
      'synthesis': 'Synthesis ' * 60,
      'yes_no_leaning': 'yes with some patience and gentle care',
      'advice': ['Advice one ' * 8, 'Advice two ' * 8, 'Advice three ' * 8],
      'affirmation': 'I welcome the light.',
      'follow_up_questions': ['What should I focus on next month at work?', 'How do I open my heart again?'],
    },
  };
}

final _overrides = [
  authStateProvider.overrideWith((ref) => Stream.value(null)),
  userDocProvider.overrideWith((ref) => Stream.value(null)),
  isPremiumProvider.overrideWith((ref) => true),
];

Future<void> _phone(WidgetTester t, {double textScale = 1.0}) async {
  t.view.physicalSize = const Size(1080, 2340);
  t.view.devicePixelRatio = 2.75;
  t.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  final spreads = (jsonDecode(File('assets/json/spreads.json').readAsStringSync()) as List).cast<Map<String, dynamic>>().map(Spread.new).toList();

  for (final scale in [1.0, 1.3]) {
    testWidgets('three card draw -> reveal -> result (textScale $scale)', (t) async {
      await _phone(t, textScale: scale);
      final spread = spreads.firstWhere((s) => s.id == 'three_card');
      final reading = _reading(3);
      final router = GoRouter(initialLocation: '/draw', routes: [
        GoRoute(path: '/tarot', builder: (_, _) => const Scaffold()),
        GoRoute(path: '/draw', builder: (_, _) => CardDrawScreen(request: TarotRequest(question: reading['question'] as String, topic: 'career', spread: spread, aiEnabled: true))),
        GoRoute(path: '/tarot/result/:id', builder: (_, s) => TarotResultScreen(readingId: s.pathParameters['id']!)),
      ]);
      await t.pumpWidget(ProviderScope(
        overrides: [
          ..._overrides,
          startTarotProvider.overrideWithValue(({required question, required topic, spreadId, customSpreadId, required aiEnabled, readerId}) async => reading),
          tarotReadingProvider('r1').overrideWith((ref) => Stream.value(TarotReading('r1', reading))),
        ],
        child: MaterialApp.router(theme: buildTheme(), routerConfig: router),
      ));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await _settle(t);

      for (var i = 0; i < 3; i++) {
        await t.tap(find.bySemanticsLabel('Pick card').first, warnIfMissed: false);
        await t.pump(const Duration(milliseconds: 100));
      }
      await t.pump(const Duration(seconds: 3));
      await _settle(t);
      expect(find.text('Your cards have spoken'), findsOneWidget);
      await t.tap(find.text('See My Reading'));
      await _settle(t);
      expect(find.byType(TarotResultScreen), findsOneWidget);
      await t.drag(find.byType(ListView).first, const Offset(0, -3000));
      await _settle(t);
    });
  }

  testWidgets('picked card flies from the deck and lands in its slot', (t) async {
    await _phone(t);
    final spread = spreads.firstWhere((s) => s.id == 'one_card');
    final router = GoRouter(initialLocation: '/draw', routes: [
      GoRoute(path: '/draw', builder: (_, _) => CardDrawScreen(request: TarotRequest(question: '', topic: 'general', spread: spread, aiEnabled: true))),
    ]);
    await t.pumpWidget(ProviderScope(
      overrides: [
        ..._overrides,
        startTarotProvider.overrideWithValue(({required question, required topic, spreadId, customSpreadId, required aiEnabled, readerId}) async => _reading(1)),
      ],
      child: MaterialApp.router(theme: buildTheme(), routerConfig: router),
    ));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await _settle(t);
    final backs = find.image(const AssetImage('assets/images/card_back.webp'));
    final before = backs.evaluate().length;

    await t.tap(find.bySemanticsLabel('Pick card').first, warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 300));
    // Mid-flight: the slot is still empty ("1") and the flying copy (+ trail) is drawn in the overlay.
    expect(find.text('1'), findsOneWidget);
    expect(backs.evaluate().length, greaterThan(before - 1));

    await t.pump(const Duration(milliseconds: 600));
    await _settle(t);
    // Landed: the placeholder is replaced by the card, which then flips face-up.
    expect(find.text('1'), findsNothing);
    expect(find.text('Your cards have spoken'), findsOneWidget);
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('tarot home + spreads layout (textScale $scale)', (t) async {
      await _phone(t, textScale: scale);
      for (final w in [const TarotReadingScreen(), const SpreadsScreen()]) {
        await t.pumpWidget(ProviderScope(overrides: _overrides, child: MaterialApp(theme: buildTheme(), home: Scaffold(body: w))));
        await _settle(t);
        await t.drag(find.byType(ListView).first, const Offset(0, -1500));
        await _settle(t);
      }
    });
  }

  for (final scale in [1.0, 1.3]) {
    testWidgets('sign-in + paywall layout (textScale $scale)', (t) async {
      await _phone(t, textScale: scale);
      for (final w in [const SignInScreen(), const PaywallScreen()]) {
        await t.pumpWidget(ProviderScope(overrides: _overrides, child: MaterialApp(theme: buildTheme(), home: w)));
        await _settle(t);
        await t.drag(find.byType(ListView).first, const Offset(0, -1500));
        await _settle(t);
      }
      expect(find.byType(PaywallScreen), findsOneWidget);
    });
  }

  testWidgets('tarot tab: tapping a featured spread opens its sheet and draws', (t) async {
    await _phone(t);
    final router = GoRouter(initialLocation: '/tarot', routes: [
      GoRoute(path: '/tarot', builder: (_, _) => const Scaffold(body: TarotReadingScreen())),
      GoRoute(path: '/tarot/draw', redirect: (_, s) => s.extra is TarotRequest ? null : '/tarot', builder: (_, s) => CardDrawScreen(request: s.extra! as TarotRequest)),
    ]);
    TarotRequest? sent;
    await t.pumpWidget(ProviderScope(
      overrides: [
        ..._overrides,
        spreadsProvider.overrideWith((ref) async => spreads),
        startTarotProvider.overrideWithValue(({required question, required topic, spreadId, customSpreadId, required aiEnabled, readerId}) async => _reading(1)),
      ],
      child: MaterialApp.router(theme: buildTheme(), routerConfig: router),
    ));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await _settle(t);

    // The question box is actionable: an idea fills it.
    final idea = tarotQuestionIdeas['general']!.first;
    await t.scrollUntilVisible(find.text(idea), 200, scrollable: find.byType(Scrollable).first);
    await t.tap(find.text(idea));
    await _settle(t);
    expect(find.widgetWithText(TextField, idea), findsOneWidget);

    // Tapping "One Card" (not via See all) opens the sheet with the question carried over.
    await t.scrollUntilVisible(find.text('One Card'), 200, scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('One Card'));
    await _settle(t);
    expect(find.text('Draw 1 Card'), findsOneWidget);
    expect(find.widgetWithText(TextField, idea), findsWidgets);
    await t.tap(find.text('Draw 1 Card'));
    await _settle(t);
    final draw = t.widget<CardDrawScreen>(find.byType(CardDrawScreen));
    sent = draw.request;
    expect(sent.spread.id, 'one_card');
    expect(sent.question, idea);
  });

  testWidgets('onboarding: intent, reveal a card, finish', (t) async {
    await _phone(t);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await t.pumpWidget(ProviderScope(
      overrides: [
        ..._overrides,
        prefsProvider.overrideWithValue(prefs),
        authGateProvider.overrideWith((ref) => _FakeGate(prefs)),
        cardsProvider.overrideWith((ref) async =>
            (jsonDecode(File('assets/json/cards.json').readAsStringSync()) as List).cast<Map<String, dynamic>>().map(TarotCard.new).toList()),
      ],
      child: MaterialApp(theme: buildTheme(), home: const OnboardingScreen()),
    ));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await _settle(t);
    expect(find.text('Begin'), findsOneWidget);
    await t.tap(find.byKey(const Key('onboardingNext')));
    await _settle(t);
    await t.tap(find.text('Love'));
    await _settle(t);
    await t.tap(find.byKey(const Key('onboardingNext')));
    await _settle(t);
    expect(find.text('Pick a card to continue'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Pick card 2'));
    await _settle(t);
    await t.tap(find.byKey(const Key('onboardingNext')));
    await _settle(t);
    expect(find.text('Get started'), findsOneWidget);
    await t.tap(find.byKey(const Key('onboardingNext')));
    await _settle(t);
    expect(prefs.getBool('onboardingSeen'), isTrue);
    expect(prefs.getStringList(onboardingFocusKey), ['love']);
  });

  testWidgets('sign-up form blocks weak passwords and shows the checklist', (t) async {
    await _phone(t);
    await t.pumpWidget(ProviderScope(overrides: _overrides, child: MaterialApp(theme: buildTheme(), home: const SignInScreen())));
    await _settle(t);
    await t.scrollUntilVisible(find.text('New here? Create an account'), 200, scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('New here? Create an account'));
    await _settle(t);
    await t.enterText(find.byKey(const Key('email')), 'Priya <x>@Example.com');
    await t.enterText(find.byKey(const Key('password')), 'weakpass');
    await _settle(t);
    expect(find.text('At least 8 characters'), findsOneWidget);
    expect(find.text('An uppercase letter (A–Z)'), findsOneWidget);
    // Formatter already cleaned the email as it was typed.
    expect(find.widgetWithText(TextFormField, 'priyax@example.com'), findsOneWidget);
    await t.scrollUntilVisible(find.byKey(const Key('submitAuth')), 200, scrollable: find.byType(Scrollable).first);
    await t.tap(find.byKey(const Key('submitAuth')));
    await _settle(t);
    expect(find.textContaining('Password needs:'), findsOneWidget);
  });

  testWidgets('spreads sheet -> Draw 3 Cards opens the draw screen', (t) async {
    await _phone(t);
    final router = GoRouter(initialLocation: '/spreads', routes: [
      GoRoute(path: '/tarot', builder: (_, _) => const Scaffold()),
      GoRoute(path: '/spreads', builder: (_, _) => const SpreadsScreen()),
      GoRoute(path: '/tarot/draw', redirect: (_, s) => s.extra is TarotRequest ? null : '/tarot', builder: (_, s) => CardDrawScreen(request: s.extra! as TarotRequest)),
    ]);
    await t.pumpWidget(ProviderScope(
      overrides: [
        ..._overrides,
        spreadsProvider.overrideWith((ref) async => spreads),
        startTarotProvider.overrideWithValue(({required question, required topic, spreadId, customSpreadId, required aiEnabled, readerId}) async => _reading(3)),
      ],
      child: MaterialApp.router(theme: buildTheme(), routerConfig: router),
    ));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await _settle(t);
    await t.scrollUntilVisible(find.text('Three Card Spread'), 200, scrollable: find.byType(Scrollable).first);
    await _settle(t);
    await t.tap(find.text('Three Card Spread').first);
    await _settle(t);
    await t.tap(find.text('Draw 3 Cards'));
    await _settle(t);
    expect(find.byType(CardDrawScreen), findsOneWidget);
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('horoscope card with long text (textScale $scale)', (t) async {
      await _phone(t, textScale: scale);
      final d = {
        'periodKey': '2026-09-26',
        'overview': 'Overview ' * 40,
        'affirmation': 'I trust the universe.',
        'love': 'Venus favors honest conversations today; open up to someone you trust and let warmth guide you. ' * 2,
        'career': 'A steady approach wins. Focus on finishing what you started before chasing new ideas. ' * 2,
        'health': 'Rest and hydration restore your energy; a short walk clears your mind. ' * 2,
        'lucky_number': 7,
        'lucky_color': 'Lavender Purple',
        'lucky_color_hex': '#B57EDC',
      };
      await t.pumpWidget(ProviderScope(
        overrides: [
          ..._overrides,
          horoscopeProvider.overrideWith((ref, key) async => d),
        ],
        child: MaterialApp(theme: buildTheme(), home: const Scaffold(body: HoroscopeScreen())),
      ));
      await _settle(t);
      await t.drag(find.byType(ListView).first, const Offset(0, -500));
      await _settle(t);
      expect(find.text('Love'), findsOneWidget);
      expect(zodiacSigns, isNotEmpty);
    });
  }
}
