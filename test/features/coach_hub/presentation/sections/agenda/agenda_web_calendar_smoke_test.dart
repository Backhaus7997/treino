import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach_hub/presentation/sections/agenda/agenda_web_screen.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

/// Web calendar smoke test — SCENARIO-101-A/B.
///
/// Validates that TableCalendar renders without web-gesture crashes on a
/// TargetPlatform.linux host (which is the default for flutter test on the
/// CI machine). Web gesture issues surface as assertion failures or platform
/// channel exceptions during pump.
void main() {
  group('AgendaWebScreen — TableCalendar smoke', () {
    Widget buildScreen({List<Appointment> appointments = const []}) =>
        ProviderScope(
          overrides: [
            currentUidProvider.overrideWithValue('trainer-smoke-uid'),
            trainerAppointmentsStreamProvider.overrideWith(
              (ref, key) => Stream.value(appointments),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            home: const Scaffold(body: AgendaWebScreen()),
          ),
        );

    testWidgets(
        'SCENARIO-101-A — calendar pumps without errors (no appointments)',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      // TableCalendar must exist — if web gestures crash, this either throws or
      // the widget won't be found.
      expect(find.byType(TableCalendar<dynamic>), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-101-A — calendar pumps without errors (with appointments)',
        (tester) async {
      final now = DateTime.now().toUtc();
      final tomorrow = DateTime.utc(now.year, now.month, now.day + 1, 10, 0);
      final appt = Appointment(
        id: 'smoke-appt-1',
        trainerId: 'trainer-smoke-uid',
        athleteId: 'athlete-smoke',
        athleteDisplayName: 'Atleta Smoke',
        startsAt: tomorrow,
        durationMin: 60,
        status: AppointmentStatus.confirmed,
      );

      await tester.pumpWidget(buildScreen(appointments: [appt]));
      await tester.pumpAndSettle();

      expect(find.byType(TableCalendar<dynamic>), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-101-B — week/month toggle button present and tappable',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      // In month view (default): format button shows "Semana" (switch to week)
      expect(find.text('Semana'), findsOneWidget); // i18n

      await tester.tap(find.text('Semana'));
      await tester.pumpAndSettle();

      // In week view: format button shows "Mes" (switch back to month)
      expect(find.text('Mes'), findsOneWidget); // i18n

      // TableCalendar is still alive after toggle
      expect(find.byType(TableCalendar<dynamic>), findsOneWidget);
    });
  });
}
