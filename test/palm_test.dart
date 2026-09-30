import 'dart:ui' show PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:selene/app.dart';
import 'package:selene/core/birth_fields.dart';
import 'package:selene/core/theme.dart';
import 'package:selene/core/validators.dart';
import 'package:selene/data/api.dart';
import 'package:selene/data/models.dart';
import 'package:selene/features/palm.dart';
import 'package:selene/features/palm_overlay.dart';
import 'package:selene/features/palm_results.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _today() => DateTime.now().toUtc().toIso8601String().substring(0, 10);

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  resultTests();

  group('overlay geometry', () {
    test('without a palm box the photo covers the canvas (BoxFit.cover)', () {
      final (s, o) = PalmOverlayPainter.fit(const Size(300, 400), 1000, 1000, null);
      expect(s, 0.4);
      expect(o, const Offset(-50, 0));
    });

    test('zooms onto the palm box but never leaves empty bands', () {
      const size = Size(300, 400);
      final (s, o) = PalmOverlayPainter.fit(size, 1000, 1000, (0.3, 0.4, 0.7, 0.8));
      expect(s, greaterThan(0.4)); // zoomed in vs plain cover
      // Photo still covers the whole canvas.
      expect(o.dx, lessThanOrEqualTo(0));
      expect(o.dy, lessThanOrEqualTo(0));
      expect(o.dx + 1000 * s, greaterThanOrEqualTo(size.width - 1e-6));
      expect(o.dy + 1000 * s, greaterThanOrEqualTo(size.height - 1e-6));
      // The palm centre lands near the canvas centre.
      final cx = o.dx + 0.5 * 1000 * s;
      expect((cx - size.width / 2).abs(), lessThan(1));
    });

    test('smoothing keeps endpoints and softens a zig-zag', () {
      final pts = [const Offset(0, 0), const Offset(10, 10), const Offset(20, 0), const Offset(30, 10)];
      final s = PalmOverlayPainter.smooth(pts);
      expect(s.first, pts.first);
      expect(s.last, pts.last);
      expect(s[1].dy, lessThan(10));
      expect(s[2].dy, greaterThan(0));
    });

    test('spline passes through the first and last point', () {
      final path = PalmOverlayPainter.spline([const Offset(0, 0), const Offset(50, 20), const Offset(100, 0)]);
      final m = path.computeMetrics().first;
      expect(m.getTangentForOffset(0)!.position, const Offset(0, 0));
      final end = m.getTangentForOffset(m.length)!.position;
      expect((end - const Offset(100, 0)).distance, lessThan(0.01));
    });
  });

  group('models', () {
    test('palm box and drawable lines', () {
      final r = PalmReading({
        'palm_box': {'xmin': 0.2, 'ymin': 0.3, 'xmax': 0.8, 'ymax': 0.9},
        'lines': [
          {'name': 'life', 'confidence': 0.9, 'points': [{'x': 0.3, 'y': 0.4}, {'x': 0.35, 'y': 0.7}]},
          {'name': 'fate', 'confidence': 0.2, 'points': [{'x': 0.5, 'y': 0.8}, {'x': 0.5, 'y': 0.5}]},
          {'name': 'heart', 'confidence': 0.9, 'points': [{'x': 0.5, 'y': 0.4}]},
        ],
      });
      expect(r.palmBox, (0.2, 0.3, 0.8, 0.9));
      expect(r.lines.map((l) => l.name), ['heart', 'life', 'fate']);
      expect(r.lines.map((l) => l.drawable), [false, true, false]);
      expect(PalmReading({'palm_box': {'xmin': 0.2, 'ymin': 0.3, 'xmax': 0.21, 'ymax': 0.9}}).palmBox, isNull);
    });

    test('free chat counter resets with the server day', () {
      expect(AppUser('u', {'usage': {'date': _today(), 'chat': 2}}).freeChatsLeft, 1);
      expect(AppUser('u', {'usage': {'date': _today(), 'chat': 9}}).freeChatsLeft, 0);
      expect(AppUser('u', {'usage': {'date': '2000-01-01', 'chat': 3}}).freeChatsLeft, freeChatDaily);
      expect(AppUser('u', {'premium': {'active': true}, 'usage': {'date': _today(), 'chat': 50}}).freeChatsLeft, greaterThan(0));
    });

    test('palm subject json omits empty optional fields', () {
      expect(const PalmSubject(name: 'Riya', relation: 'partner').toJson(), {'name': 'Riya', 'relation': 'partner'});
      expect(const PalmSubject(name: 'Riya', relation: 'friend', dob: '1999-05-02', birthTime: '06:30', birthPlace: 'Delhi').toJson(),
          {'name': 'Riya', 'relation': 'friend', 'dob': '1999-05-02', 'birthTime': '06:30', 'birthPlace': 'Delhi'});
    });
  });

  group('birth fields', () {
    test('time round-trips as HH:mm', () {
      expect(formatBirthTime(const TimeOfDay(hour: 6, minute: 5)), '06:05');
      expect(parseBirthTime('23:59'), const TimeOfDay(hour: 23, minute: 59));
      expect(parseBirthTime('24:00'), isNull);
      expect(parseBirthTime(null), isNull);
    });

    test('place validation', () {
      expect(Validators.place('Patna, India'), isNull);
      expect(Validators.place("St. John's"), isNull);
      expect(Validators.place('नई दिल्ली'), isNull);
      expect(Validators.place(''), isNotNull);
      expect(Validators.place('', required: false), isNull);
      expect(Validators.place('Delhi <script>'), isNotNull);
      expect(Validators.place('Room 42'), isNotNull);
    });
  });

  testWidgets("palm page: 'Someone else's' reveals the details form", (t) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.75;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await t.pumpWidget(ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        authStateProvider.overrideWith((ref) => Stream.value(null)),
        userDocProvider.overrideWith((ref) => Stream.value(null)),
      ],
      child: MaterialApp(theme: buildTheme(), home: const Scaffold(body: PalmHomeScreen())),
    ));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.scrollUntilVisible(find.text('Whose palm is it?'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Whose palm is it?'), findsOneWidget);
    expect(find.byKey(const Key('otherNameField')), findsNothing);
    await t.scrollUntilVisible(find.text("Someone else's"), 200, scrollable: find.byType(Scrollable).first);
    await t.tap(find.text("Someone else's"));
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('otherNameField')), findsOneWidget);
    expect(find.text('Partner'), findsOneWidget);
    expect(find.text('Place of birth (optional)'.toUpperCase()), findsOneWidget);
  });
}


Map<String, dynamic> _palmDoc() => {
      'status': 'done',
      'hand': 'left',
      'subject': {'name': 'Riya', 'relation': 'partner'},
      'result': {
        'headline': 'A warm and curious heart.',
        'palm_box': {'xmin': 0.2, 'ymin': 0.35, 'xmax': 0.8, 'ymax': 0.9},
        'hand_type': {'element': 'water', 'tags': ['Intuitive', 'Kind', 'Creative'], 'description': 'Long palm, long fingers. ' * 4},
        'lines': [
          for (final n in ['heart', 'head', 'life', 'fate'])
            {
              'name': n,
              'status': 'clear',
              'observation': 'Observation ' * 6,
              'meaning': 'Meaning of the line. ' * 8,
              'confidence': n == 'fate' ? 0.2 : 0.9,
              'points': [for (var i = 0; i < 8; i++) {'x': 0.25 + i * 0.07, 'y': 0.45 + (i % 3) * 0.02}],
            },
        ],
        'mounts': [
          {'name': 'venus', 'prominence': 'high', 'meaning': 'Warmth. ' * 5},
        ],
        'overview': {'love': 'Deeply loyal', 'career': 'Creative path', 'life_path': 'Steady growth', 'personality': 'Gentle and wise'},
        'personality': {
          'traits': [for (var i = 0; i < 5; i++) {'emoji': '*', 'text': 'Trait number $i ' * 3}],
        },
        'love': {'summary': 's', 'strengths': ['a', 'b', 'c'], 'mindful_of': ['d', 'e'], 'outlook': 'o', 'chip': 'Positive'},
        'career': {'summary': 's', 'best_areas': [], 'outlook': 'o', 'chip': 'Growth'},
        'life_path': {'summary': 's', 'predictions': [], 'chip': 'Bright'},
        'quote': 'Trust your path.',
        'did_you_know': '',
        'safety_flag': false,
      },
    };

void resultTests() {
  for (final premium in [false, true]) {
    testWidgets('palm results render (premium: $premium)', (t) async {
      t.view.physicalSize = const Size(1080, 2340);
      t.view.devicePixelRatio = 2.75;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          userDocProvider.overrideWith((ref) => Stream.value(null)),
          isPremiumProvider.overrideWith((ref) => premium),
          palmReadingDocProvider('p1').overrideWith((ref) => Stream.value(_palmDoc())),
          palmPhotoProvider('p1').overrideWith((ref) async => null),
        ],
        child: MaterialApp(theme: buildTheme(), home: const PalmResultScreen(readingId: 'p1')),
      ));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text("Riya's Palm Reading"), findsOneWidget);
      if (!premium) await t.scrollUntilVisible(find.text('Unlock Full Reading'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Unlock Full Reading'), premium ? findsNothing : findsOneWidget);
      await t.scrollUntilVisible(find.text('Love & Relationships${premium ? '' : ' · Premium'}'), -300, scrollable: find.byType(Scrollable).first);

      await t.tap(find.text('Line Analysis'));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Heart Line'), findsOneWidget);
      expect(find.textContaining('Unlock 3 more lines'), premium ? findsNothing : findsOneWidget);

      await t.tap(find.text('Personality'));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Unlock with Premium'), premium ? findsNothing : findsOneWidget);
    });
  }

  testWidgets('overlay painter draws a real image with a highlighted line', (t) async {
    final img = await t.runAsync(() => createTestImage(width: 400, height: 600));
    final lines = (_palmDoc()['result'] as Map)['lines'] as List;
    final painter = PalmOverlayPainter(
      img: img!,
      lines: [for (final l in lines) PalmLine(Map<String, dynamic>.from(l as Map))].where((l) => l.drawable).toList(),
      palmBox: (0.2, 0.35, 0.8, 0.9),
      highlight: 'life',
      progress: 0.6,
    );
    final recorder = PictureRecorder();
    painter.paint(Canvas(recorder), const Size(300, 360));
    expect(recorder.endRecording(), isNotNull);
    expect(painter.shouldRepaint(PalmOverlayPainter(img: img, lines: painter.lines, palmBox: painter.palmBox, highlight: 'life', progress: 1)), isTrue);
  });
}
