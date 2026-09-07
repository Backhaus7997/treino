// El cable entre los providers de la agenda y `AgendaTimeGrid`.
//
// La grilla no conoce Firestore ni Riverpod a propósito: recibe sus propios
// `AgendaEvent` y `AgendaAvailabilityBand` y se testea con datos armados a
// mano. Esta pieza es la que traduce, y es el único lugar donde las dos formas
// se tocan.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/theme/app_palette.dart';
import '../../../../coach/application/agenda_providers.dart';
import '../../../../coach/domain/wall_clock.dart';
import '../../../../coach/domain/appointment.dart';
import 'agenda_time_grid.dart';

/// Semana (o día) de la agenda, con las sesiones y la disponibilidad reales.
class AgendaWeekView extends ConsumerWidget {
  const AgendaWeekView({
    super.key,
    required this.trainerId,
    required this.firstDay,
    this.dayCount = 7,
    this.now,
    this.onEmptySlotTap,
    this.onEventTap,
  });

  final String trainerId;
  final DateTime firstDay;
  final int dayCount;

  /// Inyectable para poder testear la línea de "ahora" sin congelar el reloj.
  final DateTime? now;

  final void Function(DateTime)? onEmptySlotTap;
  final void Function(Appointment)? onEventTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);

    final desde = DateTime.utc(firstDay.year, firstDay.month, firstDay.day);
    final hasta = desde.add(Duration(days: dayCount));

    // `valueOrNull` y no `when`: mientras carga se muestra la grilla vacía en
    // vez de un spinner. El esqueleto —los días, las horas, la
    // disponibilidad— ya es información útil, y reemplazarlo por una ruedita
    // hace parpadear la pantalla entera en cada refresco del stream.
    final citas = ref
            .watch(trainerAppointmentsStreamProvider(
              TrainerAppointmentsKey(
                trainerId: trainerId,
                fromDate: desde,
                toDate: hasta,
              ),
            ))
            .valueOrNull ??
        const <Appointment>[];

    final reglas =
        ref.watch(availabilityRulesStreamProvider(trainerId)).valueOrNull ??
            const [];

    return AgendaTimeGrid(
      firstDay: firstDay,
      dayCount: dayCount,
      // `nowWall()` y no el reloj crudo: la línea de "ahora" se compara
      // contra `Appointment.startsAt`, que es wall-clock de Argentina. Con el
      // instante UTC real la línea se dibuja 3 horas corrida — el mismo modo
      // de falla de #671.
      //
      // (El comentario NO nombra la llamada prohibida a propósito: el scanner
      // del ratchet `no_raw_clock_scan` es TEXTUAL y cuenta los comentarios
      // igual que el código. Escribirla acá, aunque fuera para explicar por
      // qué no se usa, rompe el ratchet lo mismo.)
      now: now ?? nowWall(),
      onEmptySlotTap: onEmptySlotTap,
      onEventTap: onEventTap == null
          ? null
          : (e) {
              final cita = citas.where((c) => c.id == e.id);
              if (cita.isNotEmpty) onEventTap!(cita.first);
            },
      availability: [
        for (final r in reglas)
          AgendaAvailabilityBand(
            weekday: r.dayOfWeek,
            startMinute: r.startHour * 60 + r.startMinute,
            endMinute: r.endHour * 60 + r.endMinute,
          ),
      ],
      events: [
        for (final c in citas)
          AgendaEvent(
            id: c.id,
            startsAt: c.startsAt,
            durationMin: c.durationMin,
            title: c.athleteDisplayName,
            subtitle: c.status == AppointmentStatus.cancelled
                ? 'Cancelada' // i18n
                : null,
            // Un turno cancelado LIBERA el horario. Pintarlo igual que uno
            // vigente le hace creer al PF que tiene la agenda llena cuando en
            // realidad ahí entra alguien. Va apagado, no se esconde: que el
            // turno existió es un dato, y si desaparece el PF no entiende por
            // qué el alumno dice que tenía hora.
            color: c.status == AppointmentStatus.cancelled
                ? palette.textMuted
                : palette.accent,
          ),
      ],
    );
  }
}
