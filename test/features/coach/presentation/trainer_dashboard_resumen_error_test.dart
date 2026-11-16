import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/utils/app_clock.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/data/appointment_repository.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart'
    show trainerLinksStreamProvider;
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

// QA H3: el "Resumen del día" hacía `apptAsync.valueOrNull ?? []`, colapsando
// loading Y error a 0/0/0 — un permission-denied (App Check no registrado) se
// leía como un día tranquilo. Ahora distingue los estados con `.when`, igual
// que su hermano _ProximasSesionesList (mismo provider).

const _kTrainer = 'trainer-1';

UserProfile _trainer() => UserProfile(
      uid: _kTrainer,
      email: 'mateo@test.com',
      displayName: 'Mateo',
      role: UserRole.trainer,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

Future<void> _pump(
  WidgetTester tester, {
  required Override apptOverride,
  // #1729: el stream de cancelados. Por default, un día sin cancelados — así
  // los tests que sólo miran el stream de confirmados no dependen de Firebase.
  // `useRealCancelledStream` lo deja ir por el repositorio de `extraOverrides`.
  Override? cancelledOverride,
  bool useRealCancelledStream = false,
  List<Override> extraOverrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue(_kTrainer),
        userProfileProvider.overrideWith((ref) => Stream.value(_trainer())),
        userPublicProfileProvider.overrideWith(
          (ref, uid) => Stream<UserPublicProfile?>.value(null),
        ),
        trainerLinksStreamProvider
            .overrideWith((ref) => Stream.value(const <TrainerLink>[])),
        apptOverride,
        if (!useRealCancelledStream)
          cancelledOverride ??
              trainerCancelledAppointmentsStreamProvider.overrideWith(
                (ref, key) => Stream.value(const <Appointment>[]),
              ),
        ...extraOverrides,
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
  group('Resumen del día — estados del stream de turnos', () {
    testWidgets('error → muestra mensaje, NO 0/0/0', (tester) async {
      await _pump(
        tester,
        apptOverride: trainerAppointmentsStreamProvider.overrideWith(
          (ref, key) =>
              Stream<List<Appointment>>.error(Exception('permission-denied')),
        ),
      );

      expect(
          find.text('No pudimos cargar el resumen del día.'), findsOneWidget);
      // La fila de stats se reemplaza entera: sus labels desaparecen, así que
      // el PF no ve "0 PENDIENTES / 0 COMPLETADAS / 0 CANCELADAS" mintiendo.
      expect(find.text('PENDIENTES'), findsNothing);
    });

    testWidgets('data (día vacío legítimo) → 0/0/0 real, sin mensaje de error',
        (tester) async {
      await _pump(
        tester,
        apptOverride: trainerAppointmentsStreamProvider.overrideWith(
          (ref, key) => Stream.value(const <Appointment>[]),
        ),
      );

      // Con data real, 0/0/0 SÍ es correcto (día sin turnos) — y no hay error.
      expect(find.text('No pudimos cargar el resumen del día.'), findsNothing);
      expect(find.text('PENDIENTES'), findsOneWidget);
      expect(find.text('COMPLETADAS'), findsOneWidget);
    });

    testWidgets('loading → guiones, sin 0 ni mensaje de error', (tester) async {
      final controller = StreamController<List<Appointment>>();
      addTearDown(controller.close);
      await _pump(
        tester,
        apptOverride: trainerAppointmentsStreamProvider
            .overrideWith((ref, key) => controller.stream),
      );

      // Nunca emite → loading. Los stat columns muestran "—", no "0".
      expect(find.text('No pudimos cargar el resumen del día.'), findsNothing);
      expect(find.text('PENDIENTES'), findsOneWidget);
      expect(find.text('—'), findsWidgets);
    });
  });

  // #1729: CANCELADAS daba 0 siempre. El stream de confirmados (el único que
  // leía la tarjeta) no trae cancelados por construcción.
  group('Resumen del día — CANCELADAS (#1729)', () {
    // 2026-06-16 15:00 UTC = 12:00 en Argentina. Congelado como instante
    // local-flagged (lo que pide AppClock) para que el día ART no dependa de la
    // zona horaria de la máquina que corre el test.
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

    Appointment appt({
      required DateTime at,
      required AppointmentStatus status,
      String trainer = _kTrainer,
    }) =>
        Appointment.create(
          trainerId: trainer,
          athleteId: 'athlete-1',
          athleteDisplayName: 'Alumno',
          startsAt: at,
          durationMin: 60,
          status: status,
        );

    Override confirmed(List<Appointment> list) =>
        trainerAppointmentsStreamProvider
            .overrideWith((ref, key) => Stream.value(list));

    testWidgets(
        'con el repositorio real: un turno cancelado hoy cuenta, y los de '
        'otro día o de otro PF no', (tester) async {
      final firestore = FakeFirebaseFirestore();
      Future<void> seed(Appointment a) =>
          firestore.collection('appointments').doc(a.id).set(a.toJson());
      await seed(appt(
        at: today.add(const Duration(hours: 9)),
        status: AppointmentStatus.cancelled,
      ));
      await seed(appt(
        at: today.add(const Duration(hours: 10)),
        status: AppointmentStatus.cancelled,
      ));
      // Cancelado AYER y de OTRO PF: no son de hoy / no son de este PF.
      await seed(appt(
        at: today.subtract(const Duration(hours: 14)),
        status: AppointmentStatus.cancelled,
      ));
      await seed(appt(
        at: today.add(const Duration(hours: 11)),
        status: AppointmentStatus.cancelled,
        trainer: 'otro-pf',
      ));

      await _pump(
        tester,
        apptOverride: confirmed([
          appt(
            at: today.add(const Duration(hours: 18)),
            status: AppointmentStatus.confirmed,
          ),
        ]),
        useRealCancelledStream: true,
        extraOverrides: [
          appointmentRepositoryProvider.overrideWithValue(
            AppointmentRepository(firestore: firestore),
          ),
        ],
      );

      expect(statValue(tester, 'CANCELADAS'), '2');
      expect(statValue(tester, 'PENDIENTES'), '1');
    });

    testWidgets(
        'loading del stream de cancelados → "—" en esa columna, y '
        'pendientes/completadas siguen con su número', (tester) async {
      final controller = StreamController<List<Appointment>>();
      // Sin `await`: `close()` de un controller que nadie escuchó nunca
      // completa, y si la tarjeta deja de leer este stream el test se colgaría
      // 10 minutos en vez de fallar por el expect.
      addTearDown(() => unawaited(controller.close()));
      await _pump(
        tester,
        apptOverride: confirmed([
          appt(
            at: today.add(const Duration(hours: 18)),
            status: AppointmentStatus.confirmed,
          ),
          appt(
            at: today.add(const Duration(hours: 8)),
            status: AppointmentStatus.confirmed,
          ),
        ]),
        cancelledOverride: trainerCancelledAppointmentsStreamProvider
            .overrideWith((ref, key) => controller.stream),
      );

      expect(statValue(tester, 'CANCELADAS'), '—');
      expect(statValue(tester, 'PENDIENTES'), '1');
      expect(statValue(tester, 'COMPLETADAS'), '1');
    });

    testWidgets(
        'error del stream de cancelados → "—", NO 0 (un fallo no es un día '
        'tranquilo)', (tester) async {
      await _pump(
        tester,
        apptOverride: confirmed([
          appt(
            at: today.add(const Duration(hours: 18)),
            status: AppointmentStatus.confirmed,
          ),
        ]),
        cancelledOverride:
            trainerCancelledAppointmentsStreamProvider.overrideWith(
          (ref, key) => Stream<List<Appointment>>.error(
            Exception('permission-denied'),
          ),
        ),
      );

      expect(statValue(tester, 'CANCELADAS'), '—');
      expect(statValue(tester, 'PENDIENTES'), '1');
      expect(find.text('No pudimos cargar el resumen del día.'), findsNothing);
    });

    testWidgets('día sin cancelados → 0 real', (tester) async {
      await _pump(tester, apptOverride: confirmed(const []));

      expect(statValue(tester, 'CANCELADAS'), '0');
    });
  });
}
