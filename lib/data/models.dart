import 'package:cloud_firestore/cloud_firestore.dart';

/// Models. AI results are kept as maps with typed accessors so that small schema
/// drifts from the model never crash the UI.

String _s(Object? v) => v is String ? v : (v?.toString() ?? '');
List<String> _ls(Object? v) => v is List ? v.map(_s).toList() : const [];
List<Map<String, dynamic>> _lm(Object? v) =>
    v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const [];
Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

class TarotCard {
  TarotCard(this.j);
  final Map<String, dynamic> j;
  String get id => _s(j['id']);
  String get name => _s(j['name']);
  int get number => (j['number'] as num?)?.toInt() ?? 0;
  String get roman => _s(j['roman']);
  String get arcana => _s(j['arcana']);
  String? get suit => j['suit'] as String?;
  String get element => _s(j['element']);
  String get astrology => _s(j['astrology']);
  List<String> get keywords => _ls(j['keywords']);
  List<String> get reversedKeywords => _ls(j['reversed_keywords']);
  String get description => _s(j['description']);
  String get upright => _s(j['upright']);
  String get reversed => _s(j['reversed']);
  String get symbolism => _s(j['symbolism']);
  String get love => _s(j['love']);
  String get career => _s(j['career']);
  String get yesNo => _s(j['yes_no']);
  String get image => 'assets/cards/$id.webp';
  bool get isMajor => arcana == 'major';
}

class SpreadPosition {
  SpreadPosition(this.index, this.label, this.meaning);
  final int index;
  final String label, meaning;
}

class Spread {
  Spread(Map<String, dynamic> j)
      : id = _s(j['id']),
        name = _s(j['name']),
        subtitle = _s(j['subtitle']),
        description = _s(j['description']),
        categories = _ls(j['category']),
        image = 'assets/images/${_s(j['image'])}.webp',
        premium = j['premium'] == true,
        custom = false,
        positions = _lm(j['positions']).map((p) => SpreadPosition((p['index'] as num).toInt(), _s(p['label']), _s(p['meaning']))).toList();

  Spread.custom({required this.id, required this.name, required this.positions})
      : subtitle = '${positions.length} cards · Custom',
        description = 'Your own spread',
        categories = const ['custom'],
        image = 'assets/images/spread_custom.webp',
        premium = true,
        custom = true;

  final String id, name, subtitle, description, image;
  final List<String> categories;
  final bool premium, custom;
  final List<SpreadPosition> positions;
}

class Reader {
  Reader(Map<String, dynamic> j)
      : id = _s(j['id']),
        name = _s(j['name']),
        tags = _ls(j['tags']),
        filters = _ls(j['filters']),
        description = _s(j['description']),
        image = 'assets/images/${_s(j['image'])}.webp',
        premium = j['premium'] == true,
        popular = j['popular'] == true,
        greeting = _s(j['greeting']);
  final String id, name, description, image, greeting;
  final List<String> tags, filters;
  final bool premium, popular;
}

class AppUser {
  AppUser(this.uid, this.j);
  final String uid;
  final Map<String, dynamic> j;
  String get displayName => _s(j['displayName']);
  String get firstName => displayName.split(' ').first;
  String? get zodiac => j['zodiac'] as String?;
  String? get dob => j['dob'] as String?;
  List<String> get focusAreas => _ls(j['focusAreas']);
  String get language => _s(j['language']).isEmpty ? 'en' : _s(j['language']);
  String get preferredReaderId => _s(j['preferredReaderId']).isEmpty ? 'selene' : _s(j['preferredReaderId']);
  bool get profileComplete => j['profileComplete'] == true;
  Map<String, dynamic> get settings => _m(j['settings']);
  bool get keepPalmPhotos => settings['keepPalmPhotos'] == true;
  bool get premium {
    final p = _m(j['premium']);
    if (p['active'] != true) return false;
    final exp = p['expiresAt'];
    return exp is! Timestamp || exp.toDate().isAfter(DateTime.now());
  }

  int get lifetimePalm => (_m(j['usage'])['lifetimePalm'] as num?)?.toInt() ?? 0;

  /// Where Premium was bought: 'dodo' (web checkout) or null (Google Play / App Store via RevenueCat).
  String? get premiumSource => _m(j['premium'])['source'] as String?;

  String? get birthTime => j['birthTime'] as String?;
  String? get birthPlace => j['birthPlace'] as String?;

  /// Today's usage of a metered feature ('chat', 'tarot', 'palm'). The server resets counters per UTC day.
  int usedToday(String feature) {
    final u = _m(j['usage']);
    if (u['date'] != DateTime.now().toUtc().toIso8601String().substring(0, 10)) return 0;
    return (u[feature] as num?)?.toInt() ?? 0;
  }

  int get freeChatsLeft => premium ? 999 : (freeChatDaily - usedToday('chat')).clamp(0, freeChatDaily);
  int get freeTarotLeft => premium ? 999 : (freeTarotDaily - usedToday('tarot')).clamp(0, freeTarotDaily);
}

/// Free-tier limits (mirrors FREE_* defaults in functions/src/config.ts; the server is authoritative).
const freeChatDaily = 3;
const freeTarotDaily = 1;
const freePalmLifetime = 1;

class PalmLine {
  PalmLine(this.j);
  final Map<String, dynamic> j;
  String get name => _s(j['name']);
  String get status => _s(j['status']);
  String get observation => _s(j['observation']);
  String get meaning => _s(j['meaning']);
  double get confidence => (j['confidence'] as num?)?.toDouble() ?? 0;
  List<(double, double)> get points => _lm(j['points'])
      .map((p) => (((p['x'] as num?) ?? 0).toDouble(), ((p['y'] as num?) ?? 0).toDouble()))
      .toList();
  String get title => '${name[0].toUpperCase()}${name.substring(1)} Line';
  bool get drawable => confidence >= 0.4 && points.length >= 2;
}

class PalmReading {
  PalmReading(this.j);
  final Map<String, dynamic> j;
  String get headline => _s(j['headline']);
  Map<String, dynamic> get handType => _m(j['hand_type']);
  String get element => _s(handType['element']);
  String get handTypeName => element.isEmpty ? 'Unknown Hand' : '${element[0].toUpperCase()}${element.substring(1)} Hand';
  List<String> get handTags => _ls(handType['tags']);
  String get handDescription => _s(handType['description']);
  List<PalmLine> get lines {
    const order = ['heart', 'head', 'life', 'fate'];
    final l = _lm(j['lines']).map(PalmLine.new).toList();
    l.sort((a, b) => order.indexOf(a.name).compareTo(order.indexOf(b.name)));
    return l;
  }

  /// Palm area on the photo (normalized 0..1 as left, top, right, bottom), when the model returned one.
  (double, double, double, double)? get palmBox {
    final b = _m(j['palm_box']);
    double? v(String k) => (b[k] as num?)?.toDouble();
    final (l, t, r, bt) = (v('xmin'), v('ymin'), v('xmax'), v('ymax'));
    if (l == null || t == null || r == null || bt == null || r - l < 0.1 || bt - t < 0.1) return null;
    return (l, t, r, bt);
  }

  List<Map<String, dynamic>> get mounts => _lm(j['mounts']);
  Map<String, dynamic> get overview => _m(j['overview']);
  List<Map<String, dynamic>> get traits => _lm(_m(j['personality'])['traits']);
  Map<String, dynamic> get love => _m(j['love']);
  Map<String, dynamic> get career => _m(j['career']);
  Map<String, dynamic> get lifePath => _m(j['life_path']);
  String get quote => _s(j['quote']);
  String get didYouKnow => _s(j['did_you_know']);
  bool get safetyFlag => j['safety_flag'] == true;

  static String strOf(Map<String, dynamic> m, String k) => _s(m[k]);
  static List<String> listOf(Map<String, dynamic> m, String k) => _ls(m[k]);
  static List<Map<String, dynamic>> mapsOf(Map<String, dynamic> m, String k) => _lm(m[k]);
}

class DrawnCard {
  DrawnCard(Map<String, dynamic> j)
      : cardId = _s(j['cardId']),
        reversed = j['reversed'] == true,
        position = (j['position'] as num?)?.toInt() ?? 0,
        positionLabel = _s(j['positionLabel']),
        positionMeaning = _s(j['positionMeaning']);
  final String cardId, positionLabel, positionMeaning;
  final bool reversed;
  final int position;
}

class TarotReading {
  TarotReading(this.id, this.j);
  final String id;
  final Map<String, dynamic> j;
  String get question => _s(j['question']);
  String get topic => _s(j['topic']);
  String get spreadName => _s(j['spreadName']);
  String get readerId => _s(j['readerId']);
  bool get aiEnabled => j['aiEnabled'] != false;
  List<DrawnCard> get cards => _lm(j['cards']).map(DrawnCard.new).toList();
  Map<String, dynamic> get interp => _m(j['interpretation']);
  bool get hasInterpretation => j['interpretation'] is Map;
  String get title => _s(interp['title']).isEmpty ? spreadName : _s(interp['title']);
  String get synthesis => _s(interp['synthesis']);
  String get leaning => _s(interp['yes_no_leaning']);
  List<String> get advice => _ls(interp['advice']);
  String get affirmation => _s(interp['affirmation']);
  List<String> get followUps => _ls(interp['follow_up_questions']);
  bool get safety => j['safety'] == true;
  String get safetyMessage => _s(j['safetyMessage']);
  Map<String, dynamic>? cardInterp(int index) =>
      _lm(interp['cards']).where((c) => (c['position_index'] as num?)?.toInt() == index).firstOrNull;
  DateTime? get createdAt => switch (j['createdAt']) {
        Timestamp t => t.toDate(),
        String s => DateTime.tryParse(s),
        _ => null,
      };
}
