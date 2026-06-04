import '../../profile/domain/experience_level.dart';

/// Modelo de PREVIEW de un plan periodizado importado desde Excel
/// (hoja "Programa"). Vive solo en memoria mientras el PF revisa antes de
/// asignar — NO se persiste, por eso son clases planas (sin freezed/json).
///
/// La asignación (convertir esto en algo que el alumno consuma, resolviendo
/// "semana actual") es el paso siguiente y toca el lane del alumno: se coordina
/// aparte. Acá solo mostramos y validamos el match contra el catálogo.
class PeriodizedPreviewPlan {
  PeriodizedPreviewPlan({
    required this.name,
    required this.daysPerWeek,
    required this.durationWeeks,
    required this.level,
    required this.weeks,
    this.unmatched = const [],
  });

  final String name;
  final int daysPerWeek;
  final int durationWeeks;
  final ExperienceLevel level;
  final List<PeriodizedPreviewWeek> weeks;
  final List<PeriodizedUnmatched> unmatched;

  bool get hasUnmatched => unmatched.isNotEmpty;

  /// Nombres distintos sin match (un mismo ejercicio se repite semana a
  /// semana, así que deduplicamos para el warning y el pick manual).
  List<String> get unmatchedNames {
    final seen = <String>{};
    final out = <String>[];
    for (final u in unmatched) {
      if (seen.add(u.rowName)) out.add(u.rowName);
    }
    return out;
  }

  /// Mapea TODAS las ocurrencias de [rowName] (en todas las semanas/días) al
  /// ejercicio elegido y las saca de `unmatched`. Mapear por nombre resuelve
  /// el ejercicio en todas las semanas de una sola vez.
  PeriodizedPreviewPlan mapExercise(
    String rowName, {
    required String exerciseId,
    required String exerciseName,
    String? muscleGroup,
  }) {
    return PeriodizedPreviewPlan(
      name: name,
      daysPerWeek: daysPerWeek,
      durationWeeks: durationWeeks,
      level: level,
      unmatched: unmatched.where((u) => u.rowName != rowName).toList(),
      weeks: weeks
          .map((w) => w.copyWith(
                days: w.days
                    .map((d) => d.copyWith(
                          items: d.items
                              .map((it) => (it.rowName == rowName &&
                                      it.exerciseId == null)
                                  ? it.copyWith(
                                      exerciseId: exerciseId,
                                      exerciseName: exerciseName,
                                      muscleGroup: muscleGroup,
                                    )
                                  : it)
                              .toList(),
                        ))
                    .toList(),
              ))
          .toList(),
    );
  }
}

class PeriodizedPreviewWeek {
  PeriodizedPreviewWeek({required this.weekNumber, required this.days});
  final int weekNumber;
  final List<PeriodizedPreviewDay> days;

  PeriodizedPreviewWeek copyWith({List<PeriodizedPreviewDay>? days}) =>
      PeriodizedPreviewWeek(weekNumber: weekNumber, days: days ?? this.days);
}

class PeriodizedPreviewDay {
  PeriodizedPreviewDay({required this.dayNumber, required this.items});
  final int dayNumber;
  final List<PeriodizedPreviewItem> items;

  PeriodizedPreviewDay copyWith({List<PeriodizedPreviewItem>? items}) =>
      PeriodizedPreviewDay(dayNumber: dayNumber, items: items ?? this.items);
}

class PeriodizedPreviewItem {
  PeriodizedPreviewItem({
    required this.rowName,
    required this.sets,
    required this.repsMin,
    required this.repsMax,
    required this.exerciseName,
    this.weightKg,
    this.restSec,
    this.notes,
    this.exerciseId,
    this.muscleGroup,
    this.order,
    this.block,
  });

  final String rowName;
  final int sets;
  final int repsMin;
  final int repsMax;
  final double? weightKg;
  final int? restSec;
  final String? notes;
  final String? exerciseId;
  final String exerciseName;
  final String? muscleGroup;
  final int? order;

  /// Letra de superserie tal cual el Excel ("A", "B"…); null = ejercicio suelto.
  final String? block;

  bool get isMatched => exerciseId != null;

  PeriodizedPreviewItem copyWith({
    String? exerciseId,
    String? exerciseName,
    String? muscleGroup,
  }) =>
      PeriodizedPreviewItem(
        rowName: rowName,
        sets: sets,
        repsMin: repsMin,
        repsMax: repsMax,
        weightKg: weightKg,
        restSec: restSec,
        notes: notes,
        order: order,
        block: block,
        exerciseId: exerciseId ?? this.exerciseId,
        exerciseName: exerciseName ?? this.exerciseName,
        muscleGroup: muscleGroup ?? this.muscleGroup,
      );
}

class PeriodizedUnmatched {
  PeriodizedUnmatched({
    required this.weekNumber,
    required this.dayNumber,
    required this.rowName,
  });
  final int weekNumber;
  final int dayNumber;
  final String rowName;
}
