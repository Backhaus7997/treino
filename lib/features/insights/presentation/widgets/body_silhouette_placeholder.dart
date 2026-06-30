import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../domain/muscle_group.dart';

/// Silueta muscular del Insights / Home "Esta Semana".
///
/// Renderiza `assets/body/bodyfront.png` (y opcionalmente `bodyback.png`) con
/// masks por grupo muscular stackeadas encima, tintadas en `palette.accent`.
/// La intensidad del tintado se calcula vs el target de la rutina:
/// `opacity = (setsDone / target).clamp(0.0, 1.0)`. Grupos sin target en la
/// rutina pero con sets realizados se pintan a `_kOrphanIntensity` (60%)
/// para mantener la señal visual sin sugerir cumplimiento de plan.
///
/// Decisión 3C (2026-06-19): intensidad proporcional al cumplimiento del
/// plan en vez de binario — el athlete ve de un vistazo qué tan cerca está
/// del volumen semanal prescripto, no solo "si tocaste el músculo".
///
/// Si los assets fallan en cargar (test sin bundle, imagen movida), el
/// `errorBuilder` del PNG base cae al icono original — la card nunca se
/// rompe visualmente.
class BodySilhouettePlaceholder extends StatelessWidget {
  const BodySilhouettePlaceholder({
    super.key,
    required this.width,
    required this.height,
    this.label,
    this.showBack = false,
    this.setsByGroup = const {},
    this.targetByGroup = const {},
  });

  final double width;
  final double height;

  /// Opcional — texto al pie de las siluetas (ej. "Tocá para ver tus insights").
  final String? label;

  /// Si `true`, renderiza `bodyfront` + `bodyback` lado a lado (mockup
  /// Esta Semana). Si `false` (default), solo `bodyfront` centrado (mockup
  /// Insights · Músculos de la semana).
  final bool showBack;

  /// Sets logueados por grupo en la semana actual. Default vacío para
  /// retrocompatibilidad con call sites que aún no pasan data.
  final Map<MuscleGroupDisplay, int> setsByGroup;

  /// Target de sets por grupo según la rutina asignada (denominador del
  /// ratio de intensidad). Default vacío — sin target los grupos entrenados
  /// se pintan al fallback `_kOrphanIntensity`.
  final Map<MuscleGroupDisplay, int> targetByGroup;

  /// Intensidad de tintado para grupos con sets realizados pero sin target
  /// en la rutina (athlete entrenó algo fuera de plan). Suficiente para que
  /// se vea, pero no full — distingue cumplimiento (100%) de "tocaste pero
  /// no estaba prescripto".
  static const double _kOrphanIntensity = 0.6;

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
                          child: _BodyView(
                            baseAsset: 'assets/body/bodyfront.png',
                            masksByGroup: _frontMasks(),
                            palette: palette,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _BodyView(
                            baseAsset: 'assets/body/bodyback.png',
                            masksByGroup: _backMasks(),
                            palette: palette,
                          ),
                        ),
                      ],
                    )
                  : _BodyView(
                      baseAsset: 'assets/body/bodyfront.png',
                      masksByGroup: _frontMasks(),
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

  /// Devuelve `{assetPath: intensity}` para todas las masks frontales que
  /// deben pintarse esta semana. Una mask puede aparecer una sola vez en el
  /// map; si un grupo expone varias, todas heredan la misma intensidad.
  Map<String, double> _frontMasks() => _masksFor((g) => g.frontMaskAssets);

  Map<String, double> _backMasks() => _masksFor((g) => g.backMaskAssets);

  Map<String, double> _masksFor(
    List<String> Function(MuscleGroupDisplay) selector,
  ) {
    final result = <String, double>{};
    for (final group in MuscleGroupDisplay.displayOrder) {
      final sets = setsByGroup[group] ?? 0;
      if (sets <= 0) continue;
      final intensity = _intensityFor(group, sets);
      for (final mask in selector(group)) {
        result[mask] = intensity;
      }
    }
    return result;
  }

  double _intensityFor(MuscleGroupDisplay group, int sets) {
    final target = targetByGroup[group] ?? 0;
    if (target <= 0) return _kOrphanIntensity;
    return (sets / target).clamp(0.0, 1.0);
  }
}

/// Stack: PNG base del cuerpo + N masks tintadas en `palette.accent` con la
/// opacidad calculada en el padre.
class _BodyView extends StatelessWidget {
  const _BodyView({
    required this.baseAsset,
    required this.masksByGroup,
    required this.palette,
  });

  final String baseAsset;
  final Map<String, double> masksByGroup;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      fit: StackFit.expand,
      children: [
        // Base body silhouette — ColorFiltered so the PNG silhouette adopts
        // palette.textPrimary in both light and dark modes (srcIn replaces
        // RGB while keeping the PNG alpha channel).
        ColorFiltered(
          colorFilter: ColorFilter.mode(palette.textPrimary, BlendMode.srcIn),
          child: Image.asset(
            baseAsset,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Center(
              child: Icon(
                TreinoIcon.tabWorkout,
                size: 32,
                color: palette.accent.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
        // Each muscle mask tinted in the brand accent. `ColorFiltered.srcIn`
        // keeps the mask's alpha channel and replaces the RGB with the
        // accent colour — independent of whatever fill the PNG had.
        for (final entry in masksByGroup.entries)
          Opacity(
            opacity: entry.value,
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(
                palette.accent,
                BlendMode.srcIn,
              ),
              child: Image.asset(
                entry.key,
                fit: BoxFit.contain,
                // Defensive: if a mask is missing from the bundle, render
                // nothing rather than killing the whole silhouette.
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
      ],
    );
  }
}
