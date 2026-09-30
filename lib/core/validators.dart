import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

/// Client-side input rules. These give instant feedback and keep junk out of the fields;
/// the real enforcement lives server-side (firestore.rules + Cloud Functions).
abstract final class Validators {
  static const nameMax = 40;
  static const emailMax = 254;
  static const passwordMin = 8;
  static const passwordMax = 64;

  // Letters from any script (Latin, Devanagari…) plus combining marks, separated by single spaces.
  static final _nameChars = RegExp(r'[\p{L}\p{M} ]', unicode: true);
  static final _nameFull = RegExp(r'^[\p{L}\p{M}]+( [\p{L}\p{M}]+)*$', unicode: true);
  // Pragmatic RFC 5322 subset; Firebase re-validates.
  static final _email = RegExp(r"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9](?:[A-Za-z0-9\-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9\-]{0,61}[A-Za-z0-9])?)+$");
  static final _emailChars = RegExp(r'[A-Za-z0-9@._%+\-]');

  /// Name field: letters and spaces only, no leading/double spaces, max 40.
  static final nameFormatters = <TextInputFormatter>[
    FilteringTextInputFormatter.allow(_nameChars),
    _NoLeadingOrDoubleSpace(),
    LengthLimitingTextInputFormatter(nameMax),
  ];

  /// Email field: only characters valid in an address, no spaces, lower-cased, max 254.
  static final emailFormatters = <TextInputFormatter>[
    FilteringTextInputFormatter.allow(_emailChars),
    LengthLimitingTextInputFormatter(emailMax),
    _LowerCase(),
  ];

  /// Password field: no whitespace / control characters, max 64.
  static final passwordFormatters = <TextInputFormatter>[
    FilteringTextInputFormatter.deny(RegExp(r'[\s\u0000-\u001F\u007F]')),
    LengthLimitingTextInputFormatter(passwordMax),
  ];

  /// Removes characters the name rules don't allow (used to prefill from Google profiles).
  static String sanitizeName(String raw) {
    final kept = raw.characters.where((c) => _nameChars.hasMatch(c)).join();
    final s = kept.replaceAll(RegExp(r' {2,}'), ' ').trim();
    return s.length > nameMax ? s.substring(0, nameMax).trim() : s;
  }

  static String? name(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Please enter your name.';
    if (s.length < 2) return 'Name is too short.';
    if (!_nameFull.hasMatch(s)) return 'Use letters and single spaces only.';
    return null;
  }

  static String? email(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Please enter your email.';
    if (s.length > emailMax || !_email.hasMatch(s)) return 'That email address looks invalid.';
    return null;
  }

  /// Rules a new password must meet, in display order.
  static List<(String, bool)> passwordChecks(String p) => [
        ('At least $passwordMin characters', p.length >= passwordMin),
        ('An uppercase letter (A–Z)', RegExp('[A-Z]').hasMatch(p)),
        ('A lowercase letter (a–z)', RegExp('[a-z]').hasMatch(p)),
        ('A number (0–9)', RegExp('[0-9]').hasMatch(p)),
        ('A symbol (e.g. ! @ # \$ %)', RegExp(r'[^A-Za-z0-9\s]').hasMatch(p)),
      ];

  static const _common = {'password', 'passw0rd', '12345678', '123456789', 'qwerty123', 'iloveyou', 'selene123', 'abcd1234', 'admin123', 'welcome1'};

  /// Validator for creating a password (sign-up, linking a guest account).
  static String? newPassword(String? v) {
    final p = v ?? '';
    if (p.isEmpty) return 'Please choose a password.';
    final missing = passwordChecks(p).where((c) => !c.$2).map((c) => c.$1.toLowerCase()).toList();
    if (missing.isNotEmpty) return 'Password needs: ${missing.join(', ')}.';
    if (_common.contains(p.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''))) return 'That password is too common. Try another.';
    return null;
  }

  /// Validator for signing in (existing accounts may pre-date the strength rules).
  static String? existingPassword(String? v) => (v ?? '').isEmpty ? 'Please enter your password.' : null;

  static const placeMax = 60;
  // Mirrors firestore.rules / safeBirthPlace: letters, marks, spaces and , . ' -
  static final _placeChars = RegExp(r"[\p{L}\p{M} ,.'\-]", unicode: true);

  /// Birth place field (city, country).
  static final placeFormatters = <TextInputFormatter>[
    FilteringTextInputFormatter.allow(_placeChars),
    _NoLeadingOrDoubleSpace(),
    LengthLimitingTextInputFormatter(placeMax),
  ];

  static String? place(String? v, {bool required = true}) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return required ? 'Please enter your birth place.' : null;
    if (s.length < 2) return 'Place name is too short.';
    if (!s.characters.every(_placeChars.hasMatch)) return 'Use letters, spaces and commas only.';
    return null;
  }
}

class _NoLeadingOrDoubleSpace extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final t = newValue.text.replaceAll(RegExp(r' {2,}'), ' ').replaceFirst(RegExp(r'^ +'), '');
    if (t == newValue.text) return newValue;
    final off = (newValue.selection.baseOffset - (newValue.text.length - t.length)).clamp(0, t.length);
    return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: off));
  }
}

class _LowerCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) => newValue.copyWith(text: newValue.text.toLowerCase());
}
