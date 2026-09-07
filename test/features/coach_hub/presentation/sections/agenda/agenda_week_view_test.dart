import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/domain/availability_rule.dart';
import 'package:treino/features/coach_hub/presentation/sections/agenda/agenda_time_grid.dart';
import 'package:treino/features/coach_hub/presentation/sections/agenda/agenda_week_view.dart';

/// El cable entre los providers de la agenda y la grilla de tiempo.
///
/// La grilla no conoce Firestore a propósito. Esta pieza es la que traduce, y
/// lo que se testea acá es exactamente esa traducción.
void main() {
  final lunes = DateTime(2026, 9, 7);

  Appointment cita(
    String id,
    DateTime desde,
    int dur,
    String alumno, {
    AppointmentStatus estado = AppointmentStatus.confirmed,
  }) =>
      Appointment(
        id: id,
        trainerId: 'pf-1',
        athleteId: 'a-$id',
        athleteDisplayName: alumno,
        startsAt: desde,
        durationMin: dur,
        status: estado,
      );

  Future<void> pump(
    WidgetTester tester, {
    List<Appointment> citas = const [],
    List<AvailabilityRule> reglas = const [],
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        trainerAppointmentsStreamProvider
            .overrideWith((ref, key) => Stream.value(citas)),
        availabilityRulesStreamProvider
            .overrideWith((ref, id) => Stream.value(reglas)),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: AgendaWeekView(
            trainerId: 'pf-1',
            firstDay: lunes,
            dayCount: 7,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('cada sesión llega a la grilla con el nombre del alumno',
      (tester) async {
    await pump(tester, citas: [
      cita('1', DateTime(2026, 9, 7, 10), 60, 'Bruno Sosa'),
      cita('2', DateTime(2026, 9, 9, 15), 90, 'Ana Ruiz'),
    ]);

    expect(find.byType(AgendaTimeGrid), findsOneWidget);
    expect(find.text('Bruno Sosa'), findsOneWidget);
    expect(find.text('Ana Ruiz'), findsOneWidget);
  });

  testWidgets('las reglas de disponibilidad se vuelven bandas de fondo',
      (tester) async {
    await pump(tester, reglas: [
      const AvailabilityRule(
        id: 'r1',
        trainerId: 'pf-1',
        dayOfWeek: 1,
        startHour: 9,
        startMinute: 0,
        endHour: 13,
        endMinute: 0,
        slotDurationMin: 60,
      ),
    ]);

    expect(find.byKey(const Key('agenda_band_1_540')), findsOneWidget);
  });

  testWidgets('una sesión cancelada NO se ve igual que una confirmada',
      (tester) async {
    await pump(tester, citas: [
      cita('ok', DateTime(2026, 9, 7, 10), 60, 'Confirmada'),
      cita('no', DateTime(2026, 9, 8, 10), 60, 'Cancelada',
          estado: AppointmentStatus.cancelled),
    ]);

    final grid = tester.widget<AgendaTimeGrid>(find.byType(AgendaTimeGrid));
    final confirmada = grid.events.firstWhere((e) => e.id == 'ok');
    final cancelada = grid.events.firstWhere((e) => e.id == 'no');

    // Un turno cancelado libera el horario. Pintarlo igual que uno vigente
    // le hace creer al PF que tiene la agenda llena cuando no la tiene.
    expect(cancelada.color, isNot(equals(confirmada.color)));
  });

  testWidgets('mientras el stream carga, la pantalla no se rompe',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        trainerAppointmentsStreamProvider
            .overrideWith((ref, key) => const Stream.empty()),
        availabilityRulesStreamProvider
            .overrideWith((ref, id) => const Stream.empty()),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: AgendaWeekView(
            trainerId: 'pf-1',
            firstDay: lunes,
            dayCount: 7,
          ),
        ),
      ),
    ));
    await tester.pump();

    // Degrada a grilla vacía, no a spinner ni a error: el esqueleto del
    // calendario (días, horas, disponibilidad) ya es información útil.
    expect(find.byType(AgendaTimeGrid), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
