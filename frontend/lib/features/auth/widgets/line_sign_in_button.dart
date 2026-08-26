import 'package:flutter/material.dart';

class LineSignInButton extends StatelessWidget {
  const LineSignInButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  static const _lineGreen = Color(0xFF06C755);
  static const _lineText = Colors.white;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: _lineGreen,
          foregroundColor: _lineText,
          disabledBackgroundColor: _lineGreen.withValues(alpha: 0.6),
          disabledForegroundColor: _lineText.withValues(alpha: 0.85),
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
                  color: _lineText,
                ),
              )
            : const Icon(Icons.chat),
        label: Text(label),
      ),
    );
  }
}
