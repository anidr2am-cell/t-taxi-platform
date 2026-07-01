import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_tokens.dart';

class PwaInstallBanner extends StatefulWidget {
  const PwaInstallBanner({super.key});

  @override
  State<PwaInstallBanner> createState() => _PwaInstallBannerState();
}

class _PwaInstallBannerState extends State<PwaInstallBanner> {
  bool _dismissed = false;
  bool _canInstall = false;

  @override
  void initState() {
    super.initState();
    _checkInstallPrompt();
  }

  void _checkInstallPrompt() {
    // PWA install prompt is handled via browser beforeinstallprompt event on web
    // Flutter web doesn't expose this directly; show banner as install encouragement
    setState(() => _canInstall = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed || !_canInstall) return const SizedBox.shrink();

    final l10n = context.l10n;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTokens.accentLight,
        borderRadius: AppTokens.borderRadiusMd,
        border: Border.all(color: AppTokens.accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.install_mobile, color: AppTokens.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.t('install_app'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTokens.textPrimary,
                  ),
                ),
                Text(
                  l10n.t('install_app_desc'),
                  style: const TextStyle(fontSize: 12, color: AppTokens.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => setState(() => _dismissed = true),
          ),
        ],
      ),
    );
  }
}
