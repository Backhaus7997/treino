import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/tokens/tokens.dart';
import '../../../../core/widgets/treino_icon.dart';

/// Lo que ve el usuario en un día sin ejercicios.
///
/// Antes ese día era un acordeón vacío: se abría y no había nada, sin decir si
/// estaba bien así o faltaba algo. El borde punteado dice "acá va contenido"
/// sin gritar error — un día vacío es un estado intermedio legítimo mientras
/// se arma la rutina, no una falla.
class EmptyDayState extends StatelessWidget {
  const EmptyDayState({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return DottedBorderBox(
      child: Padding(
        // La escala es CERRADA: 8·12·14·18·20. `s20 + hairline` daba 24, que
        // es justo el valor que la escala existe para prohibir.
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.s20,
          horizontal: AppSpacing.s18,
        ),
        child: Column(
          children: [
            Icon(TreinoIcon.dumbbell, size: 30, color: palette.textFaint),
            const SizedBox(height: AppSpacing.s12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.barlowCondensed(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.hairline),
            Text(
              body,
              textAlign: TextAlign.center,
              style: GoogleFonts.barlow(
                fontSize: 12.5,
                color: palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Contenedor de borde punteado.
///
/// Flutter no trae borde punteado en `BoxDecoration`, así que se pinta. Vive
/// acá y no en el kit porque por ahora lo usa un solo lugar; si aparece un
/// segundo, se muda a `core/widgets`.
class DottedBorderBox extends StatelessWidget {
  const DottedBorderBox({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return CustomPaint(
      painter: _DottedBorderPainter(
        color: palette.borderStrong,
        radius: AppRadius.md,
      ),
      child: SizedBox(width: double.infinity, child: child),
    );
  }
}

class _DottedBorderPainter extends CustomPainter {
  const _DottedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Recorre el contorno y dibuja tramos de 4 con huecos de 4.
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        final fin = (dist + 4).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(dist, fin), paint);
        dist += 8;
      }
    }
  }

  @override
  bool shouldRepaint(_DottedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
