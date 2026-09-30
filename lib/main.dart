import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/api.dart';
import 'data/billing.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Fonts ship in assets/google_fonts, so never hit the network for them (works offline, no flash).
  GoogleFonts.config.allowRuntimeFetching = false;
  // A broken widget shows a calm, on-brand message instead of a grey box or raw error text.
  // Details go to Crashlytics, never to the user.
  ErrorWidget.builder = (details) => const Material(
        color: Color(0xFF0A0916),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Text(
              'Something went wrong on this screen.\nPlease go back and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFFB9B2D6), fontSize: 14, height: 1.5),
            ),
          ),
        ),
      );
  if (!kIsWeb) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0A0916),
    ));
  }
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Crash reporting (release only; debug/emulator builds keep errors in the console).
  // Crashlytics has no web SDK, so web errors stay in the browser console.
  final report = kReleaseMode && !useEmulator && !kIsWeb;
  if (!kIsWeb) await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(report);
  if (report) {
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
    FirebaseAuth.instance.authStateChanges().listen((u) => FirebaseCrashlytics.instance.setUserIdentifier(u?.uid ?? ''));
  }

  if (useEmulator) {
    await FirebaseAuth.instance.useAuthEmulator(emulatorHost, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(emulatorHost, 8080);
    await FirebaseStorage.instance.useStorageEmulator(emulatorHost, 9199);
    FirebaseFunctions.instanceFor(region: functionsRegion).useFunctionsEmulator(emulatorHost, 5001);
  } else {
    // Production: Play Integrity / App Attest.
    // Sideloaded test builds pass --dart-define=APPCHECK_DEBUG_TOKEN=<token registered in Firebase>
    // so they work without the Play Store. Never ship a store build with this flag.
    // Web: reCAPTCHA v3 site key, passed at build time: --dart-define=RECAPTCHA_SITE_KEY=<key>.
    const testToken = String.fromEnvironment('APPCHECK_DEBUG_TOKEN');
    const recaptchaKey = String.fromEnvironment('RECAPTCHA_SITE_KEY');
    const debug = !kReleaseMode || testToken != '';
    if (kIsWeb && recaptchaKey.isEmpty) {
      debugPrint('RECAPTCHA_SITE_KEY not set: App Check is off, enforced backend calls will be rejected.');
    } else {
      await FirebaseAppCheck.instance.activate(
        providerWeb: kIsWeb ? ReCaptchaV3Provider(recaptchaKey) : null,
        providerAndroid: debug ? AndroidDebugProvider(debugToken: testToken.isEmpty ? null : testToken) : const AndroidPlayIntegrityProvider(),
        providerApple: debug ? const AppleDebugProvider() : const AppleAppAttestWithDeviceCheckFallbackProvider(),
      );
    }
  }

  final prefs = await SharedPreferences.getInstance();
  if (!useEmulator) {
    // Store billing is unavailable on emulators without Play; never block app start on it.
    Billing.init().catchError((Object e, StackTrace s) {
      debugPrint('Billing init failed: $e');
      if (report) FirebaseCrashlytics.instance.recordError(e, s, reason: 'Billing.init');
    });
  }
  runApp(ProviderScope(
    overrides: [prefsProvider.overrideWithValue(prefs)],
    child: const SeleneApp(),
  ));
}
