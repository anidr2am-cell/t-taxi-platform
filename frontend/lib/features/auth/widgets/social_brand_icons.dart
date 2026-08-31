import 'package:flutter/material.dart';

/// Kakao Talk brand bubble (black fill) for sign-in buttons.
class KakaoBrandIcon extends StatelessWidget {
  const KakaoBrandIcon({
    super.key,
    this.size = 20,
    this.color = const Color(0xFF191919),
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _KakaoBubblePainter(color: color),
    );
  }
}

class _KakaoBubblePainter extends CustomPainter {
  _KakaoBubblePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;
    final bubble = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w * 0.88, h * 0.72),
      Radius.circular(w * 0.18),
    );
    canvas.drawRRect(bubble, paint);

    final tail = Path()
      ..moveTo(w * 0.18, h * 0.68)
      ..lineTo(w * 0.06, h * 0.92)
      ..lineTo(w * 0.32, h * 0.68)
      ..close();
    canvas.drawPath(tail, paint);
  }

  @override
  bool shouldRepaint(covariant _KakaoBubblePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// LINE brand speech-bubble mark (white on green buttons).
class LineBrandIcon extends StatelessWidget {
  const LineBrandIcon({
    super.key,
    this.size = 20,
    this.color = Colors.white,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _LineBubblePainter(color: color),
    );
  }
}

class _LineBubblePainter extends CustomPainter {
  _LineBubblePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;
    final bubble = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w * 0.92, h * 0.78),
      Radius.circular(w * 0.22),
    );
    canvas.drawRRect(bubble, paint);

    final linePaint = Paint()
      ..color = const Color(0xFF06C755)
      ..strokeWidth = w * 0.09
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 3; i++) {
      final y = h * (0.28 + i * 0.16);
      canvas.drawLine(Offset(w * 0.22, y), Offset(w * 0.70, y), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LineBubblePainter oldDelegate) =>
      oldDelegate.color != color;
}
