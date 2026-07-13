import 'package:flutter/foundation.dart';

import 'muscle_group.dart';

/// DTO inmutable con los agregados de la semana actual del usuario.
/// Se computa client-side a partir de `Session` + `SetLog` + catálogo
/// de ejercicios. No persiste — se recalcula cada vez que se entra a
/// la pantalla de Insights.
@immutable
class WeeklyInsights {
  const WeeklyInsights({
    required this.weekStart,
    required this.weekEnd,
    required this.daysTrained,
    required this.sessionsCount,
    required this.plannedSessionsCount,
    required this.setsByGroup,
    required this.targetByGroup,
    this.streak = 0,
    this.monthSessionsCount = 0,
    this.hasEverCompletedAnyWorkout = false,
  });

  /// Lunes 00:00 hora local de la semana actual.
  final DateTime weekStart;

  /// Domingo 23:59:59.999 hora local de la semana actual.
  final DateTime weekEnd;

  /// Longitud 7. Index 0 = lunes, 6 = domingo. true si la semana tuvo al
  /// menos una sesión finished que empezó ese día.
  final List<bool> daysTrained;

  /// Cantidad de sesiones finished en la semana.
  final int sessionsCount;

  /// Sesiones planeadas para la semana (denominador del "4/5" del mockup).
  /// Hardcoded a 5 en esta etapa — el día que el plan de Coach soporte
  /// configurar plannedDays por usuario, esto se calcula real.
  final int plannedSessionsCount;

  /// Cantidad de sets logueados por grupo display esta semana.
  /// Solo incluye grupos con al menos 1 set logueado.
  final Map<MuscleGroupDisplay, int> setsByGroup;

  /// Target de sets por grupo según la rutina asignada al usuario
  /// (sumando todos los days del routine). Vacío si el user no tiene
  /// rutina asignada.
  final Map<MuscleGroupDisplay, int> targetByGroup;

  /// Racha de días consecutivos entrenados (incluye hoy si entrenó,
  /// o cuenta desde ayer si todavía no entrenó hoy). Calculado en
  /// `weeklyInsightsProvider`.
  final int streak;

  /// Cantidad de sesiones finished en el mes calendario actual.
  /// Se basa en el mes de `startedAt.toLocal()`, no en ventana de 30 días.
  final int monthSessionsCount;

  /// `true` si el usuario completó AL MENOS un entrenamiento alguna vez
  /// (`Session.countsAsWorkout`), sin importar si la semana mostrada tiene
  /// sesiones. Desacopla el hub de reportes históricos (`_StatsHubTileList`)
  /// del `_EmptyState` de onboarding: una semana en 0 no implica cuenta
  /// nueva. Derivado de la MISMA lectura de sesiones que ya hace este
  /// provider — no agrega un fetch extra.
  final bool hasEverCompletedAnyWorkout;

  WeeklyInsights copyWith({
    DateTime? weekStart,
    DateTime? weekEnd,
    List<bool>? daysTrained,
    int? sessionsCount,
    int? plannedSessionsCount,
    Map<MuscleGroupDisplay, int>? setsByGroup,
    Map<MuscleGroupDisplay, int>? targetByGroup,
    int? streak,
    int? monthSessionsCount,
    bool? hasEverCompletedAnyWorkout,
  }) =>
      WeeklyInsights(
        weekStart: weekStart ?? this.weekStart,
        weekEnd: weekEnd ?? this.weekEnd,
        daysTrained: daysTrained ?? this.daysTrained,
        sessionsCount: sessionsCount ?? this.sessionsCount,
        plannedSessionsCount: plannedSessionsCount ?? this.plannedSessionsCount,
        setsByGroup: setsByGroup ?? this.setsByGroup,
        targetByGroup: targetByGroup ?? this.targetByGroup,
        streak: streak ?? this.streak,
        monthSessionsCount: monthSessionsCount ?? this.monthSessionsCount,
        hasEverCompletedAnyWorkout:
            hasEverCompletedAnyWorkout ?? this.hasEverCompletedAnyWorkout,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WeeklyInsights &&
          other.weekStart == weekStart &&
          other.weekEnd == weekEnd &&
          listEquals(other.daysTrained, daysTrained) &&
          other.sessionsCount == sessionsCount &&
          other.plannedSessionsCount == plannedSessionsCount &&
          mapEquals(other.setsByGroup, setsByGroup) &&
          mapEquals(other.targetByGroup, targetByGroup) &&
          other.streak == streak &&
          other.monthSessionsCount == monthSessionsCount &&
          other.hasEverCompletedAnyWorkout == hasEverCompletedAnyWorkout;

  @override
  int get hashCode => Object.hash(
        weekStart,
        weekEnd,
        Object.hashAll(daysTrained),
        sessionsCount,
        plannedSessionsCount,
        _stableMapHash(setsByGroup),
        _stableMapHash(targetByGroup),
        streak,
        monthSessionsCount,
        hasEverCompletedAnyWorkout,
      );

  /// MapEntry tiene identity-based hash, así que iteramos ordenado por
  /// enum.index para asegurar reproducibilidad entre instancias con los
  /// mismos pares (clave, valor).
  static int _stableMapHash(Map<MuscleGroupDisplay, int> map) {
    final flat = <int>[];
    for (final key in MuscleGroupDisplay.values) {
      if (map.containsKey(key)) {
        flat.add(key.index);
        flat.add(map[key]!);
      }
    }
    return Object.hashAll(flat);
  }
}
