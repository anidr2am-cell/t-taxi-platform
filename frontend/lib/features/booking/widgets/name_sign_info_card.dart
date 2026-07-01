import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';

/// Placeholder for a future name-sign reference image.
/// Set [assetPath] when the asset is available and register it in pubspec.yaml.
class NameSignInfoAssets {
  NameSignInfoAssets._();

  static const String? assetPath = null;
}

class NameSignInfoCard extends StatelessWidget {
  final bool visible;

  const NameSignInfoCard({super.key, required this.visible});

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: visible
          ? Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _NameSignInfoCardBody(l10n: context.l10n),
            )
          : const SizedBox.shrink(),
    );
  }
}

class _NameSignInfoCardBody extends StatelessWidget {
  final AppLocalizations l10n;

  const _NameSignInfoCardBody({required this.l10n});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final stackVertically = width < 360;

    final image = _ImagePlaceholder();
    final text = _DescriptionText(l10n: l10n);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTokens.primaryLight,
        borderRadius: AppTokens.borderRadiusMd,
        border: Border.all(color: AppTokens.border),
      ),
      child: stackVertically
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: 72, child: image),
                const SizedBox(height: 10),
                text,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: width * 0.4 - 26, child: image),
                const SizedBox(width: 10),
                Expanded(child: text),
              ],
            ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final assetPath = NameSignInfoAssets.assetPath;
    return ClipRRect(
      borderRadius: AppTokens.borderRadiusSm,
      child: Container(
        color: AppTokens.surfaceMuted,
        child: assetPath == null
            ? const Center(
                child: Icon(
                  Icons.badge_outlined,
                  color: AppTokens.textSecondary,
                  size: 28,
                ),
              )
            : Image.asset(
                assetPath,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
      ),
    );
  }
}

class _DescriptionText extends StatelessWidget {
  final AppLocalizations l10n;

  const _DescriptionText({required this.l10n});

  @override
  Widget build(BuildContext context) {
    final price = l10n.t('name_sign_service_price_highlight');
    final gate = l10n.t('name_sign_service_gate_highlight');

    return RichText(
      text: TextSpan(
        style: const TextStyle(
          color: AppTokens.textPrimary,
          fontSize: 13,
          height: 1.45,
        ),
        children: [
          TextSpan(text: l10n.t('name_sign_info_before_price')),
          TextSpan(
            text: price,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppTokens.accent,
            ),
          ),
          TextSpan(text: l10n.t('name_sign_info_after_price')),
          TextSpan(
            text: gate,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppTokens.primaryDark,
            ),
          ),
          TextSpan(text: l10n.t('name_sign_info_after_gate')),
        ],
      ),
    );
  }
}
