import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../core/astro.dart';
import '../core/theme.dart';
import '../core/validators.dart';
import '../core/widgets.dart';
import '../data/api.dart';
import '../data/google_auth.dart';
import 'auth.dart';
import 'legal.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  /// Upgrades a guest account to email/password, keeping the same uid (and all readings).
  /// The new email must be verified before the account can be used again (router + rules).
  Future<void> _linkAccount(BuildContext context) async {
    final email = TextEditingController(), pass = TextEditingController();
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Save your account'),
        content: Form(
          key: form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                inputFormatters: Validators.emailFormatters,
                validator: Validators.email,
                decoration: const InputDecoration(hintText: 'Email'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: pass,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                inputFormatters: Validators.passwordFormatters,
                validator: Validators.newPassword,
                decoration: const InputDecoration(hintText: 'Password', helperText: '8+ characters: upper, lower, number, symbol', helperMaxLines: 2, errorMaxLines: 3),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => (form.currentState?.validate() ?? false) ? Navigator.pop(c, true) : null, child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final cred = EmailAuthProvider.credential(email: email.text.trim(), password: pass.text);
      final linked = await FirebaseAuth.instance.currentUser!.linkWithCredential(cred);
      await linked.user?.sendEmailVerification();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account saved. Check your inbox to verify your email next time you sign in.')));
      }
    } on FirebaseAuthException catch (e) {
      final msg = switch (e.code) {
        'email-already-in-use' || 'credential-already-in-use' => 'That email can’t be used. Try another or sign in instead.',
        'weak-password' || 'password-does-not-meet-requirements' => 'Choose a stronger password.',
        'invalid-email' => 'That email address looks invalid.',
        'too-many-requests' => 'Too many attempts. Please wait a few minutes.',
        _ => 'Could not save your account. Please try again.',
      };
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<bool> _confirm(BuildContext context, String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: Text(action, style: const TextStyle(color: AppColors.error))),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userDocProvider).value;
    final auth = FirebaseAuth.instance.currentUser;
    final premium = ref.watch(isPremiumProvider);
    final sign = user?.zodiac == null ? null : signById(user!.zodiac);

    Widget tile(String icon, String title, {String? subtitle, VoidCallback? onTap, Widget? trailing, Color? color}) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GlowCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            onTap: onTap,
            child: Row(children: [
              IconBadge(icon, color: color ?? AppColors.glow, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: AppType.ui(size: 14.5, weight: FontWeight.w600, color: color == AppColors.error ? AppColors.error : AppColors.text)),
                  if (subtitle != null) Text(subtitle, style: AppType.ui(size: 12, weight: FontWeight.w400, color: AppColors.textSecondary)),
                ]),
              ),
              trailing ?? const AppIcon(Ic.right, color: AppColors.textMuted, size: 18),
            ]),
          ),
        );

    Widget birthRow(String icon, String label, String? value) {
      final has = value != null && value.isNotEmpty;
      return Row(children: [
        AppIcon(icon, size: 18, color: AppColors.gold),
        const SizedBox(width: 10),
        Text(label, style: AppType.ui(size: 13, weight: FontWeight.w500, color: AppColors.textSecondary)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            has ? value : 'Not set',
            textAlign: TextAlign.right,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.ui(size: 13.5, weight: FontWeight.w600, color: has ? AppColors.text : AppColors.textMuted),
          ),
        ),
      ]);
    }

    final dobDate = user?.dob == null ? null : DateTime.tryParse(user!.dob!);
    final bornLabel = dobDate != null ? DateFormat.yMMMMd().format(dobDate) : user?.dob;

    return SafeArea(
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 110), children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(2.5),
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.cta),
            child: CircleAvatar(radius: 38, backgroundColor: AppColors.bg, backgroundImage: AssetImage(sign?.image ?? 'assets/images/app_icon.webp')),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(user?.displayName.isNotEmpty == true ? user!.displayName : 'Stargazer', style: Theme.of(context).textTheme.headlineSmall),
              Text(auth?.isAnonymous == true ? 'Guest account' : (auth?.email ?? ''), style: AppType.ui(size: 12.5, weight: FontWeight.w500, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (sign != null) Tag('${sign.name} · ${sign.range}', color: AppColors.gold, icon: Ic.star),
                if (premium) const PremiumBadge(),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 20),
        if (user != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GlowCard(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileSetupScreen(editing: true))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('Birth details', style: AppType.ui(size: 13, weight: FontWeight.w700)),
                  const Spacer(),
                  const AppIcon(Ic.edit, size: 15, color: AppColors.textMuted),
                ]),
                const SizedBox(height: 12),
                birthRow(Ic.cake, 'Date', bornLabel),
                const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1)),
                birthRow(Ic.time, 'Time', user.birthTime),
                const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1)),
                birthRow(Ic.location, 'Place', user.birthPlace),
              ]),
            ),
          ),
        if (!premium)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GradientButton(label: 'Go Premium', icon: Ic.crownFill, onPressed: () => context.push('/paywall')),
          ),
        if (auth?.isAnonymous == true) ...[
          tile(Ic.shield, 'Save with Google', subtitle: 'Keep your readings safe with your Google account', color: AppColors.gold, onTap: () async {
            final messenger = ScaffoldMessenger.of(context);
            var switched = false;
            try {
              final ok = await GoogleAuth.signIn(onSwitchedAccount: () => switched = true);
              if (ok) {
                messenger.showSnackBar(SnackBar(
                    content: Text(switched ? 'Signed in to your existing Google account.' : 'Account saved. Sign in with Google anytime.')));
              }
            } on FirebaseAuthException catch (e) {
              messenger.showSnackBar(SnackBar(content: Text(e.message ?? 'Google sign-in failed.')));
            }
          }),
          tile(Ic.mail, 'Save with email', subtitle: 'Add an email so you never lose your readings', color: AppColors.gold, onTap: () => _linkAccount(context)),
        ],
        tile(Ic.edit, 'Edit Profile', subtitle: 'Name, birthday, focus areas, language',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileSetupScreen(editing: true)))),
        tile(Ic.book, 'My Readings', onTap: () => context.push('/readings')),
        tile(Ic.bookmark, 'My Card Collection', onTap: () => context.push('/cards?collection=1')),
        tile(Ic.grid, 'My Spreads', onTap: () => context.push('/spreads')),
        tile(
          Ic.pic,
          'Keep palm photos in the cloud',
          subtitle: 'Off: photos are deleted from our servers right after your reading',
          trailing: Switch(
            value: user?.keepPalmPhotos ?? false,
            onChanged: (v) => userRef().set({'settings': {'keepPalmPhotos': v}}, SetOptions(merge: true)),
          ),
        ),
        tile(Ic.pic, 'Delete my palm photos', onTap: () async {
          if (await _confirm(context, 'Delete palm photos?', 'All palm photos stored in the cloud will be deleted.', 'Delete')) {
            try {
              await Api.deletePalmPhotos();
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Palm photos deleted.')));
            } catch (e) {
              if (context.mounted) showApiError(context, e);
            }
          }
        }),
        tile(Ic.book, 'Privacy policy', onTap: () => openLegal(context, LegalLinks.privacy)),
        tile(Ic.shield, 'Terms of use', onTap: () => openLegal(context, LegalLinks.terms)),
        tile(Ic.mail, 'Contact support', subtitle: LegalLinks.supportEmail, onTap: () => openLegal(context, LegalLinks.supportMailto)),
        tile(Ic.info, 'About Selene', onTap: () => showAboutSelene(context)),
        const SizedBox(height: 8),
        tile(Ic.exit, 'Sign out', onTap: () async {
          if (auth?.isAnonymous == true &&
              !await _confirm(context, 'Sign out of guest account?', 'Guest readings cannot be recovered after signing out.', 'Sign out')) {
            return;
          }
          await GoogleAuth.signOut();
          await FirebaseAuth.instance.signOut();
        }),
        tile(Ic.delete, 'Delete account & data', color: AppColors.error, onTap: () async {
          if (await _confirm(context, 'Delete everything?', 'Your account, readings, chats and photos will be permanently deleted.', 'Delete')) {
            try {
              await Api.deleteMyData(deleteAccount: true);
              await GoogleAuth.signOut();
              await FirebaseAuth.instance.signOut();
            } catch (e) {
              if (context.mounted) showApiError(context, e);
            }
          }
        }),
        const DisclaimerText(),
      ]),
    );
  }
}
