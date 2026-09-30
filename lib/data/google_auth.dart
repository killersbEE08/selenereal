import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// OAuth *web* client of the Firebase project (client_type 3 in google-services.json).
/// Public by design: Google returns an ID token for this audience, which Firebase Auth verifies.
const _webClientId = '185397989989-9h0rcams4cjo7ascr63pr6o3koc5h51o.apps.googleusercontent.com';

class GoogleAuth {
  static Future<void>? _init;

  static Future<void> _ensureInit() => _init ??= GoogleSignIn.instance.initialize(serverClientId: _webClientId);

  /// Native Google account picker → Firebase sign-in (works for both new and returning users).
  ///
  /// If the current user is a guest, the Google account is *linked* to it so the guest's
  /// readings are kept. If that Google account already belongs to another Selene account,
  /// we sign into that account instead and [onSwitchedAccount] is called.
  ///
  /// Returns false if the user closed the picker.
  static Future<bool> signIn({void Function()? onSwitchedAccount}) async {
    if (kIsWeb) return _signInWeb(onSwitchedAccount);
    await _ensureInit();
    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled || e.code == GoogleSignInExceptionCode.interrupted) return false;
      throw FirebaseAuthException(code: 'google-sign-in-failed', message: 'Google sign-in failed. ${e.description ?? ''}'.trim());
    }
    final idToken = account.authentication.idToken;
    if (idToken == null) throw FirebaseAuthException(code: 'google-sign-in-failed', message: 'Google did not return a sign-in token. Please try again.');
    final cred = GoogleAuthProvider.credential(idToken: idToken);

    final auth = FirebaseAuth.instance;
    final current = auth.currentUser;
    if (current != null && current.isAnonymous) {
      try {
        await current.linkWithCredential(cred);
        return true;
      } on FirebaseAuthException catch (e) {
        if (e.code != 'credential-already-in-use' && e.code != 'email-already-in-use') rethrow;
        onSwitchedAccount?.call();
      }
    }
    await auth.signInWithCredential(cred);
    return true;
  }

  /// Web: Firebase's Google popup (same guest-linking behaviour as mobile).
  static Future<bool> _signInWeb(void Function()? onSwitchedAccount) async {
    final provider = GoogleAuthProvider()..setCustomParameters({'prompt': 'select_account'});
    final auth = FirebaseAuth.instance;
    try {
      final current = auth.currentUser;
      if (current != null && current.isAnonymous) {
        try {
          await current.linkWithPopup(provider);
          return true;
        } on FirebaseAuthException catch (e) {
          if (e.code != 'credential-already-in-use' && e.code != 'email-already-in-use') rethrow;
          onSwitchedAccount?.call();
          final cred = e.credential;
          if (cred != null) {
            await auth.signInWithCredential(cred);
            return true;
          }
        }
      }
      await auth.signInWithPopup(provider);
      return true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'popup-closed-by-user' || e.code == 'cancelled-popup-request' || e.code == 'user-cancelled') return false;
      if (e.code == 'popup-blocked') {
        throw FirebaseAuthException(code: e.code, message: 'Your browser blocked the Google sign-in window. Allow pop-ups for this site and try again.');
      }
      rethrow;
    }
  }

  /// Clears the cached Google account so the picker shows again on next sign-in.
  static Future<void> signOut() async {
    if (kIsWeb) return; // the popup always shows the account chooser (prompt=select_account)
    try {
      await _ensureInit();
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Not signed in with Google / plugin unavailable: nothing to clear.
    }
  }
}
