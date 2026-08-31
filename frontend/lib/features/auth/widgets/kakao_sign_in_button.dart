import 'package:flutter/material.dart';

import 'social_brand_icons.dart';

class KakaoSignInButton extends StatelessWidget {
  const KakaoSignInButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  static const _kakaoYellow = Color(0xFFFEE500);
  static const _kakaoText = Color(0xFF191919);
  static const _buttonHeight = 50.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _buttonHeight,
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: _kakaoYellow,
          foregroundColor: _kakaoText,
          disabledBackgroundColor: _kakaoYellow.withValues(alpha: 0.6),
          disabledForegroundColor: _kakaoText.withValues(alpha: 0.7),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: loading ? null : onPressed,
        icon: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _kakaoText,
                ),
              )
            : const KakaoBrandIcon(size: 20),
        label: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
