import '../../../../core/utils/kg_format.dart';
import '../../../../l10n/app_l10n.dart';
import 'mmss.dart';

/// Texto de la MEJOR serie de un ejercicio, o `null` cuando no hay nada que
/// mostrar. Lo comparten el resumen post-entreno y el HISTORIAL del detalle de
/// ejercicio: la regla vive acá para que las dos pantallas no vuelvan a
/// divergir (#1701 la arregló en una, #1716 encontró la otra con el bug viejo).
///
/// Un ejercicio por TIEMPO o por DISTANCIA guarda peso 0 y reps 0 (#1702), y
/// «0 reps» es falso: su mejor serie es el tiempo o los metros. Con el peso por
/// delante (una serie con carga es siempre «kg × reps»), el orden es:
///
/// 1. peso > 0 → «80 kg × 5»;
/// 2. tiempo → «01:00»;
/// 3. distancia → «40 m»;
/// 4. reps de peso corporal → «12 reps» (más [bodyweightSuffix], si lo pide
///    quien llama);
/// 5. nada → `null`: una serie vieja por tiempo/distancia, de antes de #1702 y
///    sin métrica ni reps, no tiene mejor serie que mostrar. Quien llama
///    muestra sólo la cantidad de series, en vez de un «0 reps».
///
/// [bodyweightSuffix] va pegado a «N reps» y sólo en el caso 4. El resumen
/// post-entreno lo usa para aclarar que es peso corporal (#1513); el HISTORIAL
/// no, y por eso es un parámetro y no parte de la regla.
String? bestSetLabel({
  required AppL10n l10n,
  required double weightKg,
  required int reps,
  int? durationSeconds,
  double? distanceMeters,
  String bodyweightSuffix = '',
}) {
  if (weightKg > 0) {
    return '${formatNumberDisplay(weightKg, l10n.localeName)} kg × $reps';
  }
  if (durationSeconds != null) return formatMMSS(durationSeconds);
  if (distanceMeters != null) {
    return l10n.workoutSetDistanceValue(
      formatNumberDisplay(distanceMeters, l10n.localeName),
    );
  }
  if (reps > 0) return '$reps reps$bodyweightSuffix';
  return null;
}
