import 'package:flutter/foundation.dart';

import 'muscle_group.dart';

/// DTO inmutable con los agregados de UN día calendario específico.
///
/// [REQ:heat-map-per-day] A diferencia de [WeeklyInsights] (acumulado semanal),
/// esto representa exactamente lo entrenado en [day] — nada más. Un día sin
/// sesión finished se representa con `setsByGroup` vacío (silueta en blanco).
@immutable
class DayInsights {
  const DayInsights({
    required this.day,
    required this.setsByGroup,
    required this.sessionsCount,
  });

  /// Día calendario (medianoche local) que estos agregados representan.
  final DateTime day;

  /// Sets logueados por grupo display, SOLO de sesiones finished cuyo
  /// `startedAt` cae en [day]. Vacío si no hubo sesión ese día.
  final Map<MuscleGroupDisplay, int> setsByGroup;

  /// Cantidad de sesiones finished que empezaron en [day].
  final int sessionsCount;

  /// `true` si no hubo ninguna sesión finished en [day] — la silueta debe
  /// renderizarse en blanco.
  bool get isEmpty => sessionsCount == 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DayInsights &&
          other.day == day &&
          mapEquals(other.setsByGroup, setsByGroup) &&
          other.sessionsCount == sessionsCount;

  @override
  int get hashCode => Object.hash(
        day,
        _stableMapHash(setsByGroup),
        sessionsCount,
      );

  /// MapEntry tiene identity-based hash, así que iteramos ordenado por
  /// enum.index para asegurar reproducibilidad entre instancias con los
  /// mismos pares (clave, valor). Mismo patrón que `WeeklyInsights`.
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
