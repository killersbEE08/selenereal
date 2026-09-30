import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';

const useEmulator = bool.fromEnvironment('USE_EMULATOR');
const emulatorHost = String.fromEnvironment('EMULATOR_HOST', defaultValue: '10.0.2.2');
const functionsRegion = 'asia-south1';

FirebaseFunctions get functions => FirebaseFunctions.instanceFor(region: functionsRegion);

// ---------- Static datasets (bundled, offline-first) ----------

Future<List<Map<String, dynamic>>> _loadJson(String path) async =>
    (jsonDecode(await rootBundle.loadString(path)) as List).cast<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

final cardsProvider = FutureProvider<List<TarotCard>>((ref) async => (await _loadJson('assets/json/cards.json')).map(TarotCard.new).toList());
final cardMapProvider = FutureProvider<Map<String, TarotCard>>((ref) async => {for (final c in await ref.watch(cardsProvider.future)) c.id: c});
final spreadsProvider = FutureProvider<List<Spread>>((ref) async => (await _loadJson('assets/json/spreads.json')).map(Spread.new).toList());
final readersProvider = FutureProvider<List<Reader>>((ref) async => (await _loadJson('assets/json/readers.json')).map(Reader.new).toList());

// ---------- Auth & user ----------

final authStateProvider = StreamProvider<User?>((ref) => FirebaseAuth.instance.authStateChanges());

final userDocProvider = StreamProvider<AppUser?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(null);
  return FirebaseFirestore.instance.doc('users/${user.uid}').snapshots().map((s) => AppUser(user.uid, s.data() ?? {}));
});

final isPremiumProvider = Provider<bool>((ref) => ref.watch(userDocProvider).value?.premium ?? false);

String? get currentUid => FirebaseAuth.instance.currentUser?.uid;
DocumentReference<Map<String, dynamic>> userRef() => FirebaseFirestore.instance.doc('users/$currentUid');

final customSpreadsProvider = StreamProvider<List<Spread>>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return Stream.value([]);
  return FirebaseFirestore.instance.collection('users/$uid/customSpreads').orderBy('createdAt', descending: true).snapshots().map((q) => q.docs.map((d) {
        final pos = (d.data()['positions'] as List? ?? []).cast<Map>();
        return Spread.custom(
          id: d.id,
          name: d.data()['name'] as String? ?? 'My Spread',
          positions: [for (var i = 0; i < pos.length; i++) SpreadPosition(i, '${pos[i]['label']}', '${pos[i]['meaning']}')],
        );
      }).toList());
});

final collectionProvider = StreamProvider<Set<String>>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return Stream.value({});
  return FirebaseFirestore.instance.collection('users/$uid/collection').snapshots().map((q) => q.docs.map((d) => d.id).toSet());
});

final tarotHistoryProvider = StreamProvider<List<TarotReading>>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return Stream.value([]);
  return FirebaseFirestore.instance
      .collection('users/$uid/tarotReadings')
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((q) => q.docs.map((d) => TarotReading(d.id, d.data())).toList());
});

final palmHistoryProvider = StreamProvider<List<(String, Map<String, dynamic>)>>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return Stream.value([]);
  return FirebaseFirestore.instance
      .collection('users/$uid/palmReadings')
      .where('status', isEqualTo: 'done')
      .snapshots()
      .map((q) {
    final l = q.docs.map((d) => (d.id, d.data())).toList();
    l.sort((a, b) => ((b.$2['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0).compareTo((a.$2['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0));
    return l;
  });
});

final chatsProvider = StreamProvider<List<(String, Map<String, dynamic>)>>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return Stream.value([]);
  return FirebaseFirestore.instance
      .collection('users/$uid/chats')
      .orderBy('lastMessageAt', descending: true)
      .limit(50)
      .snapshots()
      .map((q) => q.docs.map((d) => (d.id, d.data())).toList());
});

// ---------- Backend API (Cloud Functions) ----------

class ApiException implements Exception {
  ApiException(this.message, {this.needsPremium = false, this.code});
  final String message;
  final bool needsPremium;
  final String? code;
  @override
  String toString() => message;
}

class Api {
  static Future<Map<String, dynamic>> call(String name, Map<String, dynamic> data, {Duration timeout = const Duration(seconds: 90)}) async {
    try {
      final res = await functions.httpsCallable(name, options: HttpsCallableOptions(timeout: timeout)).call(data);
      return _deepMap(res.data);
    } on FirebaseFunctionsException catch (e) {
      final details = e.details is Map ? Map<String, dynamic>.from(e.details as Map) : const <String, dynamic>{};
      // Quota errors open the paywall, except for premium users at their cap and photo-attempt limits.
      final premium = (e.code == 'resource-exhausted' && details['reason'] != 'premium_cap' && details['reason'] != 'attempts') || details['reason'] == 'premium';
      // Our functions throw HttpsError with human messages; infrastructure errors carry codes
      // like "INTERNAL"/"deadline-exceeded" that must not reach the user verbatim.
      final msg = switch (e.code) {
        'internal' || 'unknown' || 'data-loss' => 'Something went wrong on our side. Please try again.',
        'deadline-exceeded' => 'That took too long. Please try again.',
        'unavailable' when (e.message ?? '').toUpperCase() == 'UNAVAILABLE' => 'The service is busy right now. Please try again in a moment.',
        'unauthenticated' => 'Please sign in to continue.',
        _ => (e.message == null || e.message!.isEmpty || e.message == e.code.toUpperCase()) ? 'Something went wrong. Please try again.' : e.message!,
      };
      throw ApiException(msg, needsPremium: premium, code: e.code);
    } on SocketException {
      throw ApiException("You're offline. Check your connection and try again.");
    } on TimeoutException {
      throw ApiException('That took too long. Please try again.');
    }
  }

  static Map<String, dynamic> _deepMap(Object? v) => v is Map ? v.map((k, val) => MapEntry('$k', _deep(val))) : <String, dynamic>{};
  static Object? _deep(Object? v) => v is Map ? _deepMap(v) : (v is List ? v.map(_deep).toList() : v);

  static Future<Map<String, dynamic>> analyzePalm(String readingId, String hand, {Map<String, dynamic>? subject}) =>
      call('analyzePalm', {'readingId': readingId, 'hand': hand, 'subject': ?subject}, timeout: const Duration(seconds: 150));

  static Future<Map<String, dynamic>> startTarot({
    required String question,
    required String topic,
    String? spreadId,
    String? customSpreadId,
    required bool aiEnabled,
    String? readerId,
  }) =>
      call('startTarotReading', {
        'question': question,
        'topic': topic,
        'spreadId': ?spreadId,
        'customSpreadId': ?customSpreadId,
        'aiEnabled': aiEnabled,
        'readerId': ?readerId,
      }, timeout: const Duration(seconds: 150));

  static Future<Map<String, dynamic>> chat({String? chatId, required String readerId, required String text, String? tarotReadingId}) =>
      call('sendChatMessage', {'chatId': ?chatId, 'readerId': readerId, 'text': text, 'tarotReadingId': ?tarotReadingId});

  static Future<Map<String, dynamic>> horoscope(String sign, String period) => call('getHoroscope', {'sign': sign, 'period': period});
  static Future<String> cardInsight(String cardId, bool reversed) async =>
      (await call('getCardInsight', {'cardId': cardId, 'reversed': reversed}))['text'] as String? ?? '';
  static Future<Map<String, dynamic>> dailyCard(String date) => call('getDailyCard', {'date': date});
  static Future<void> deleteMyData({required bool deleteAccount}) => call('deleteMyData', {'deleteAccount': deleteAccount});
  static Future<void> deletePalmPhotos() => call('deletePalmPhotos', {});
  static Future<void> devSetPremium(bool active) => call('devSetPremium', {'active': active});

  /// Asks the server to re-read the entitlement from RevenueCat and store it (see functions/src/account.ts).
  static Future<bool> syncPremium() async =>
      (await call('syncPremium', {}, timeout: const Duration(seconds: 20)))['active'] == true;

  /// Web (Dodo Payments): hosted checkout URL for 'monthly' or 'yearly'.
  static Future<String> createDodoCheckout(String plan) async =>
      (await call('createDodoCheckout', {'plan': plan}, timeout: const Duration(seconds: 30)))['url'] as String;

  /// Web (Dodo Payments): customer portal URL to manage/cancel the subscription.
  static Future<String> dodoPortal() async => (await call('dodoPortal', {}, timeout: const Duration(seconds: 30)))['url'] as String;

  /// Web (Dodo Payments): re-read the subscription from Dodo (after returning from checkout).
  static Future<bool> syncDodoPremium() async =>
      (await call('syncDodoPremium', {}, timeout: const Duration(seconds: 30)))['active'] == true;
}

Future<void> uploadPalm(String readingId, Uint8List bytes) async {
  // Server checks magic bytes; the extension in the path is fixed by the storage rules.
  final png = bytes.length > 4 && bytes[0] == 0x89 && bytes[1] == 0x50;
  await FirebaseStorage.instance
      .ref('palms/$currentUid/$readingId.jpg')
      .putData(bytes, SettableMetadata(contentType: png ? 'image/png' : 'image/jpeg'));
}

String todayKey([DateTime? d]) => (d ?? DateTime.now()).toIso8601String().substring(0, 10);

/// Cached horoscope per sign/period for the session.
final horoscopeProvider = FutureProvider.family<Map<String, dynamic>, (String, String)>((ref, key) async {
  ref.watch(userDocProvider.select((u) => u.value?.language));
  // Horoscope periods roll over at UTC midnight on the server; refetch then instead of showing yesterday's.
  final now = DateTime.now().toUtc();
  final rollover = Timer(DateTime.utc(now.year, now.month, now.day + 1, 0, 1).difference(now), ref.invalidateSelf);
  ref.onDispose(rollover.cancel);
  return Api.horoscope(key.$1, key.$2);
});

final dailyCardProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) throw ApiException('Not signed in');
  return Api.dailyCard(todayKey());
});
