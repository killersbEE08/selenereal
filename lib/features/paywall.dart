import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../app.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../data/api.dart';
import '../data/billing.dart';
import 'legal.dart';

final _offeringProvider = FutureProvider.autoDispose<Offering?>((ref) => Billing.currentOffering());

/// Paywall. Purchases go through RevenueCat → Google Play / App Store. Premium is granted
/// only by the server (RevenueCat webhook or the `syncPremium` callable → Firestore), never by
/// the app itself.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key, this.checkoutReturn = false});

  /// Web: the browser just came back from Dodo checkout.
  final bool checkoutReturn;
  @override
  ConsumerState<PaywallScreen> createState() => _PaywallState();
}

enum _Unlock { idle, unlocking, stuck }

class _PaywallState extends ConsumerState<PaywallScreen> {
  Package? _selected;
  String _webPlan = 'yearly';
  bool _busy = false;
  _Unlock _unlock = _Unlock.idle;
  Timer? _giveUp;

  static const _benefits = [
    (Ic.hand, 'Unlimited palm readings, for you and loved ones'),
    (Ic.search, 'Full line analysis, mounts and personality'),
    (Ic.chat, 'Unlimited chat (free: 3 messages a day)'),
    (Ic.cards, 'Unlimited AI tarot and every premium spread'),
    (Ic.magicHat, 'Unlock all 6 AI readers'),
    (Ic.calendar, 'Weekly, monthly and yearly horoscopes'),
    (Ic.pencil, 'Design your own custom spreads'),
  ];

  @override
  void initState() {
    super.initState();
    // Someone who already owns Premium (e.g. a dashboard grant) but lands here should unlock
    // silently instead of being asked to pay again.
    if (!useEmulator && Billing.available) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!ref.read(isPremiumProvider) && await Billing.hasPremiumEntitlement() && mounted) _unlockFromServer();
      });
    }
    if (kIsWeb && widget.checkoutReturn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !ref.read(isPremiumProvider)) _unlockFromServer();
      });
    }
  }

  @override
  void dispose() {
    _giveUp?.cancel();
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  /// The store confirmed the entitlement; make the server write it (instead of only waiting
  /// for the webhook) and stop waiting after a bounded time so the screen can never spin forever.
  Future<void> _unlockFromServer() async {
    setState(() => _unlock = _Unlock.unlocking);
    _giveUp?.cancel();
    _giveUp = Timer(const Duration(seconds: 25), () {
      if (mounted && !ref.read(isPremiumProvider)) setState(() => _unlock = _Unlock.stuck);
    });
    try {
      final active = kIsWeb ? await Api.syncDodoPremium() : await Api.syncPremium();
      if (!mounted) return;
      // Web: the payment may still be processing; keep waiting for the webhook until the timer ends.
      if (!active && !kIsWeb && !ref.read(isPremiumProvider)) {
        _giveUp?.cancel();
        setState(() => _unlock = _Unlock.stuck);
      }
      // When active, the user-doc stream flips isPremiumProvider and the success card shows.
    } catch (e) {
      if (!mounted) return;
      _giveUp?.cancel();
      setState(() => _unlock = _Unlock.stuck);
      showApiError(context, e);
    }
  }

  Future<void> _webCheckout() async {
    setState(() => _busy = true);
    try {
      await WebBilling.checkout(_webPlan); // navigates away on success
    } on BillingException catch (e) {
      if (mounted) _snack(e.message);
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _webManage() async {
    try {
      await WebBilling.manage();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  void _close() => context.canPop() ? context.pop() : context.go('/home');

  Future<void> _devUnlock() async {
    setState(() => _busy = true);
    try {
      await Api.devSetPremium(true);
      if (mounted) _snack('Premium unlocked (test mode).');
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _buy(Package p) async {
    setState(() => _busy = true);
    try {
      final active = await Billing.buy(p);
      if (!mounted) return;
      if (active) await _unlockFromServer();
    } on BillingException catch (e) {
      if (mounted) _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      final active = await Billing.restore();
      if (!mounted) return;
      if (active) {
        await _unlockFromServer();
      } else {
        _snack('No active Premium found for this store account.');
      }
    } on BillingException catch (e) {
      if (mounted) _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _label(Package p) => switch (p.packageType) {
        PackageType.annual => 'Yearly',
        PackageType.weekly => 'Weekly',
        PackageType.monthly => 'Monthly',
        PackageType.lifetime => 'Lifetime',
        _ => p.storeProduct.title,
      };

  String _detail(Package p) {
    final price = p.storeProduct.priceString;
    final period = switch (p.packageType) {
      PackageType.annual => ' / year',
      PackageType.weekly => ' / week',
      PackageType.monthly => ' / month',
      _ => '',
    };
    final trial = p.storeProduct.introductoryPrice;
    return trial != null && trial.price == 0 ? 'Free trial, then $price$period' : '$price$period';
  }

  @override
  Widget build(BuildContext context) {
    final premium = ref.watch(isPremiumProvider);
    if (premium) _giveUp?.cancel();
    final offering = ref.watch(_offeringProvider);
    return SubPage(
      child: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
          Align(alignment: Alignment.topRight, child: CircleIconButton(icon: Ic.close, tooltip: 'Close', onTap: _close)),
          SizedBox(
            height: 200,
            child: Stack(alignment: Alignment.center, children: [
              Container(
                width: 240,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [AppColors.gold.withValues(alpha: 0.26), AppColors.primary.withValues(alpha: 0.08), Colors.transparent], stops: const [0, 0.55, 1]),
                ),
              ),
              Image.asset('assets/images/fortune_teller.webp', height: 200, fit: BoxFit.contain, excludeFromSemantics: true),
            ]),
          ),
          const SizedBox(height: 8),
          Center(child: Text('SELENE PREMIUM', style: AppType.overline(color: AppColors.gold))),
          const SizedBox(height: 6),
          const Center(child: GradientHeading('Unlock deeper', 'insight', size: 32, textAlign: TextAlign.center)),
          const SizedBox(height: 20),
          GlowCard(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Column(children: [
              for (final b in _benefits)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(children: [
                    IconBadge(b.$1, color: AppColors.gold, size: 34),
                    const SizedBox(width: 12),
                    Expanded(child: Text(b.$2, style: AppType.ui(size: 14.5, weight: FontWeight.w500))),
                    const AppIcon(Ic.checkCircleFill, color: AppColors.success, size: 20),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 18),
          if (premium)
            GlowCard(
              selected: true,
              child: Column(children: [
                const AppIcon(Ic.crownFill, color: AppColors.gold, size: 34),
                const SizedBox(height: 8),
                Text('You are Premium', style: AppType.display(size: 22, color: AppColors.gold)),
                const SizedBox(height: 4),
                Text(
                    ref.watch(userDocProvider).value?.premiumSource == 'dodo'
                        ? 'Everything is unlocked. Manage or cancel your web subscription anytime.'
                        : 'Everything is unlocked. Manage or cancel anytime in Google Play → Subscriptions.',
                    textAlign: TextAlign.center, style: AppType.ui(size: 12.5, weight: FontWeight.w400, color: AppColors.textSecondary)),
                const SizedBox(height: 14),
                GradientButton(label: 'Start exploring', icon: Ic.sparkles, onPressed: _close),
                if (ref.watch(userDocProvider).value?.premiumSource == 'dodo')
                  TextButton(onPressed: _webManage, child: const Text('Manage subscription')),
                if (useEmulator)
                  TextButton(onPressed: () => Api.devSetPremium(false), child: const Text('Turn off (test mode)')),
              ]),
            )
          else if (_unlock == _Unlock.unlocking)
            GlowCard(
              child: Column(children: [
                const Loading(),
                const SizedBox(height: 12),
                Text('Purchase confirmed. Unlocking Premium…', textAlign: TextAlign.center, style: AppType.ui(size: 14.5, weight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('This usually takes a few seconds.', style: AppType.ui(size: 12.5, weight: FontWeight.w400, color: AppColors.textSecondary)),
              ]),
            )
          else if (_unlock == _Unlock.stuck)
            GlowCard(
              child: Column(children: [
                const AppIcon(Ic.info, color: AppColors.warning, size: 28),
                const SizedBox(height: 8),
                Text('Your purchase is safe', style: AppType.ui(size: 16, weight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  "The store confirmed it but we couldn't activate Premium on your account yet. Check your connection and try again. "
                  'Make sure you are signed in with the same account you purchased with.',
                  textAlign: TextAlign.center,
                  style: AppType.ui(size: 12.5, weight: FontWeight.w400, color: AppColors.textSecondary, height: 1.5),
                ),
                const SizedBox(height: 14),
                GradientButton(label: 'Try again', icon: Ic.refresh, trailing: false, onPressed: _unlockFromServer),
              ]),
            )
          else if (useEmulator)
            GradientButton(label: 'Unlock Premium (test mode)', loading: _busy, onPressed: _devUnlock)
          else if (WebBilling.available)
            Column(children: [
              _Plan(
                title: 'Yearly',
                price: WebBilling.yearlyPrice.isEmpty ? 'Billed yearly' : '${WebBilling.yearlyPrice} / year',
                badge: 'Best value',
                selected: _webPlan == 'yearly',
                onTap: () => setState(() => _webPlan = 'yearly'),
              ),
              const SizedBox(height: 10),
              _Plan(
                title: 'Monthly',
                price: WebBilling.monthlyPrice.isEmpty ? 'Billed monthly' : '${WebBilling.monthlyPrice} / month',
                selected: _webPlan == 'monthly',
                onTap: () => setState(() => _webPlan = 'monthly'),
              ),
              const SizedBox(height: 16),
              GradientButton(label: 'Continue to secure checkout', icon: Ic.crownFill, loading: _busy, onPressed: _webCheckout),
            ])
          else if (!Billing.available)
            GlowCard(child: Text('Subscriptions are coming soon.', textAlign: TextAlign.center, style: AppType.ui(size: 14)))
          else
            offering.when(
              loading: () => const SizedBox(height: 120, child: Loading()),
              error: (e, _) => MascotMessage(title: 'Store unavailable', message: 'Could not load prices. Check your connection.', action: 'Retry', onAction: () => ref.invalidate(_offeringProvider)),
              data: (o) {
                final pkgs = o?.availablePackages ?? const <Package>[];
                if (pkgs.isEmpty) return GlowCard(child: Text('No plans available right now. Please try again later.', style: AppType.ui(size: 14)));
                final sel = _selected ?? pkgs.firstWhere((p) => p.packageType == PackageType.annual, orElse: () => pkgs.first);
                return Column(children: [
                  for (final p in pkgs) ...[
                    _Plan(
                      title: _label(p),
                      price: _detail(p),
                      badge: p.packageType == PackageType.annual ? 'Best value' : null,
                      selected: p.identifier == sel.identifier,
                      onTap: () => setState(() => _selected = p),
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 6),
                  GradientButton(label: 'Continue', icon: Ic.crownFill, loading: _busy, onPressed: () => _buy(sel)),
                ]);
              },
            ),
          if (!premium && !useEmulator && Billing.available && _unlock != _Unlock.unlocking)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: TextButton(
                onPressed: _busy ? null : _restore,
                child: Text('Restore purchases', style: AppType.ui(size: 13.5, weight: FontWeight.w600, color: AppColors.textSecondary)),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            kIsWeb
                ? 'Payments are processed securely by Dodo Payments, our merchant of record. Subscriptions renew automatically until cancelled; cancel anytime from "Manage subscription".'
                : 'Payment is charged to your Google Play account. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the period in Google Play → Subscriptions.',
            textAlign: TextAlign.center,
            style: AppType.ui(size: 11, weight: FontWeight.w400, color: AppColors.textMuted, height: 1.45),
          ),
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                onPressed: () => openLegal(context, LegalLinks.terms),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: const Size(0, 44)),
                child: Text('Terms', style: AppType.ui(size: 12, weight: FontWeight.w700, color: AppColors.glow)),
              ),
              Text('·', style: AppType.ui(size: 12, color: AppColors.textMuted)),
              TextButton(
                onPressed: () => openLegal(context, LegalLinks.privacy),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: const Size(0, 44)),
                child: Text('Privacy Policy', style: AppType.ui(size: 12, weight: FontWeight.w700, color: AppColors.glow)),
              ),
            ],
          ),
        ]),
      ),
    );
  }
}

class _Plan extends StatelessWidget {
  const _Plan({required this.title, required this.price, required this.selected, required this.onTap, this.badge});
  final String title, price;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        button: true,
        child: GlowCard(
          selected: selected,
          onTap: onTap,
          child: Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: selected ? AppColors.cta : null,
                border: selected ? null : Border.all(color: AppColors.borderStrong, width: 1.6),
              ),
              child: selected ? const Center(child: AppIcon(Ic.check, size: 14, color: AppColors.onGold)) : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: AppType.ui(size: 16, weight: FontWeight.w700)),
                Text(price, style: AppType.ui(size: 12.5, weight: FontWeight.w500, color: AppColors.textSecondary)),
              ]),
            ),
            if (badge != null) PremiumBadge(label: badge!),
          ]),
        ),
      );
}
