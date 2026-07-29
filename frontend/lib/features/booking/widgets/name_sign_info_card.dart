import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';

/// Placeholder for a future name-sign reference image.
/// Set [assetPath] when the asset is available and register it in pubspec.yaml.
class NameSignInfoAssets {
  NameSignInfoAssets._();

  static const String assetPath = 'assets/images/name_sign_example.png';

  /// Source asset is 1086×1448 (portrait).
  static const double aspectRatio = 1086 / 1448;
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
          ? const Padding(
              padding: EdgeInsets.only(top: 8),
              child: _NameSignInfoCardBody(),
            )
          : const SizedBox.shrink(),
    );
  }
}

class _NameSignInfoCardBody extends StatelessWidget {
  const _NameSignInfoCardBody();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTokens.primaryLight,
        borderRadius: AppTokens.borderRadiusMd,
        border: Border.all(color: AppTokens.border),
      ),
      child: const _ImagePlaceholder(),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  static const _maxDisplayHeight = 420.0;

  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        var width = maxWidth;
        var height = width / NameSignInfoAssets.aspectRatio;
        if (height > _maxDisplayHeight) {
          height = _maxDisplayHeight;
          width = height * NameSignInfoAssets.aspectRatio;
        }

        return Align(
          alignment: Alignment.center,
          child: ClipRRect(
            borderRadius: AppTokens.borderRadiusSm,
            child: Container(
              color: AppTokens.surfaceMuted,
              width: width,
              height: height,
              child: Image.asset(
                NameSignInfoAssets.assetPath,
                fit: BoxFit.contain,
                width: width,
                height: height,
              ),
            ),
          ),
        );
      },
    );
  }
}
