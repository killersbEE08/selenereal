import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';
import '../core/widgets.dart';

/// Public legal/support links (Firebase Hosting, see store_listing/legal).
/// Override at build time with --dart-define=SUPPORT_EMAIL=you@domain.com
abstract final class LegalLinks {
  static const _base = 'https://selene-ai-34251.web.app';
  static final privacy = Uri.parse('$_base/privacy_policy.html');
  static final terms = Uri.parse('$_base/terms_of_use.html');
  static final deleteAccount = Uri.parse('$_base/delete_account.html');
  static const supportEmail = String.fromEnvironment('SUPPORT_EMAIL', defaultValue: 'princekumarmandal78@gmail.com');
  static final supportMailto = Uri(scheme: 'mailto', path: supportEmail, query: 'subject=Selene%20support');
}

/// Opens a legal page in an in-app browser tab (mail links go to the mail app).
Future<void> openLegal(BuildContext context, Uri url) async {
  final ok = await launchUrl(url, mode: url.scheme == 'mailto' ? LaunchMode.externalApplication : LaunchMode.inAppBrowserView).catchError((_) => false);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(url.scheme == 'mailto' ? 'Email us at ${LegalLinks.supportEmail}' : 'Could not open the page. Please try again.')));
  }
}

/// Simple branded About sheet: what Selene is, the disclaimer, version. No licence wall.
Future<void> showAboutSelene(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AboutSheet(),
    );

class _AboutSheet extends StatelessWidget {
  const _AboutSheet();
  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ClipRRect(borderRadius: BorderRadius.circular(22), child: Image.asset('assets/images/app_icon.webp', width: 72, excludeFromSemantics: true)),
            const SizedBox(height: 12),
            Text('Selene', style: AppType.display(size: 26, weight: FontWeight.w500)),
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (_, s) => Text(s.hasData ? 'Version ${s.data!.version} (${s.data!.buildNumber})' : ' ',
                  style: AppType.ui(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
            ),
            const SizedBox(height: 16),
            Text('Tarot, horoscopes and palm reading, written for you by AI.',
                textAlign: TextAlign.center, style: AppType.ui(size: 14, weight: FontWeight.w400, color: AppColors.textSecondary, height: 1.5)),
            const SizedBox(height: 16),
            GlowCard(
              padding: const EdgeInsets.all(14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const AppIcon(Ic.info, size: 18, color: AppColors.gold),
                const SizedBox(width: 10),
                Expanded(child: Text(disclaimer, style: AppType.ui(size: 13, weight: FontWeight.w500, color: AppColors.text, height: 1.45))),
              ]),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinePillButton(label: 'Privacy', icon: Ic.book, onPressed: () => openLegal(context, LegalLinks.privacy))),
              const SizedBox(width: 10),
              Expanded(child: OutlinePillButton(label: 'Terms', icon: Ic.shield, onPressed: () => openLegal(context, LegalLinks.terms))),
            ]),
            const SizedBox(height: 14),
            Text('Made with care in India', style: AppType.ui(size: 11.5, weight: FontWeight.w500, color: AppColors.textMuted)),
          ]),
        ),
      );
}
