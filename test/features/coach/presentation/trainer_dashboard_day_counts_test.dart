// Regression test for the "Resumen del día" classification bug:
// an in-progress confirmed session (started but not yet ended) must count as
// PENDING — not DONE. A session only becomes DONE once startsAt + durationMin
// has elapsed. See dashboardDayCounts in trainer_dashboard_tab.dart.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/utils/app_clock.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart'
    show trainerLinksStreamProvider;
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/presentation/trainer_dashboard_tab.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart'
    show userPublicProfileProvider;
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

Appointment _appt({
  required DateTime startsAt,
  required int durationMin,
  AppointmentStatus status = AppointmentStatus.confirmed,
  AppointmentAttendance? attendance,
}) {
  return Appointment(
    id: 't_${startsAt.millisecondsSinceEpoch}',
    trainerId: 't',
    athleteId: 'a',
    athleteDisplayName: 'Alumno',
    startsAt: startsAt,
    durationMin: durationMin,
    status: status,
    attendance: attendance,
  );
}

const _kTrainer = 'trainer-1';

Future<void> _pumpCard(
  WidgetTester tester,
  List<Appointment> appointments,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue(_kTrainer),
        userProfileProvider.overrideWith(
          (ref) => Stream.value(UserProfile(
            uid: _kTrainer,
            email: 'mateo@test.com',
            displayName: 'Mateo',
            role: UserRole.trainer,
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          )),
        ),
        userPublicProfileProvider.overrideWith(
          (ref, uid) => Stream<UserPublicProfile?>.value(null),
        ),
        trainerLinksStreamProvider
            .overrideWith((ref) => Stream.value(const <TrainerLink>[])),
        trainerAppointmentsStreamProvider
            .overrideWith((ref, key) => Stream.value(appointments)),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const Scaffold(body: TrainerDashboardTab()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('dashboardDayCounts — done/pending split by session end', () {
    test(
      'in-progress session (started 5 min ago, 60 min long) counts as pending, '
      'not done',
      () {
        final now = DateTime.utc(2026, 6, 16, 10, 5);
        final inProgress = _appt(
          startsAt: DateTime.utc(2026, 6, 16, 10, 0), // started 5 min ago
          durationMin: 60, // ends at 11:00 — still ongoing
        );

        final counts = dashboardDayCounts([inProgress], now);

        expect(counts.pending, 1, reason: 'ongoing session must stay pending');
        expect(counts.done, 0, reason: 'must not be counted as completed yet');
        expect(counts.cancelled, 0);
      },
    );

    test('session whose end has passed counts as done', () {
      final now = DateTime.utc(2026, 6, 16, 11, 30);
      final finished = _appt(
        startsAt: DateTime.utc(2026, 6, 16, 10, 0),
        durationMin: 60, // ended at 11:00, before now (11:30)
      );

      final counts = dashboardDayCounts([finished], now);

      expect(counts.done, 1);
      expect(counts.pending, 0);
    });

    test('future session counts as pending', () {
      final now = DateTime.utc(2026, 6, 16, 9, 0);
      final future = _appt(
        startsAt: DateTime.utc(2026, 6, 16, 18, 0),
        durationMin: 45,
      );

      final counts = dashboardDayCounts([future], now);

      expect(counts.pending, 1);
      expect(counts.done, 0);
    });

    test('cancelled session is counted as cancelled, never pending/done', () {
      final now = DateTime.utc(2026, 6, 16, 12, 0);
      final cancelled = _appt(
        startsAt: DateTime.utc(2026, 6, 16, 10, 0),
        durationMin: 60,
        status: AppointmentStatus.cancelled,
      );

      final counts = dashboardDayCounts([cancelled], now);

      expect(counts.cancelled, 1);
      expect(counts.pending, 0);
      expect(counts.done, 0);
    });

    test('only today\'s appointments are classified', () {
      final now = DateTime.utc(2026, 6, 16, 12, 0);
      final yesterday = _appt(
        startsAt: DateTime.utc(2026, 6, 15, 10, 0),
        durationMin: 60,
      );
      final today = _appt(
        startsAt: DateTime.utc(2026, 6, 16, 18, 0),
        durationMin: 60,
      );

      final counts = dashboardDayCounts([yesterday, today], now);

      expect(counts.pending, 1, reason: 'only today\'s future session counts');
      expect(counts.done, 0);
    });
  });

  // #1737: el PF marca una sesión ausente (#1492) y el Resumen del día la
  // contaba como COMPLETADA. El conteo puro está en
  // `application/dashboard_day_counts_test.dart`; esto cubre la tarjeta.
  group('Resumen del día — AUSENTES (#1737)', () {
    // 2026-06-16 15:00 UTC = 12:00 en Argentina. Congelado como instante
    // local-flagged (lo que pide AppClock): el día ART no depende de la zona
    // horaria de la máquina que corre el test.
    final frozen = DateTime.utc(2026, 6, 16, 15, 0).toLocal();
    final today = DateTime.utc(2026, 6, 16);

    setUp(() => AppClock.freeze(frozen));
    tearDown(AppClock.unfreeze);

    // El valor grande de la columna cuyo label es [label].
    String statValue(WidgetTester tester, String label) {
      final column = find
          .ancestor(of: find.text(label), matching: find.byType(Column))
          .first;
      return find
          .descendant(of: column, matching: find.byType(Text))
          .evaluate()
          .map((e) => (e.widget as Text).data!)
          .first;
    }

    Appointment at(
      int hour, {
      AppointmentAttendance? attendance,
    }) =>
        _appt(
          startsAt: today.add(Duration(hours: hour)),
          durationMin: 60,
          attendance: attendance,
        );

    testWidgets(
        'un turno terminado y marcado ausente cuenta en AUSENTES y NO en '
        'COMPLETADAS', (tester) async {
      await _pumpCard(tester, [
        at(8), // terminó, se dio
        at(9, attendance: AppointmentAttendance.absent), // terminó, faltó
        at(18), // todavía no empezó
      ]);

      expect(statValue(tester, 'COMPLETADAS'), '1');
      expect(statValue(tester, 'AUSENTES'), '1');
      expect(statValue(tester, 'PENDIENTES'), '1');
    });

    testWidgets('sin ausentes la columna dice 0, no desaparece',
        (tester) async {
      await _pumpCard(tester, [at(8)]);

      expect(statValue(tester, 'AUSENTES'), '0');
      expect(statValue(tester, 'COMPLETADAS'), '1');
    });

    // 360 es el ancho de teléfono más común; 320 el más angosto que todavía
    // se usa. A 360 los labels no se achican (con los 8 px de margen que tenía
    // el divisor, «COMPLETADAS» pasaba a ~9 px); a 320 sí, pero siguen enteros.
    for (final width in [360.0, 320.0]) {
      testWidgets(
          'las cuatro columnas entran a $width px sin overflow ni labels '
          'partidos', (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await _pumpCard(tester, [
          at(8),
          at(9, attendance: AppointmentAttendance.absent),
        ]);

        expect(tester.takeException(), isNull);
        for (final label in [
          'PENDIENTES',
          'COMPLETADAS',
          'AUSENTES',
          'CANCELADAS',
        ]) {
          final natural = tester.getSize(find.text(label));
          final labelBox = find
              .ancestor(of: find.text(label), matching: find.byType(FittedBox))
              .first;
          final column =
              find.ancestor(of: labelBox, matching: find.byType(Column)).first;
          final shown = tester.getSize(labelBox).width;
          // Una sola línea: el alto del texto es el de una línea de 10 px.
          expect(natural.height, lessThan(16), reason: label);
          // El label (ya escalado) no se sale de su columna.
          expect(
            shown,
            lessThanOrEqualTo(tester.getSize(column).width),
            reason: label,
          );
          if (width >= 360) {
            expect(shown, greaterThan(natural.width * 0.95), reason: label);
          }
        }
      });
    }
  });
}
