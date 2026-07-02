// NOTE: helpers de formato para las cards/detalle de templates (Biblioteca web).
// es-AR hardcodeado + // i18n. No se usa AppL10n (constraint C-6).
library;

import 'package:treino/features/workout/domain/routine.dart';

/// Etiqueta de cadencia de un template: "N día/días/sem · N semana/semanas".
///
/// Singulariza cuando el número es 1 ("1 día/sem · 1 semana"), pluraliza si no.
/// `days.length` = días por semana (cada RoutineDay es un día de entrenamiento);
/// `numWeeks` = semanas de periodización (routine.dart).
String routineCadenceLabel(Routine routine) {
  final dias = routine.days.length;
  final semanas = routine.numWeeks;
  final d = dias == 1 ? 'día' : 'días'; // i18n
  final s = semanas == 1 ? 'semana' : 'semanas'; // i18n
  return '$dias $d/sem · $semanas $s';
}
