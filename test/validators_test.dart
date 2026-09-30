import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selene/core/validators.dart';

String _format(List<TextInputFormatter> fs, String input) {
  var v = TextEditingValue(text: input, selection: TextSelection.collapsed(offset: input.length));
  for (final f in fs) {
    v = f.formatEditUpdate(TextEditingValue.empty, v);
  }
  return v.text;
}

void main() {
  group('name', () {
    test('accepts letters in any script with single spaces', () {
      expect(Validators.name('Priya Sharma'), isNull);
      expect(Validators.name('प्रिया शर्मा'), isNull);
      expect(Validators.name('José Álvarez'), isNull);
    });
    test('rejects symbols, digits, emoji, markup', () {
      for (final bad in ['Priya123', '<script>', 'Priya ✨', "Robert'); DROP", 'a', '', 'Priya_S', 'Priya  S']) {
        expect(Validators.name(bad), isNotNull, reason: bad);
      }
    });
    test('input formatter strips disallowed characters as you type', () {
      expect(_format(Validators.nameFormatters, '  Pri<ya>1 2 3  Sh@rma!'), 'Priya Shrma');
      expect(_format(Validators.nameFormatters, 'x' * 60).length, Validators.nameMax);
    });
    test('sanitizes Google display names for prefill', () {
      expect(Validators.sanitizeName('John (Work) 2'), 'John Work');
    });
  });

  group('email', () {
    test('valid and invalid addresses', () {
      expect(Validators.email('priya@example.com'), isNull);
      expect(Validators.email('p.sharma+tarot@mail.co.in'), isNull);
      for (final bad in ['', 'priya', 'priya@', '@example.com', 'priya@example', 'pri ya@example.com', 'priya@@example.com']) {
        expect(Validators.email(bad), isNotNull, reason: bad);
      }
    });
    test('formatter removes spaces, quotes, markup and lower-cases', () {
      expect(_format(Validators.emailFormatters, ' Priya "<x>"@Example.COM '), 'priyax@example.com');
    });
  });

  group('password', () {
    test('requires 8+ chars with upper, lower, number and symbol', () {
      expect(Validators.newPassword('Moon#2026'), isNull);
      expect(Validators.newPassword('short1!A'), isNull);
      expect(Validators.newPassword('Ab1!'), contains('8 characters'));
      expect(Validators.newPassword('moon#2026'), contains('uppercase'));
      expect(Validators.newPassword('MOON#2026'), contains('lowercase'));
      expect(Validators.newPassword('Moon#Moon'), contains('number'));
      expect(Validators.newPassword('Moon2026x'), contains('symbol'));
    });
    test('rejects very common passwords', () {
      expect(Validators.newPassword('Passw0rd!'), contains('common'));
    });
    test('formatter blocks whitespace and caps length', () {
      expect(_format(Validators.passwordFormatters, 'Moon #20\t26'), 'Moon#2026');
      expect(_format(Validators.passwordFormatters, 'A' * 100).length, Validators.passwordMax);
    });
  });
}
