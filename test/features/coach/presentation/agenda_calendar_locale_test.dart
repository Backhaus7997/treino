import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
/// El mes del encabezado sale de `AppClock.now()`, así que cada caso congela
/// el reloj. Los instantes barren el eje del día a propósito: primer día del
/// mes apenas pasada la medianoche (con semana que empieza en septiembre),
/// mitad de mes, último día casi a la medianoche, y un cambio de año. Son
/// locales, como pide `AppClock.freeze`, así que el mes enfocado no depende de
/// la TZ del runner. Eso se prueba corriendo el archivo, no se supone:
///
/// ```bash
/// for z in UTC Pacific/Kiritimati Etc/GMT+12 \
///          America/Argentina/Buenos_Aires Asia/Tokyo; do
///   TZ="$z" flutter test test/features/coach/presentation/agenda_calendar_locale_test.dart
/// done
/// ```
void main() {
  final casos = <({DateTime ahora, String mes})>[
    (ahora: DateTime(2026, 10, 1, 0, 30), mes: 'octubre de 2026'),
    (ahora: DateTime(2026, 10, 14, 12), mes: 'octubre de 2026'),
    (ahora: DateTime(2026, 10, 31, 23, 30), mes: 'octubre de 2026'),
    (ahora: DateTime(2027, 1, 1, 0, 30), mes: 'enero de 2027'),
  ];

  // Abreviaturas de `DateFormat.E('es')`. TableCalendar arranca la semana en
  // domingo por defecto; acá sólo importa que estén las siete en español.
  const diasEs = ['dom', 'lun', 'mar', 'mié', 'jue', 'vie', 'sáb'];

  void expectCalendarioEnEspanol(String mes) {
    expect(find.text(mes), findsOneWidget);
    for (final dia in diasEs) {
      expect(find.text(dia), findsOneWidget, reason: 'falta «$dia»');
    }
  }

  group('agenda del PF (TrainerAgendaTab)', () {
    for (final caso in casos) {
      testWidgets('${caso.ahora} → «${caso.mes}» y días en español',
          (tester) async {
        AppClock.freeze(caso.ahora);
        addTearDown(AppClock.unfreeze);

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
      });
    }
  });

  group('agenda del alumno (AthleteAgendaScreen)', () {
    for (final caso in casos) {
      testWidgets('${caso.ahora} → «${caso.mes}» y días en español',
          (tester) async {
        AppClock.freeze(caso.ahora);
        addTearDown(AppClock.unfreeze);

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
