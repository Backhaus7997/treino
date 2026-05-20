import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';

/// Silueta muscular del Insights / Home "Esta Semana".
///
/// Renderiza `assets/body/bodyfront.png` + `assets/body/bodyback.png` lado a
/// lado dentro del card. Las masks individuales por músculo
/// (`assets/body/mask_<view>_<muscle>.png`) están cargadas en el bundle pero
/// NO se renderizan en esta etapa — quedan listas para el highlighting
/// dinámico per muscle group (Fase 6 / polish), donde se stackearán sobre el
/// body base con `ColorFiltered` + `palette.accent` según `setsByGroup`.
///
/// Si los assets fallan en cargar (test sin bundle, imagen movida), el
/// `errorBuilder` cae al icono original — la card nunca se rompe visualmente.
class BodySilhouettePlaceholder extends StatelessWidget {
  const BodySilhouettePlaceholder({
    super.key,
    required this.width,
    required this.height,
    this.label,
    this.showBack = false,
  });

  final double width;
  final double height;

  /// Opcional — texto al pie de las siluetas (ej. "Tocá para ver tus insights").
  final String? label;

  /// Si `true`, renderiza `bodyfront` + `bodyback` lado a lado (mockup
  /// Esta Semana). Si `false` (default), solo `bodyfront` centrado (mockup
  /// Insights · Músculos de la semana).
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: showBack
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: _BodyImage(
                            assetPath: 'assets/body/bodyfront.png',
                            palette: palette,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _BodyImage(
                            assetPath: 'assets/body/bodyback.png',
                            palette: palette,
                          ),
                        ),
                      ],
                    )
                  : _BodyImage(
                      assetPath: 'assets/body/bodyfront.png',
                      palette: palette,
                    ),
            ),
            if (label != null) ...[
              const SizedBox(height: 8),
              Text(
                label!,
                textAlign: TextAlign.center,
                style: GoogleFonts.barlow(
                  fontWeight: FontWeight.w400,
                  fontSize: 12,
                  color: palette.textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BodyImage extends StatelessWidget {
  const _BodyImage({required this.assetPath, required this.palette});

  final String assetPath;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Center(
        child: Icon(
          TreinoIcon.tabWorkout,
          size: 32,
          color: palette.accent.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}
