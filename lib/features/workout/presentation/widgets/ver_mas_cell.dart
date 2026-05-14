import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';

/// "Ver más" cell rendered at the end of the Plantillas grid. Visual element
/// matching the mockup — currently a no-op tap (a "ver todas" screen is
/// out of scope for this fix).
class VerMasCell extends StatelessWidget {
  const VerMasCell({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: palette.border,
          radius: 20,
          dashLength: 6,
          dashGap: 4,
          strokeWidth: 1,
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add,
                color: palette.accent,
                size: 32,
              ),
              const SizedBox(height: 8),
              Text(
                'Ver más',
                style: GoogleFonts.barlow(
                  fontSize: 14,
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.dashLength,
    required this.dashGap,
    required this.strokeWidth,
  });

  final Color color;
  final double radius;
  final double dashLength;
  final double dashGap;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );

    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dashLength).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      color != old.color ||
      radius != old.radius ||
      dashLength != old.dashLength ||
      dashGap != old.dashGap ||
      strokeWidth != old.strokeWidth;
}
