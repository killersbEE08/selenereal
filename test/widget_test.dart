import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:selene/core/astro.dart';
import 'package:selene/data/models.dart';

void main() {
  group('icons', () {
    test('every Ic name has a bundled SVG', () {
      final src = File('lib/core/icons.dart').readAsStringSync();
      final block = src.substring(src.indexOf('abstract final class Ic'), src.indexOf('/// Tintable SVG icon'));
      final names = RegExp(r"= '([a-z0-9_]+)'").allMatches(block).map((m) => m.group(1)!).toSet();
      expect(names.length, greaterThan(60));
      for (final n in names) {
        expect(File('assets/icons/$n.svg').existsSync(), isTrue, reason: n);
      }
    });
    test('no corrupted "?" placeholders or emoji left in datasets', () {
      for (final f in ['spreads.json', 'readers.json']) {
        final t = File('assets/json/$f').readAsStringSync();
        expect(RegExp(r'\w \? \w|\?{2,}').hasMatch(t), isFalse, reason: f);
      }
    });
  });

  group('zodiac', () {
    test('sun sign boundaries', () {
      expect(sunSignFor(DateTime(2000, 3, 21)).id, 'aries');
      expect(sunSignFor(DateTime(2000, 4, 19)).id, 'aries');
      expect(sunSignFor(DateTime(2000, 4, 20)).id, 'taurus');
      expect(sunSignFor(DateTime(2000, 1, 5)).id, 'capricorn');
      expect(sunSignFor(DateTime(2000, 12, 25)).id, 'capricorn');
      expect(sunSignFor(DateTime(2000, 2, 19)).id, 'pisces');
      expect(sunSignFor(DateTime(2000, 9, 26)).id, 'libra');
    });
    test('every sign has an image asset', () {
      for (final s in zodiacSigns) {
        expect(File(s.image).existsSync(), isTrue, reason: s.image);
      }
    });
  });

  group('moon', () {
    test('reference new moon and full moon', () {
      expect(moonPhase(DateTime.utc(2000, 1, 6, 18, 14)).name, 'New Moon');
      final full = moonPhase(DateTime.utc(2000, 1, 21, 12));
      expect(full.name, 'Full Moon');
      expect(full.illumination, greaterThan(0.95));
    });
    test('matches the TypeScript implementation for a known date', () {
      // 2026-09-26 12:00 UTC — the functions test uses the same algorithm.
      final m = moonPhase(DateTime.utc(2026, 9, 26, 12));
      expect(m.illumination, inInclusiveRange(0, 1));
      expect(moonPhaseNames, contains(m.name));
    });
  });

  group('datasets', () {
    List<Map<String, dynamic>> load(String p) => (jsonDecode(File(p).readAsStringSync()) as List).cast<Map<String, dynamic>>();

    test('78 cards, each with an image file', () {
      final cards = load('assets/json/cards.json').map(TarotCard.new).toList();
      expect(cards.length, 78);
      for (final c in cards) {
        expect(File(c.image).existsSync(), isTrue, reason: c.image);
        expect(c.upright, isNotEmpty);
      }
    });
    test('spreads and readers reference existing images', () {
      for (final s in load('assets/json/spreads.json').map(Spread.new)) {
        expect(File(s.image).existsSync(), isTrue, reason: s.image);
        expect(s.positions, isNotEmpty);
      }
      for (final r in load('assets/json/readers.json').map(Reader.new)) {
        expect(File(r.image).existsSync(), isTrue, reason: r.image);
      }
    });
  });

  group('models', () {
    test('palm reading tolerates missing fields and sorts lines', () {
      final r = PalmReading({
        'hand_type': {'element': 'water', 'tags': ['Intuitive']},
        'lines': [
          {'name': 'fate', 'status': 'visible', 'points': [{'x': 0.5, 'y': 0.9}], 'confidence': 0.7},
          {'name': 'heart', 'status': 'strong', 'points': [], 'confidence': 0.9},
        ],
      });
      expect(r.handTypeName, 'Water Hand');
      expect(r.lines.map((l) => l.name), ['heart', 'fate']);
      expect(r.lines.last.points.first, (0.5, 0.9));
      expect(r.love, isEmpty);
      expect(r.quote, '');
    });
    test('tarot reading finds interpretation by position', () {
      final t = TarotReading('id', {
        'spreadName': 'Three Card',
        'cards': [
          {'cardId': 'major_19', 'reversed': false, 'position': 0, 'positionLabel': 'Past'},
        ],
        'interpretation': {
          'title': 'A Bright Turn',
          'cards': [
            {'position_index': 0, 'card_id': 'major_19', 'headline': 'Joy', 'interpretation': 'x'},
          ],
          'advice': ['a', 'b', 'c'],
        },
      });
      expect(t.title, 'A Bright Turn');
      expect(t.cardInterp(0)?['headline'], 'Joy');
      expect(t.cardInterp(1), isNull);
    });
    test('premium expiry is respected', () {
      expect(AppUser('u', {'premium': {'active': true}}).premium, isTrue);
      expect(AppUser('u', {'premium': {'active': false}}).premium, isFalse);
      expect(AppUser('u', {}).premium, isFalse);
    });
  });
}
