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
import 'package:flutter/services.dart';
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

Future<void> _pumpWithContainer(
  WidgetTester tester, {
  required ProviderContainer container,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const Scaffold(
          body: SingleChildScrollView(child: DashboardRightColumn()),
        ),
      ),
    ),
  );
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

  group('SCENARIO-RCOL-11 — accesibilidad de teclado de "Ver todos"', () {
    // Remediación CRITICAL#2 (sdd-verify fase-2): el link "Ver todos"
    // envolvía un TreinoTappable crudo (sin Focus ni Semantics) en vez de
    // TreinoInteractiveState, el resolver que expone el resto del kit.
    testWidgets(
        '"Ver todos": focusable, Semantics(button) y Enter navega a /pagos',
        (tester) async {
      final handle = tester.ensureSemantics();

      final router = await _pump(tester, overrides: _baseOverrides());
      await tester.pumpAndSettle();

      final semantics = tester.getSemantics(
        find.byKey(const Key('vencimientos_ver_todos')),
      );
      expect(semantics.flagsCollection.isButton, isTrue,
          reason: '"Ver todos" debe exponer Semantics(button: true)');

      final focusNode = Focus.of(
        tester.element(find.byKey(const Key('vencimientos_ver_todos'))),
      );
      focusNode.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('page:/pagos'), findsOneWidget,
          reason: 'Enter (teclado) debe activar el link igual que el tap');
      expect(router.routerDelegate.currentConfiguration.uri.path, '/pagos');

      handle.dispose();
    });
  });

  group(
      'SCENARIO-STALE — próximas sesiones persisten ante error transitorio '
      '(pulido-post-revision)', () {
    // Regression: trainerAppointmentsStreamProvider es un
    // StreamProvider.family en vivo — Riverpod 2.5+ preserva el valor
    // previo dentro de un AsyncError subsiguiente (copyWithPrevious/
    // "seamless"). Además, la extracción de `rows` usaba `.whenData()`
    // (== `.map()`, despacha por SUBTIPO RUNTIME) — en el estado compuesto
    // (hasValue && hasError) NO ejecuta el callback `data:`, así que
    // `rows` quedaba `null` y la sección caía al estado de error de
    // pantalla completa aunque el stream tuviera sesiones ya cargadas.
    // Fix: extracción vía `valueOrNull` + precedencia hasValue-first.
    testWidgets(
        'sesión ya cargada no desaparece tras un error transitorio del '
        'stream (stale-while-refresh)', (tester) async {
      final controller = StreamController<List<Appointment>>();
      addTearDown(controller.close);

      final container = ProviderContainer(
        overrides: _baseOverrides(appointments: controller.stream),
      );
      addTearDown(container.dispose);

      await _pumpWithContainer(tester, container: container);

      final now = DateTime.now().toUtc();
      controller.add([
        _confirmed(
          id: 's1',
          athleteDisplayName: 'Ana López',
          startsAt: now.add(const Duration(hours: 1)),
        ),
      ]);
      await tester.pumpAndSettle();

      expect(find.textContaining('Ana López'), findsOneWidget);

      controller.addError(Exception('transient stream hiccup'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Ana López'),
        findsOneWidget,
        reason: 'un error transitorio con data ya cargada no debe tapar '
            'la sesión próxima',
      );
    });
  });

  group(
      'SCENARIO-STALE — vencimientos hasValue-first, defensa en profundidad '
      '(pulido-post-revision)', () {
    // pagosBucketsProvider ya está corregido a nivel provider (commit
    // b3a14117) y no debería emitir un AsyncValue compuesto — pero el
    // widget también se flipea a hasValue-first por defensa en
    // profundidad. Este test construye el AsyncValue compuesto
    // manualmente (copyWithPrevious) para probar la precedencia del
    // widget independientemente de la garantía del provider.
    testWidgets(
        'AsyncValue compuesto (hasValue && hasError) muestra la data, no '
        'el error de pantalla completa', (tester) async {
      final payment = _pendingPayment(id: 'p1', athleteId: 'a1');
      final data = AsyncValue<PagosBuckets>.data(
        PagosBuckets(
          vencidos: [payment],
          porVencer: const [],
          pagados: const [],
          todos: [payment],
        ),
      );
      final compound = AsyncValue<PagosBuckets>.error(
        Exception('transient stream hiccup'),
        StackTrace.current,
      ).copyWithPrevious(data);

      await _pump(
        tester,
        overrides: [
          ..._baseOverrides(buckets: compound),
          userPublicProfileProvider('a1').overrideWith(
            (ref) => Stream.value(_pub('a1', 'Beto Ruiz')),
          ),
        ],
      );
      await tester.pumpAndSettle();

      final l10n = AppL10n.of(tester.element(find.byType(Scaffold)));
      expect(find.textContaining('Beto Ruiz'), findsOneWidget);
      expect(find.text(l10n.coachHubSectionLoadError), findsNothing);
    });
  });

  group(
      'SCENARIO-STALE — inactivos persisten ante error transitorio '
      '(pulido-post-revision)', () {
    // Regression: inactivosProvider es un FutureProvider que hace fan-out
    // sobre finishedInWindowByUidProvider. Si ese fan-out lanza un error
    // transitorio en un rebuild posterior a un cómputo exitoso, Riverpod
    // preserva el valor previo dentro del AsyncError resultante (mismo
    // copyWithPrevious/"seamless", no exclusivo de StreamProvider). El
    // widget chequeaba hasError ANTES que el resultado ya cargado, así que
    // tapaba la lista de inactivos con el error de pantalla completa.
    testWidgets(
        'lista de inactivos ya cargada no desaparece tras un error '
        'transitorio del future compuesto', (tester) async {
      final attempt = StateProvider<int>((ref) => 0);

      final container = ProviderContainer(overrides: [
        currentUidProvider.overrideWithValue('trainer-1'),
        trainerAppointmentsStreamProvider.overrideWith(
          (ref, key) => Stream.value(const <Appointment>[]),
        ),
        pagosBucketsProvider.overrideWith(
          (ref) => const AsyncData(
            PagosBuckets(
              vencidos: [],
              porVencer: [],
              pagados: [],
              todos: [],
            ),
          ),
        ),
        inactivosProvider.overrideWith((ref) async {
          if (ref.watch(attempt) == 0) {
            return const InactivosResult(inactiveAthleteIds: ['a1']);
          }
          throw Exception('transient fan-out hiccup');
        }),
        userPublicProfileProvider('a1').overrideWith(
          (ref) => Stream.value(_pub('a1', 'Carla Díaz')),
        ),
      ]);
      addTearDown(container.dispose);

      await _pumpWithContainer(tester, container: container);
      await tester.pumpAndSettle();

      expect(find.textContaining('Carla Díaz'), findsOneWidget);

      container.read(attempt.notifier).state = 1;
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Carla Díaz'),
        findsOneWidget,
        reason: 'un error transitorio del fan-out no debe tapar la lista '
            'de inactivos ya calculada',
      );
    });
  });
}
