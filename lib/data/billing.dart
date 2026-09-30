import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';

/// Web Premium through Dodo Payments' hosted checkout. The server creates the session and is the
/// only writer of users/{uid}.premium (webhook or `syncDodoPremium`).
class WebBilling {
  /// Shown prices; set to match the Dodo products: --dart-define=DODO_PRICE_MONTHLY="₹199" etc.
  static const monthlyPrice = String.fromEnvironment('DODO_PRICE_MONTHLY');
  static const yearlyPrice = String.fromEnvironment('DODO_PRICE_YEARLY');
  static bool get available => kIsWeb && !const bool.fromEnvironment('DODO_DISABLED');

  /// Sends the browser to Dodo checkout (same tab; Dodo returns to /#/paywall?checkout=return).
  static Future<void> checkout(String plan) async {
    final url = await Api.createDodoCheckout(plan);
    if (!await launchUrl(Uri.parse(url), webOnlyWindowName: '_self')) {
      throw BillingException('Could not open checkout. Please allow pop-ups and try again.');
    }
  }

  /// Opens Dodo's customer portal (cancel, change card, invoices).
  static Future<void> manage() async {
    final url = await Api.dodoPortal();
    await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
  }
}

/// RevenueCat public SDK keys (safe to ship; they can only make purchases, not grant them).
/// Override at build time if needed: --dart-define=RC_ANDROID_KEY=goog_xxx --dart-define=RC_IOS_KEY=appl_xxx
const _androidKey = String.fromEnvironment('RC_ANDROID_KEY', defaultValue: 'goog_KXURCAVVvdWbgFWXqjHbTnBmcXj');
const _iosKey = String.fromEnvironment('RC_IOS_KEY');

/// Entitlement identifier created in the RevenueCat dashboard.
const premiumEntitlement = 'premium';

class Billing {
  static bool _configured = false;
  static StreamSubscription<User?>? _authSub;

  // Web sells Premium through Dodo Payments (see WebBilling), not RevenueCat.
  static String get _key => kIsWeb ? '' : (defaultTargetPlatform == TargetPlatform.iOS ? _iosKey : _androidKey);
  static bool get available => _key.isNotEmpty;

  /// Configures RevenueCat and keeps its app user id equal to the Firebase uid,
  /// so the server webhook knows which Firestore user bought Premium.
  static Future<void> init() async {
    if (!available || _configured) return;
    await Purchases.setLogLevel(kReleaseMode ? LogLevel.warn : LogLevel.info);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    await Purchases.configure(PurchasesConfiguration(_key)..appUserID = uid);
    _configured = true;
    _authSub = FirebaseAuth.instance.authStateChanges().listen((u) async {
      try {
        if (u != null) {
          if ((await Purchases.appUserID) != u.uid) await Purchases.logIn(u.uid);
          // Self-heal: if the store says Premium but the webhook never reached us (dashboard
          // grants, missed deliveries), let the server pull the entitlement from RevenueCat.
          if (await hasPremiumEntitlement()) await Api.syncPremium();
        } else if (!(await Purchases.isAnonymous)) {
          await Purchases.logOut();
        }
      } catch (e) {
        debugPrint('RevenueCat identity sync failed: $e');
      }
    });
  }

  static Future<void> dispose() async => _authSub?.cancel();

  static Future<Offering?> currentOffering() async {
    if (!_configured) return null;
    return (await Purchases.getOfferings().timeout(const Duration(seconds: 15))).current;
  }

  /// True if RevenueCat (client side) currently reports the Premium entitlement for this user.
  static Future<bool> hasPremiumEntitlement() async {
    if (!_configured) return false;
    try {
      await _syncIdentity();
      final info = await Purchases.getCustomerInfo().timeout(const Duration(seconds: 15));
      return info.entitlements.active.containsKey(premiumEntitlement);
    } catch (e) {
      debugPrint('RevenueCat customer info failed: $e');
      return false;
    }
  }

  /// Makes sure RevenueCat's app user id is the Firebase uid *before* a purchase/restore.
  /// Otherwise a fast tap could attribute the purchase to an anonymous RevenueCat id, which the
  /// server webhook ignores (Premium would never unlock).
  static Future<void> _syncIdentity() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw BillingException('Please sign in before purchasing.');
    if ((await Purchases.appUserID) != uid) await Purchases.logIn(uid);
  }

  /// Returns true if the purchase completed and Premium is active on RevenueCat.
  /// Returns false if the user cancelled. Throws [BillingException] on real errors.
  static Future<bool> buy(Package p) async {
    try {
      await _syncIdentity();
      final r = await Purchases.purchase(PurchaseParams.package(p));
      return r.customerInfo.entitlements.active.containsKey(premiumEntitlement);
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) return false;
      throw BillingException(_message(code, e));
    }
  }

  /// Restores purchases for this store account. Returns true if Premium is active.
  static Future<bool> restore() async {
    try {
      await _syncIdentity();
      final info = await Purchases.restorePurchases().timeout(const Duration(seconds: 30));
      return info.entitlements.active.containsKey(premiumEntitlement);
    } on TimeoutException {
      throw BillingException('The store is taking too long to respond. Please try again.');
    } on PlatformException catch (e) {
      throw BillingException(_message(PurchasesErrorHelper.getErrorCode(e), e));
    }
  }

  static String _message(PurchasesErrorCode code, PlatformException e) => switch (code) {
        PurchasesErrorCode.networkError => "You're offline. Check your connection and try again.",
        PurchasesErrorCode.purchaseNotAllowedError => 'Purchases are not allowed on this device.',
        PurchasesErrorCode.paymentPendingError => 'Your payment is pending. Premium will unlock once it completes.',
        PurchasesErrorCode.productAlreadyPurchasedError => 'You already own this. Tap "Restore Purchases".',
        PurchasesErrorCode.storeProblemError => 'The store had a problem. Please try again in a moment.',
        _ => e.message ?? 'Purchase failed. Please try again.',
      };
}

class BillingException implements Exception {
  BillingException(this.message);
  final String message;
  @override
  String toString() => message;
}
