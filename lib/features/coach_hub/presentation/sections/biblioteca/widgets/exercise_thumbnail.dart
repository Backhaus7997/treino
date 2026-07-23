// NOTE: Scaffold y SafeArea los provee CoachHubScaffold (ADR-CHW-005).
// Todas las strings en español hardcodeado + // i18n.
// No se usa AppL10n (constraint C-6).
library;

import 'package:flutter/material.dart';

import '../../../../../../app/theme/app_palette.dart';
import '../../../../../../core/widgets/motion/treino_shimmer.dart';
import '../../../../../../core/widgets/treino_icon.dart';
import '../../../../../workout/domain/exercise.dart';
import '../exercise_image_resolver.dart';

/// Thumbnail de un ejercicio de catálogo (NO custom) para [ExerciseGridCard].
///
/// Resuelve [exerciseImageUrl] a partir de `exercise.name`:
/// - Match confiable → [Image.network] con [TreinoShimmer] mientras carga,
///   tinte sutil (las fotos de Free Exercise DB tienen fondo blanco — el
///   tinte evita que "griten" en dark theme) y fallback honesto al ícono si
///   la carga falla en runtime.
/// - Sin match confiable → ícono placeholder directo (jamás una imagen
///   equivocada — REQ implícito de la ronda de revisión: "respetando al
///   ejercicio que corresponde").
///
/// Ejercicios CUSTOM nunca instancian este widget — [ExerciseGridCard] los
/// resuelve al ícono acento-tintado directamente, sin consultar el resolver.
class ExerciseThumbnail extends StatelessWidget {
  const ExerciseThumbnail({super.key, required this.exercise});

  final Exercise exercise;

  /// Alpha del tinte oscuro sobre la foto (`BlendMode.multiply` con
  /// `palette.bg`). En dark theme (`bg` ~ near-black) atenúa el blanco crudo
  /// de las fotos de Free Exercise DB para que integren con el theme; en
  /// light theme (`bg` ~ near-white) el efecto es casi nulo — correcto, ahí
  /// las fotos ya integran bien contra un fondo claro.
  static const double _tintAlpha = 0.16;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final url = exerciseImageUrl(exercise.name);
    if (url == null) {
      return _FallbackIcon(
          key: const Key('exercise_thumbnail_fallback'), palette: palette);
    }

    return ColorFiltered(
      key: const Key('exercise_thumbnail_network'),
      colorFilter: ColorFilter.mode(
        palette.bg.withValues(alpha: _tintAlpha),
        BlendMode.multiply,
      ),
      child: Image.network(
        url,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return TreinoShimmer(child: Container(color: palette.bgCard));
        },
        errorBuilder: (_, __, ___) => _FallbackIcon(palette: palette),
      ),
    );
  }
}

/// Ícono placeholder neutro — mismo look que el fallback de asset local
/// previo (bgCard + dumbbell textMuted). Reutilizado tanto para "sin match
/// confiable" como para "la imagen de red falló al cargar en runtime".
class _FallbackIcon extends StatelessWidget {
  const _FallbackIcon({super.key, required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: palette.bgCard,
      alignment: Alignment.center,
      child: Icon(TreinoIcon.dumbbell, size: 40, color: palette.textMuted),
    );
  }
}
