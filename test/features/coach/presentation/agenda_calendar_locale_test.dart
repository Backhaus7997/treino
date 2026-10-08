import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/utils/app_clock.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/data/appointment_repository.dart';
import 'package:treino/features/coach/data/availability_repository.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach/presentation/athlete_agenda_screen.dart';
import 'package:treino/features/coach/presentation/trainer_agenda_tab.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

/// El calendario de las agendas mobile habla el idioma de la app.
///
/// `TableCalendar` formatea el encabezado (`DateFormat.yMMMM`) y la fila de
/// días (`DateFormat.E`) con su parámetro `locale`, y sin él cae a en_US: la
/// agenda del PF decía «October 2026» sobre una fila de días en inglés, en una
/// app es-AR (simulador, 2026-10-02).
///
/// ## Fechas
///
/// El «hoy» de la agenda vive en el frame de `startsAt`: el wall-clock del
/// DISPOSITIVO (ADR-7, `nowWall()` en `coach/domain/wall_clock.dart`), no
/// `argentinaNow()`. Los puntos del calendario y el filtro de `DayTimeline`
/// leen los campos de `startsAt`, así que el día enfocado tiene que salir del
/// mismo frame. Cada caso congela `AppClock` en una hora local, y los
/// instantes barren el eje del día a propósito: primer día del mes apenas
/// pasada la medianoche (con semana que empieza en septiembre), mitad de mes,
/// último día casi a la medianoche, y un cambio de año.
///
/// El barrido de TZ es el control del frame, no un trámite: con
/// `argentinaNow()`, los casos de medianoche caen en el mes vecino fuera de
/// UTC−3 (medido):
///
/// ```bash
/// for z in UTC Pacific/Kiritimati Etc/GMT+12 \
///          America/Argentina/Buenos_Aires Asia/Tokyo; do
///   TZ="$z" flutter test test/features/coach/presentation/agenda_calendar_locale_test.dart
/// done
/// ```
void main() {
  // Hora de pared del dispositivo (local), como pide `AppClock.freeze`.
  final casos = <({DateTime local, String mes})>[
    (local: DateTime(2026, 10, 1, 0, 30), mes: 'octubre de 2026'),
    (local: DateTime(2026, 10, 14, 12), mes: 'octubre de 2026'),
    (local: DateTime(2026, 10, 31, 23, 30), mes: 'octubre de 2026'),
    (local: DateTime(2027, 1, 1, 0, 30), mes: 'enero de 2027'),
  ];

  void congelar(DateTime local) {
    AppClock.freeze(local);
    addTearDown(AppClock.unfreeze);
  }

  // Abreviaturas de `DateFormat.E('es')`. TableCalendar arranca la semana en
  // domingo por defecto; acá sólo importa que estén las siete en español.
  const diasEs = ['dom', 'lun', 'mar', 'mié', 'jue', 'vie', 'sáb'];

  void expectCalendarioEnEspanol(String mes) {
    expect(find.text(mes), findsOneWidget);
    for (final dia in diasEs) {
      expect(find.text(dia), findsOneWidget, reason: 'falta «$dia»');
    }
  }

  /// El «hoy» que resalta el calendario es el mismo día que enfoca: si
  /// `currentDay` queda en el default de table_calendar, lee la hora real y
  /// no la congelada.
  void expectHoyEsElDiaCongelado(WidgetTester tester, DateTime local) {
    final calendario = tester.widget<TableCalendar>(
      find.byWidgetPredicate((w) => w is TableCalendar),
    );
    expect(isSameDay(calendario.currentDay, local), isTrue,
        reason: 'currentDay=${calendario.currentDay}, congelado=$local');
  }

  group('agenda del PF (TrainerAgendaTab)', () {
    for (final caso in casos) {
      testWidgets(
          '${caso.local.toIso8601String().substring(0, 16)} local → '
          '«${caso.mes}» y días en español', (tester) async {
        congelar(caso.local);

        await tester.pumpWidget(
          _app(
            const TrainerAgendaTab(trainerId: 'trainer-1'),
            overrides: [
              trainerAppointmentsStreamProvider.overrideWith(
                (ref, key) => Stream.value(const <Appointment>[]),
              ),
              availabilityRepositoryProvider
                  .overrideWithValue(_FakeAvailabilityRepository()),
              appointmentRepositoryProvider
                  .overrideWithValue(_FakeAppointmentRepository()),
            ],
          ),
        );
        await tester.pump();

        expectCalendarioEnEspanol(caso.mes);
        expectHoyEsElDiaCongelado(tester, caso.local);
      });
    }
  });

  group('agenda del alumno (AthleteAgendaScreen)', () {
    for (final caso in casos) {
      testWidgets(
          '${caso.local.toIso8601String().substring(0, 16)} local → '
          '«${caso.mes}» y días en español', (tester) async {
        congelar(caso.local);

        await tester.pumpWidget(
          _app(
            const AthleteAgendaScreen(
              trainerId: 'trainer-1',
              athleteId: 'athlete-1',
            ),
            overrides: [
              currentAthleteLinkProvider
                  .overrideWith((ref) => Stream.value(_link())),
              appointmentsForAthleteStreamProvider('athlete-1')
                  .overrideWith((ref) => Stream.value(const <Appointment>[])),
              userPublicProfileProvider('trainer-1')
                  .overrideWith((ref) => Stream.value(null)),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expectCalendarioEnEspanol(caso.mes);
        expectHoyEsElDiaCongelado(tester, caso.local);
      });
    }
  });
}

class _FakeAvailabilityRepository extends Fake
    implements AvailabilityRepository {}

class _FakeAppointmentRepository extends Fake
    implements AppointmentRepository {}

TrainerLink _link() => TrainerLink(
      id: 'link-1',
      trainerId: 'trainer-1',
      athleteId: 'athlete-1',
      status: TrainerLinkStatus.active,
      requestedAt: DateTime.utc(2026, 5, 18, 10),
      acceptedAt: DateTime.utc(2026, 5, 18, 12),
      sharedWithTrainer: false,
    );

Widget _app(Widget child, {required List<Override> overrides}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(body: child),
    ),
  );
}
