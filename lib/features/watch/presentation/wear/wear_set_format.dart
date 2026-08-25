import '../../../workout/domain/set_spec.dart';

/// El objetivo de una serie, en el mínimo de caracteres legible de reojo.
///
/// **Puerto exacto de `WorkoutView.describe` de watchOS**
/// (`ios/TreinoWatch Watch App/WorkoutView.swift`). Si una de las dos cambia,
/// el atleta ve objetivos distintos en cada muñeca para la misma serie.
///
/// Es una regla de PRESENTACIÓN, no de datos: divergir acá no corrompe el
/// historial, pero sí rompe la promesa de que "lo que se marca en un lado se ve
/// en el otro". Vive separada de la pantalla para poder testearla sin levantar
/// widgets, igual que el resto de las reglas puras del proyecto.
///
/// Orden de precedencia, idéntico al de Swift:
///   1. duración en segundos
///   2. reps exactas
///   3. rango de reps (colapsa a un número si min == max)
/// y después, si hay peso, se le antepone `objetivo × peso kg`.
String describeSetSpec(SetSpec spec) {
  var target = '';
  final duration = spec.durationSeconds;
  final reps = spec.reps;
  final min = spec.repsMin;
  final max = spec.repsMax;

  if (duration != null) {
    target = '${duration}s';
  } else if (reps != null) {
    target = '$reps';
  } else if (min != null && max != null) {
    // El guion es un EN DASH (–), igual que en Swift. Un guion común se lee
    // como resta a tamaño chico.
    target = min == max ? '$min' : '$min–$max';
  }

  final weight = spec.weightKg;
  if (weight != null && weight > 0) {
    // Sin decimales cuando es redondo: "100 kg" y no "100.0 kg".
    final rounded = weight.roundToDouble();
    final weightText = weight == rounded
        ? rounded.toInt().toString()
        : weight.toStringAsFixed(1);
    return target.isEmpty ? '$weightText kg' : '$target × $weightText kg';
  }

  // Em dash cuando no hay nada que describir, igual que Swift.
  return target.isEmpty ? '—' : target;
}
