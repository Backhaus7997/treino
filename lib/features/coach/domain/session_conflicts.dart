/// Qué choca cuando el PF agenda una sesión a mano (#1493).
///
/// Es un AVISO, no un bloqueo: un PF puede superponer a propósito (sesión
/// doble, clase grupal) o atender fuera de lo publicado. Quien llama decide
/// mostrar un diálogo con "Agendar igual" (ver `new_session_sheet.dart` y su
/// gemelo web `new_session_dialog.dart`, que comparten esta función).
///
/// Todo es wall-clock ADR-7: [Appointment.startsAt] y los `startsAt` que se
/// pasan acá son `DateTime.utc` con los campos del calendario local, sin
/// conversión.
library;

import 'appointment.dart';
import 'availability_override.dart';
import 'availability_rule.dart';
import 'compute_free_slots.dart' show isDayBlocked;

/// El resultado de mirar UNA sesión candidata contra la agenda.
class SessionConflicts {
  const SessionConflicts({
    this.overlapping = const [],
    this.outsideAvailability = false,
  });

  /// Sesiones confirmadas que comparten algún minuto con la candidata, de la
  /// más temprana a la más tardía.
  final List<Appointment> overlapping;

  /// La candidata no cae entera dentro de la disponibilidad publicada.
  final bool outsideAvailability;

  bool get isEmpty => overlapping.isEmpty && !outsideAvailability;
}

/// Mira la sesión `[startsAt, startsAt + durationMin)` contra [existing],
/// [rules] y [overrides].
///
/// **Superposición.** Sólo cuentan las citas `confirmed` (una cancelada no
/// ocupa el horario, igual que en `computeFreeSlots`, ADR-1). Los rangos son
/// semiabiertos: una sesión que termina a las 18:00 y otra que arranca a las
/// 18:00 NO se superponen.
///
/// **Disponibilidad.** La candidata tiene que entrar ENTERA en la unión de las
/// ventanas del día: las reglas semanales de ese día de la semana más las
/// ventanas `extra` de esa fecha. Dos ventanas pegadas (09–11 y 11–13) valen
/// como una sola (09–13). Una sesión que cruza la medianoche nunca entra.
/// Dos casos NO avisan, porque no hay nada contra qué comparar:
///
///  * el PF no publicó disponibilidad (sin reglas y sin `extra` ese día): si
///    nunca configuró "Mis horarios", cada sesión sería una falsa alarma;
///  * el día está bloqueado: ya lo cubre el aviso de "Día bloqueado".
SessionConflicts detectSessionConflicts({
  required DateTime startsAt,
  required int durationMin,
  required List<Appointment> existing,
  required List<AvailabilityRule> rules,
  required List<AvailabilityOverride> overrides,
}) {
  final endsAt = startsAt.add(Duration(minutes: durationMin));

  final overlapping = <Appointment>[
    for (final a in existing)
      if (a.status == AppointmentStatus.confirmed &&
          startsAt.isBefore(a.startsAt.add(Duration(minutes: a.durationMin))) &&
          a.startsAt.isBefore(endsAt))
        a,
  ]..sort((x, y) => x.startsAt.compareTo(y.startsAt));

  return SessionConflicts(
    overlapping: overlapping,
    outsideAvailability: _isOutsideAvailability(
      startsAt: startsAt,
      durationMin: durationMin,
      rules: rules,
      overrides: overrides,
    ),
  );
}

bool _isOutsideAvailability({
  required DateTime startsAt,
  required int durationMin,
  required List<AvailabilityRule> rules,
  required List<AvailabilityOverride> overrides,
}) {
  if (isDayBlocked(overrides, startsAt)) return false;

  // Ventanas del día, en minutos desde las 00:00.
  final windows = <({int start, int end})>[
    for (final r in rules)
      if (r.dayOfWeek == startsAt.weekday)
        (
          start: r.startHour * 60 + r.startMinute,
          end: r.endHour * 60 + r.endMinute,
        ),
    for (final o in overrides)
      if (o is AvailabilityOverrideExtra &&
          o.date.year == startsAt.year &&
          o.date.month == startsAt.month &&
          o.date.day == startsAt.day)
        (
          start: o.startHour * 60 + o.startMinute,
          end: o.endHour * 60 + o.endMinute,
        ),
  ];

  // Sin reglas y sin extras ese día no hay nada publicado contra qué medir.
  // Ojo: con reglas cargadas pero NINGUNA para este día de la semana, el día
  // sí está fuera de lo publicado (el caso "Lun/Mié/Vie" y una sesión el martes).
  if (rules.isEmpty && windows.isEmpty) return false;

  windows.sort((a, b) => a.start.compareTo(b.start));
  final merged = <({int start, int end})>[];
  for (final w in windows) {
    if (merged.isNotEmpty && w.start <= merged.last.end) {
      final last = merged.removeLast();
      merged.add((
        start: last.start,
        end: w.end > last.end ? w.end : last.end,
      ));
    } else {
      merged.add(w);
    }
  }

  final start = startsAt.hour * 60 + startsAt.minute;
  final end = start + durationMin;
  return !merged.any((w) => w.start <= start && end <= w.end);
}

/// El resultado de mirar una SERIE de sesiones (mismo horario, varias fechas).
class SeriesConflicts {
  const SeriesConflicts({this.overlapCount = 0, this.outsideCount = 0});

  /// En cuántas fechas la sesión se superpone con otra ya agendada.
  final int overlapCount;

  /// En cuántas fechas la sesión cae fuera de la disponibilidad publicada.
  final int outsideCount;

  bool get isEmpty => overlapCount == 0 && outsideCount == 0;
}

/// [detectSessionConflicts] para cada fecha de [startsAts] (todas con la misma
/// [durationMin]), contando en cuántas hay cada tipo de conflicto.
SeriesConflicts detectSeriesConflicts({
  required List<DateTime> startsAts,
  required int durationMin,
  required List<Appointment> existing,
  required List<AvailabilityRule> rules,
  required List<AvailabilityOverride> overrides,
}) {
  var overlap = 0;
  var outside = 0;
  for (final startsAt in startsAts) {
    final c = detectSessionConflicts(
      startsAt: startsAt,
      durationMin: durationMin,
      existing: existing,
      rules: rules,
      overrides: overrides,
    );
    if (c.overlapping.isNotEmpty) overlap++;
    if (c.outsideAvailability) outside++;
  }
  return SeriesConflicts(overlapCount: overlap, outsideCount: outside);
}
