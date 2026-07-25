// AgendaWebDayList — lista vertical de turnos del día seleccionado
// (pulido-post-revision). Smoke de estados + regresión SCENARIO-STALE.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach_hub/presentation/sections/agenda/agenda_web_day_list.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';

final _selectedDay = DateTime.utc(2026, 7, 20);
final _rangeFrom = DateTime.utc(2026, 7, 1);
final _rangeTo = DateTime.utc(2026, 7, 31);

Appointment _appt(String id) => Appointment.create(
      trainerId: 'trainer-1',
      athleteId: 'a1',
      athleteDisplayName: 'Ana',
      startsAt: _selectedDay.add(const Duration(hours: 10)),
      durationMin: 60,
    );

Widget _harness(Stream<List<Appointment>> stream) => ProviderScope(
      overrides: [
        trainerAppointmentsStreamProvider(
          TrainerAppointmentsKey(
            trainerId: 'trainer-1',
            fromDate: _rangeFrom,
            toDate: _rangeTo,
          ),
        ).overrideWith((ref) => stream),
        userPublicProfileProvider('a1').overrideWith(
          (ref) => Stream.value(
            const UserPublicProfile(uid: 'a1', displayName: 'Ana Activa'),
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: AgendaWebDayList(
            trainerId: 'trainer-1',
            selectedDay: _selectedDay,
            rangeFrom: _rangeFrom,
            rangeTo: _rangeTo,
          ),
        ),
      ),
    );

void main() {
  group('AgendaWebDayList — estados', () {
    testWidgets('data → muestra la card del turno', (tester) async {
      await tester.pumpWidget(_harness(Stream.value([_appt('1')])));
      await tester.pumpAndSettle();

      expect(find.text('Ana Activa'), findsOneWidget);
    });

    testWidgets('error sin data previa → mensaje de error', (tester) async {
      await tester.pumpWidget(
        _harness(Stream<List<Appointment>>.error(Exception('boom'))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Error al cargar los turnos.'), findsOneWidget);
    });
  });

  group(
      'SCENARIO-STALE — agenda sostiene los turnos ante error transitorio '
      '(pulido-post-revision)', () {
    // Regression: `apptAsync.when(loading:, error:, data:)` despacha por
    // SUBTIPO runtime (ignora `hasValue`) — `trainerAppointmentsStreamProvider`
    // es un StreamProvider en vivo, Riverpod 2.5+ preserva el valor previo
    // dentro de un AsyncError subsiguiente (copyWithPrevious/"seamless"), así
    // que un error transitorio (con turnos ya cargados) tapaba la lista con
    // el mensaje de error.
    testWidgets(
        'los turnos ya cargados no desaparecen tras un error transitorio '
        'del stream (stale-while-refresh)', (tester) async {
      final controller = StreamController<List<Appointment>>();
      addTearDown(controller.close);

      await tester.pumpWidget(_harness(controller.stream));
      await tester.pump();

      controller.add([_appt('1')]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Ana Activa'), findsOneWidget);

      controller.addError(Exception('transient stream hiccup'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.text('Ana Activa'),
        findsOneWidget,
        reason: 'un error transitorio con turnos ya cargados no debe tapar '
            'la lista de la agenda',
      );
      expect(find.text('Error al cargar los turnos.'), findsNothing);
    });
  });
}
