// WU-05 (Fase 2) — Columna derecha: Próximas sesiones + Vencimientos 7d +
// Inactivos.
//
// RED → GREEN: cubre el contrato de extracción a
// dashboard/widgets/dashboard_right_column.dart (ADR-D2-05). ELIMINA los
// CircularProgressIndicator crudos de Próximas sesiones y Vencimientos 7d —
// todo loading pasa por el shimmer del kit vía TreinoListRow(loading: true).
//
// SCENARIO-RCOL-01/04/08: loading → skeleton TreinoListRow.
// SCENARIO-RCOL-02/05/09: data vacía → TreinoEmptyState.
// SCENARIO-RCOL-03/06/10: data con filas reales.
// SCENARIO-RCOL-07: Vencimientos "Ver todos" navega a /pagos (TreinoTappable).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach_hub/application/inactivos_provider.dart';
import 'package:treino/features/coach_hub/presentation/sections/dashboard/widgets/dashboard_right_column.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/pagos_buckets_provider.dart';
import 'package:treino/features/payments/domain/payment.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

// ─── Factories ────────────────────────────────────────────────────────────────

Appointment _confirmed({
  required String id,
  required String athleteDisplayName,
  required DateTime startsAt,
}) =>
    Appointment(
      id: id,
      trainerId: 'trainer-1',
      athleteId: 'a1',
      athleteDisplayName: athleteDisplayName,
      startsAt: startsAt,
      durationMin: 60,
      status: AppointmentStatus.confirmed,
    );

Payment _pendingPayment({
  required String id,
  required String athleteId,
  DateTime? createdAt,
}) =>
    Payment(
      id: id,
      trainerId: 'trainer-1',
      athleteId: athleteId,
      amountArs: 20000,
      concept: 'Mensualidad',
      status: PaymentStatus.pending,
      createdAt: createdAt ?? DateTime.utc(2025, 1, 1),
    );

UserPublicProfile _pub(String uid, String name) => UserPublicProfile(
      uid: uid,
      displayName: name,
      displayNameLowercase: name.toLowerCase(),
    );

// ─── Test helpers ─────────────────────────────────────────────────────────────

List<Override> _baseOverrides({
  Object? appointments,
  Object? buckets,
  Object? inactivos,
}) {
  return [
    currentUidProvider.overrideWithValue('trainer-1'),
    trainerAppointmentsStreamProvider.overrideWith(
      (ref, key) => appointments is Stream<List<Appointment>>
          ? appointments
          : Stream.value(appointments as List<Appointment>? ?? const []),
    ),
    pagosBucketsProvider.overrideWith(
      (ref) => buckets is AsyncValue<PagosBuckets>
          ? buckets
          : AsyncData(buckets as PagosBuckets? ??
              const PagosBuckets(
                vencidos: [],
                porVencer: [],
                pagados: [],
                todos: [],
              )),
    ),
    inactivosProvider.overrideWith(
      (ref) => inactivos is Future<InactivosResult>
          ? inactivos
          : Future.value(inactivos as InactivosResult? ??
              const InactivosResult(inactiveAthleteIds: [])),
    ),
  ];
}

Future<GoRouter> _pump(
  WidgetTester tester, {
  required List<Override> overrides,
}) async {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(
          body: SingleChildScrollView(child: DashboardRightColumn()),
        ),
      ),
      GoRoute(path: '/pagos', builder: (_, __) => const Text('page:/pagos')),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        routerConfig: router,
      ),
    ),
  );
  return router;
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('SCENARIO-RCOL-01 — próximas sesiones loading usa el skeleton', () {
    testWidgets('trainerAppointmentsStreamProvider loading → skeleton',
        (tester) async {
      final controller = StreamController<List<Appointment>>();
      addTearDown(controller.close);

      await _pump(
        tester,
        overrides: _baseOverrides(appointments: controller.stream),
      );
      await tester.pump();

      expect(find.byKey(const Key('list_row_skeleton')), findsWidgets);
    });
  });

  group('SCENARIO-RCOL-02 — próximas sesiones data vacía usa TreinoEmptyState',
      () {
    testWidgets('sin appointments → empty state', (tester) async {
      await _pump(
        tester,
        overrides: _baseOverrides(appointments: const <Appointment>[]),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('empty_state_content')), findsWidgets);
    });
  });

  group('SCENARIO-RCOL-03 — próximas sesiones con data real', () {
    testWidgets('muestra nombre del alumno en la fila', (tester) async {
      final now = DateTime.now().toUtc();
      await _pump(
        tester,
        overrides: _baseOverrides(appointments: [
          _confirmed(
            id: 's1',
            athleteDisplayName: 'Ana López',
            startsAt: now.add(const Duration(hours: 1)),
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Ana López'), findsOneWidget);
    });
  });

  group('SCENARIO-RCOL-04 — vencimientos loading usa el skeleton', () {
    testWidgets('pagosBucketsProvider loading → skeleton', (tester) async {
      await _pump(
        tester,
        overrides: _baseOverrides(buckets: const AsyncLoading<PagosBuckets>()),
      );
      await tester.pump();

      expect(find.byKey(const Key('list_row_skeleton')), findsWidgets);
    });
  });

  group('SCENARIO-RCOL-05 — vencimientos data vacía usa TreinoEmptyState', () {
    testWidgets('sin vencidos → empty state', (tester) async {
      await _pump(
        tester,
        overrides: _baseOverrides(
          buckets: const PagosBuckets(
            vencidos: [],
            porVencer: [],
            pagados: [],
            todos: [],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('empty_state_content')), findsWidgets);
    });
  });

  group('SCENARIO-RCOL-06 — vencimientos con data real muestra badge de días',
      () {
    testWidgets('fila con nombre + badge "+N d"', (tester) async {
      final payment = _pendingPayment(id: 'p1', athleteId: 'a1');
      await _pump(
        tester,
        overrides: [
          ..._baseOverrides(
            buckets: PagosBuckets(
              vencidos: [payment],
              porVencer: const [],
              pagados: const [],
              todos: [payment],
            ),
          ),
          userPublicProfileProvider('a1').overrideWith(
            (ref) => Stream.value(_pub('a1', 'Beto Ruiz')),
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Beto Ruiz'), findsOneWidget);
      expect(find.textContaining('d'), findsWidgets);
    });
  });

  group('SCENARIO-RCOL-07 — "Ver todos" navega a /pagos', () {
    testWidgets('tap en Ver todos navega a /pagos', (tester) async {
      final router = await _pump(tester, overrides: _baseOverrides());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('vencimientos_ver_todos')));
      await tester.pumpAndSettle();

      expect(find.text('page:/pagos'), findsOneWidget);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/pagos');
    });
  });

  group('SCENARIO-RCOL-08 — inactivos loading usa el skeleton', () {
    testWidgets('inactivosProvider pendiente → skeleton', (tester) async {
      final completer = Completer<InactivosResult>();
      addTearDown(() {
        if (!completer.isCompleted) {
          completer.complete(
            const InactivosResult(inactiveAthleteIds: []),
          );
        }
      });

      await _pump(
        tester,
        overrides: _baseOverrides(inactivos: completer.future),
      );
      await tester.pump();

      expect(find.byKey(const Key('list_row_skeleton')), findsWidgets);
    });
  });

  group('SCENARIO-RCOL-09 — inactivos data vacía usa TreinoEmptyState', () {
    testWidgets('sin inactivos → empty state', (tester) async {
      await _pump(
        tester,
        overrides: _baseOverrides(
          inactivos: const InactivosResult(inactiveAthleteIds: []),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('empty_state_content')), findsWidgets);
    });
  });

  group('SCENARIO-RCOL-10 — inactivos con data real', () {
    testWidgets('fila con nombre del alumno inactivo', (tester) async {
      await _pump(
        tester,
        overrides: [
          ..._baseOverrides(
            inactivos: const InactivosResult(inactiveAthleteIds: ['a1']),
          ),
          userPublicProfileProvider('a1').overrideWith(
            (ref) => Stream.value(_pub('a1', 'Carla Díaz')),
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Carla Díaz'), findsOneWidget);
    });
  });
}
