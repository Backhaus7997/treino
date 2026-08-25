// Tests for the Coach Hub web Alumnos roster (W2 PR1 + Fase 3 WU-03 redesign).
//
// Unit: estadoForLink composite-state derivation.
// Widget: roster rows + estados, filter chips, name search, empty state,
// Con-deuda badge, "Hoy" column, partition counts, link actions, the
// per-athlete dedup, and (Fase 3 WU-03) the CoachHubDataTable + TreinoFilterChips
// redesign — loading/error states, filter badges and detail navigation —
// pumped with stubbed providers (no Firestore).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/chat/domain/chat.dart';
import 'package:treino/features/coach/application/nutrition_plan_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/data/trainer_link_repository.dart';
import 'package:treino/features/coach/domain/nutrition_plan.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/alumnos/alumnos_screen.dart';
import 'package:treino/features/coach_hub/presentation/sections/chat/chat_section_screen.dart'
    show selectedChatIdProvider;
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/payment_format.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';
import 'package:treino/features/gyms/application/gym_providers.dart';
import 'package:treino/features/gyms/domain/gym.dart';
import 'package:treino/features/payments/application/pagos_por_cobrar_provider.dart';
import 'package:treino/features/payments/application/payment_providers.dart';
import 'package:treino/features/payments/data/payment_repository.dart';
import 'package:treino/features/payments/domain/athlete_billing.dart';
import 'package:treino/features/payments/domain/payment.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_status.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';

class _MockRepo extends Mock implements TrainerLinkRepository {}

class _MockPaymentRepo extends Mock implements PaymentRepository {}

// Trainer fijo del roster de test — usado tanto en `TrainerLink.trainerId`
// como en el override de `currentUidProvider` que consume
// `nutricionEntriesProvider` para armar la key de `nutritionPlanProvider`
// (columna «Nutrición»).
const _trainerId = 't1';

TrainerLink _link(String athleteId, TrainerLinkStatus status, {String? id}) =>
    TrainerLink(
      id: id ?? 'l_$athleteId',
      trainerId: _trainerId,
      athleteId: athleteId,
      status: status,
      requestedAt: DateTime.utc(2026, 1, 1),
    );

UserPublicProfile _prof(String uid, String name) =>
    UserPublicProfile(uid: uid, displayName: name);

CobroPendiente _cobro(String athleteId) => CobroPendiente(
      athleteId: athleteId,
      amountArs: 1000,
      cadence: BillingCadence.mensual,
      concept: 'Mensualidad',
    );

/// Pago del alumno — usado para overridear `trainerPaymentsProvider`
/// (columna «Vencimiento», vía `pagosBucketsProvider` — dueAt-aware, a
/// diferencia de `pagosPorCobrarProvider`).
Payment _payment(
  String athleteId, {
  required PaymentStatus status,
  DateTime? dueAt,
  DateTime? createdAt,
  String id = 'p1',
}) =>
    Payment(
      id: id,
      trainerId: _trainerId,
      athleteId: athleteId,
      amountArs: 1000,
      concept: 'Mensualidad',
      status: status,
      createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
      dueAt: dueAt,
    );

/// Sesión finalizada en [finishedAt] — usada para overridear
/// `finishedInWindowByUidProvider` (columna «Último entreno»).
Session _sessionAt(String uid, DateTime finishedAt) => Session(
      id: 's_$uid',
      uid: uid,
      routineId: 'r1',
      routineName: 'Push',
      startedAt: finishedAt.subtract(const Duration(hours: 1)),
      finishedAt: finishedAt,
      status: SessionStatus.finished,
    );

/// Rutina asignada — usada para overridear `assignedRoutinesProvider`
/// (columna «Rutina»).
Routine _routine(String id, {RoutineStatus status = RoutineStatus.active}) =>
    Routine(
      id: id,
      name: 'Hipertrofia',
      level: ExperienceLevel.intermediate,
      days: const [],
      status: status,
    );

/// Plan de nutrición del alumno — usada para overridear
/// `nutritionPlanProvider` (columna «Nutrición», vía `nutricionEntriesProvider`
/// de Fase 6, reutilizado — no se duplica la agregación).
NutritionPlan _plan(String athleteId) => NutritionPlan(
      id: '${_trainerId}_$athleteId',
      trainerId: _trainerId,
      athleteId: athleteId,
      title: 'Plan de $athleteId',
      updatedAt: DateTime.utc(2026, 1, 5),
      meals: const [],
    );

/// Pumpea `AlumnosScreen` detrás de un GoRouter (para que `onRowTap` →
/// `context.go('/alumnos/:id')` tenga a dónde ir) con los providers stub.
Future<void> _pump(
  WidgetTester tester, {
  Stream<List<TrainerLink>>? linksStream,
  List<TrainerLink>? links,
  List<UserPublicProfile> profiles = const [],
  List<CobroPendiente> cobros = const [],
  // Sesiones finalizadas dentro de la ventana de 30d (columna «Último
  // entreno»), por athleteId. Ignora los bounds exactos de la key (from/to
  // dependen del wall-clock del widget) — mismo criterio que
  // inactivos_provider_test.dart.
  Map<String, List<Session>> sessionsInWindowByAthleteId = const {},
  // Rutinas asignadas por athleteId (columna «Rutina»).
  Map<String, List<Routine>> routinesByAthleteId = const {},
  // Plan de nutrición por athleteId (columna «Nutrición»). Los alumnos que
  // no aparecen acá quedan en `null` (Fase 6: "sin plan") — evita que
  // `nutricionEntriesProvider` pegue contra el repo real (sin Firebase en
  // los tests).
  Map<String, NutritionPlan?> plansByAthleteId = const {},
  // Pagos del trainer (columna «Vencimiento», vía `pagosBucketsProvider`).
  List<Payment> payments = const [],
  TrainerLinkRepository? repo,
  // Repo de pagos — usado por el botón «Registrar pago» del roster (reusa
  // `registrarPago` de la sección Pagos).
  PaymentRepository? paymentRepo,
  // `false` para casos donde el stream de links queda colgado en loading a
  // propósito (TreinoShimmer corre en loop infinito — pumpAndSettle no
  // termina nunca ahí; el caller pumpea manualmente en su lugar).
  bool settle = true,
  // Ancho lógico de la ventana (px) — default 1200 (wide, breakpoint 900px).
  // Los tests de responsive lo bajan a <900 para forzar el layout angosto.
  double width = 1200,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/alumnos',
    routes: [
      GoRoute(
        path: '/alumnos',
        builder: (_, __) => const Scaffold(body: AlumnosScreen()),
      ),
      GoRoute(
        path: '/alumnos/:id',
        builder: (_, state) =>
            Scaffold(body: Text('DETALLE ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/rutinas/:athleteId',
        builder: (_, state) => Scaffold(
          body: Text('RUTINAS ${state.pathParameters['athleteId']}'),
        ),
      ),
      GoRoute(
        path: '/chat',
        // Muestra el `chatId` seleccionado (vía `selectedChatIdProvider`) para
        // verificar que el botón «Chat» del roster lo fijó antes de navegar.
        builder: (_, __) => Consumer(
          builder: (context, ref, __) => Scaffold(
            body: Text('CHAT ${ref.watch(selectedChatIdProvider)}'),
          ),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        trainerLinksStreamProvider.overrideWith(
          (ref) => linksStream ?? Stream.value(links ?? const []),
        ),
        userPublicProfilesBatchProvider.overrideWith(
          (ref, key) => {for (final p in profiles) p.uid: p},
        ),
        pagosPorCobrarProvider.overrideWith((ref) => AsyncData(cobros)),
        trainerPaymentsProvider.overrideWith((ref) => Stream.value(payments)),
        finishedInWindowByUidProvider.overrideWith(
          (ref, key) =>
              sessionsInWindowByAthleteId[key.athleteId] ?? const <Session>[],
        ),
        gymsProvider.overrideWith((ref) => const <Gym>[]),
        assignedRoutinesProvider.overrideWith(
          (ref, athleteId) async =>
              routinesByAthleteId[athleteId] ?? const <Routine>[],
        ),
        currentUidProvider.overrideWithValue(_trainerId),
        // Botón «Chat» del roster: resuelve/crea el chat 1-1 con el alumno
        // sin pegar contra Firestore real.
        chatForOtherUidProvider.overrideWith(
          (ref, otherUid) async => Chat(
            chatId: 'chat_$otherUid',
            members: [_trainerId, otherUid],
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        ),
        if (paymentRepo != null)
          paymentRepositoryProvider.overrideWithValue(paymentRepo),
        for (final athleteId in {
          for (final l in links ?? const []) l.athleteId
        })
          nutritionPlanProvider(
            (trainerId: _trainerId, athleteId: athleteId),
          ).overrideWith(
            (ref) => Stream.value(plansByAthleteId[athleteId]),
          ),
        if (repo != null) trainerLinkRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        routerConfig: router,
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue('');
    registerFallbackValue(_payment('fallback', status: PaymentStatus.paid));
  });

  group('estadoForLink (estado compuesto)', () {
    test('active sin deuda → activo', () {
      expect(estadoForLink(_link('a1', TrainerLinkStatus.active), const {}),
          AlumnoEstado.activo);
    });
    test('active con deuda → conDeuda', () {
      expect(estadoForLink(_link('a1', TrainerLinkStatus.active), {'a1'}),
          AlumnoEstado.conDeuda);
    });
    test('paused → pausado', () {
      expect(estadoForLink(_link('a2', TrainerLinkStatus.paused), const {}),
          AlumnoEstado.pausado);
    });
    test('terminated → inactivo', () {
      expect(estadoForLink(_link('a3', TrainerLinkStatus.terminated), const {}),
          AlumnoEstado.inactivo);
    });
    test('pending → inactivo (no es parte del roster activo)', () {
      expect(estadoForLink(_link('a4', TrainerLinkStatus.pending), const {}),
          AlumnoEstado.inactivo);
    });
  });

  group('AlumnoEstadoX.color (dot semántico — feedback de revisión)', () {
    const p = AppPalette.mintMagenta;
    test('activo → accent (mint)', () {
      expect(AlumnoEstado.activo.color(p), p.accent);
    });
    test('pausado → warning', () {
      expect(AlumnoEstado.pausado.color(p), p.warning);
    });
    test('conDeuda → danger', () {
      expect(AlumnoEstado.conDeuda.color(p), p.danger);
    });
    test('inactivo → textMuted', () {
      expect(AlumnoEstado.inactivo.color(p), p.textMuted);
    });
  });

  group('lastWorkoutLabel (columna «Último entreno», ventana 30d)', () {
    final l10n = lookupAppL10n(const Locale('es', 'AR'));
    final todayStart = DateTime.utc(2026, 6, 15);

    test('sin sesión en la ventana → "Sin entrenos" (honesto, no "—")', () {
      expect(lastWorkoutLabel(l10n, null, todayStart), 'Sin entrenos');
    });

    test('sesión finalizada hoy → "Hoy" (l10n existente)', () {
      final finishedAt = DateTime.utc(2026, 6, 15, 20, 0);
      expect(
        lastWorkoutLabel(l10n, finishedAt, todayStart),
        l10n.coachHubAlumnosLastWorkoutToday,
      );
    });

    test('sesión finalizada ayer → "Ayer"', () {
      final finishedAt = DateTime.utc(2026, 6, 14, 9, 0);
      expect(lastWorkoutLabel(l10n, finishedAt, todayStart), 'Ayer');
    });

    test('sesión finalizada hace 5 días → "Hace 5 días"', () {
      final finishedAt = DateTime.utc(2026, 6, 10, 9, 0);
      expect(lastWorkoutLabel(l10n, finishedAt, todayStart), 'Hace 5 días');
    });

    test('sesión finalizada hace 1 día exacto (borde) → "Ayer"', () {
      final finishedAt = todayStart.subtract(const Duration(hours: 1));
      expect(lastWorkoutLabel(l10n, finishedAt, todayStart), 'Ayer');
    });
  });

  group('vencimientoInfoFor (columna «Vencimiento»)', () {
    final now = DateTime.utc(2026, 6, 15);

    test('sin pagos del alumno → sin cuota', () {
      final info = vencimientoInfoFor(const [], 'a1', now);
      expect(info.vencido, isFalse);
      expect(info.proximaFecha, isNull);
    });

    test('pago vencido → vencido true, sin fecha', () {
      final info = vencimientoInfoFor(
        [
          _payment(
            'a1',
            status: PaymentStatus.pending,
            dueAt: now.subtract(const Duration(days: 2)),
          ),
        ],
        'a1',
        now,
      );
      expect(info.vencido, isTrue);
      expect(info.proximaFecha, isNull);
    });

    test('pago por vencer → toma su dueAt', () {
      final dueAt = now.add(const Duration(days: 4));
      final info = vencimientoInfoFor(
        [_payment('a1', status: PaymentStatus.pending, dueAt: dueAt)],
        'a1',
        now,
      );
      expect(info.vencido, isFalse);
      expect(info.proximaFecha, dueAt);
    });

    test('varios pagos por vencer → toma el dueAt más próximo', () {
      final lejos = now.add(const Duration(days: 20));
      final cerca = now.add(const Duration(days: 2));
      final info = vencimientoInfoFor(
        [
          _payment('a1', id: 'p1', status: PaymentStatus.pending, dueAt: lejos),
          _payment('a1', id: 'p2', status: PaymentStatus.pending, dueAt: cerca),
        ],
        'a1',
        now,
      );
      expect(info.vencido, isFalse);
      expect(info.proximaFecha, cerca);
    });

    test('vencido y por vencer a la vez → prioriza vencido (peor caso)', () {
      final info = vencimientoInfoFor(
        [
          _payment(
            'a1',
            id: 'p_venc',
            status: PaymentStatus.pending,
            dueAt: now.subtract(const Duration(days: 1)),
          ),
          _payment(
            'a1',
            id: 'p_por_vencer',
            status: PaymentStatus.pending,
            dueAt: now.add(const Duration(days: 10)),
          ),
        ],
        'a1',
        now,
      );
      expect(info.vencido, isTrue);
      expect(info.proximaFecha, isNull);
    });

    test('pago de otro alumno no cuenta', () {
      final info = vencimientoInfoFor(
        [
          _payment(
            'otro',
            status: PaymentStatus.pending,
            dueAt: now.subtract(const Duration(days: 5)),
          ),
        ],
        'a1',
        now,
      );
      expect(info.vencido, isFalse);
      expect(info.proximaFecha, isNull);
    });

    test('pago pagado no cuenta ni como vencido ni como por vencer', () {
      final info = vencimientoInfoFor(
        [
          _payment(
            'a1',
            status: PaymentStatus.paid,
            dueAt: now.subtract(const Duration(days: 5)),
          ),
        ],
        'a1',
        now,
      );
      expect(info.vencido, isFalse);
      expect(info.proximaFecha, isNull);
    });
  });

  group('AlumnosScreen roster (W2 PR1)', () {
    testWidgets('renderiza nombres + estados de los alumnos', (tester) async {
      await _pump(
        tester,
        links: [
          _link('a1', TrainerLinkStatus.active),
          _link('a2', TrainerLinkStatus.paused),
          _link('a3', TrainerLinkStatus.terminated),
        ],
        profiles: [
          _prof('a1', 'Sofía'),
          _prof('a2', 'Diego'),
          _prof('a3', 'Aldo'),
        ],
      );

      expect(find.text('ALUMNOS'), findsOneWidget);
      expect(find.text('Sofía'), findsOneWidget);
      expect(find.text('Diego'), findsOneWidget);
      expect(find.text('Aldo'), findsOneWidget);
      expect(find.text('Activo'), findsOneWidget);
      expect(find.text('Pausado'), findsOneWidget);
      expect(find.text('Inactivo'), findsOneWidget);
    });

    testWidgets('filtro Pausados muestra solo pausados', (tester) async {
      await _pump(
        tester,
        links: [
          _link('a1', TrainerLinkStatus.active),
          _link('a2', TrainerLinkStatus.paused),
        ],
        profiles: [_prof('a1', 'Sofía'), _prof('a2', 'Diego')],
      );

      await tester.tap(find.byKey(const Key('filter_chip_Pausados')));
      await tester.pumpAndSettle();

      expect(find.text('Diego'), findsOneWidget);
      expect(find.text('Sofía'), findsNothing);
    });

    testWidgets('búsqueda filtra por nombre', (tester) async {
      await _pump(
        tester,
        links: [
          _link('a1', TrainerLinkStatus.active),
          _link('a2', TrainerLinkStatus.active),
        ],
        profiles: [_prof('a1', 'Sofía Méndez'), _prof('a2', 'Diego Torres')],
      );

      await tester.enterText(find.byType(TextField), 'diego');
      await tester.pumpAndSettle();

      expect(find.text('Diego Torres'), findsOneWidget);
      expect(find.text('Sofía Méndez'), findsNothing);
    });

    testWidgets('sin alumnos → estado vacío', (tester) async {
      await _pump(tester, links: const []);
      expect(find.text('Todavía no tenés alumnos vinculados.'), findsOneWidget);
      expect(find.byType(CoachHubDataTable), findsOneWidget);
    });

    testWidgets('active con deuda → badge Con deuda y NO cuenta como activo',
        (tester) async {
      await _pump(
        tester,
        links: [_link('a1', TrainerLinkStatus.active)],
        profiles: [_prof('a1', 'Sofía')],
        cobros: [_cobro('a1')],
      );

      // El label del chip de filtro "Con deuda" y el badge de estado de la
      // fila comparten texto — se busca el badge dentro de la fila.
      expect(
        find.descendant(
          of: find.byKey(const Key('data_table_row_a1')),
          matching: find.text('Con deuda'),
        ),
        findsOneWidget,
      );
      // Partición: con-deuda NO se cuenta bajo activos (mockup).
      expect(find.text('1 en total · 0 activos'), findsOneWidget);
    });

    testWidgets('entrenó hoy → columna muestra "Hoy"', (tester) async {
      await _pump(
        tester,
        links: [_link('a1', TrainerLinkStatus.active)],
        profiles: [_prof('a1', 'Sofía')],
        sessionsInWindowByAthleteId: {
          'a1': [_sessionAt('a1', DateTime.now().toUtc())],
        },
      );
      expect(find.text('Hoy'), findsOneWidget);
    });

    testWidgets('entrenó ayer → columna muestra "Ayer"', (tester) async {
      await _pump(
        tester,
        links: [_link('a1', TrainerLinkStatus.active)],
        profiles: [_prof('a1', 'Sofía')],
        sessionsInWindowByAthleteId: {
          'a1': [
            _sessionAt(
              'a1',
              DateTime.now().toUtc().subtract(const Duration(days: 1)),
            ),
          ],
        },
      );
      expect(find.text('Ayer'), findsOneWidget);
    });

    testWidgets(
        'entrenó hace varios días (dentro de la ventana) → "Hace N días"',
        (tester) async {
      await _pump(
        tester,
        links: [_link('a1', TrainerLinkStatus.active)],
        profiles: [_prof('a1', 'Sofía')],
        sessionsInWindowByAthleteId: {
          'a1': [
            _sessionAt(
              'a1',
              DateTime.now().toUtc().subtract(const Duration(days: 5)),
            ),
          ],
        },
      );
      expect(find.text('Hace 5 días'), findsOneWidget);
    });

    testWidgets('sin entrenos en la ventana → columna muestra "Sin entrenos"',
        (tester) async {
      await _pump(
        tester,
        links: [_link('a1', TrainerLinkStatus.active)],
        profiles: [_prof('a1', 'Sofía')],
      );
      expect(find.text('Sin entrenos'), findsOneWidget);
    });

    testWidgets('terminar abre diálogo y al confirmar llama repo.terminate',
        (tester) async {
      final repo = _MockRepo();
      when(() => repo.terminate(any(), reason: any(named: 'reason')))
          .thenAnswer((_) async {});

      await _pump(
        tester,
        links: [_link('a1', TrainerLinkStatus.active)],
        profiles: [_prof('a1', 'Sofía')],
        repo: repo,
      );

      // #568: pausar/reanudar/terminar viven en el menú ⋮, no sueltas en la
      // fila. Hay que abrirlo antes de tocar la acción.
      await tester.tap(find.byTooltip('Opciones del alumno'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Terminar').last);
      await tester.pumpAndSettle();
      expect(
          find.text('Terminar vínculo'), findsOneWidget); // título del diálogo

      await tester.tap(find.text('Terminar')); // botón confirmar
      await tester.pumpAndSettle();

      verify(() => repo.terminate('l_a1', reason: 'trainer-terminated'))
          .called(1);
    });

    testWidgets('cancelar el diálogo NO llama al repo', (tester) async {
      final repo = _MockRepo();
      when(() => repo.terminate(any(), reason: any(named: 'reason')))
          .thenAnswer((_) async {});

      await _pump(
        tester,
        links: [_link('a1', TrainerLinkStatus.active)],
        profiles: [_prof('a1', 'Sofía')],
        repo: repo,
      );

      // #568: pausar/reanudar/terminar viven en el menú ⋮, no sueltas en la
      // fila. Hay que abrirlo antes de tocar la acción.
      await tester.tap(find.byTooltip('Opciones del alumno'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Terminar').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      verifyNever(() => repo.terminate(any(), reason: any(named: 'reason')));
    });

    testWidgets('alumno re-vinculado (terminado + activo) → una sola fila',
        (tester) async {
      // El stream viene requestedAt DESC: el activo (más reciente) primero.
      await _pump(
        tester,
        links: [
          _link('a1', TrainerLinkStatus.active, id: 'l_new'),
          _link('a1', TrainerLinkStatus.terminated, id: 'l_old'),
        ],
        profiles: [_prof('a1', 'Sofía')],
      );

      expect(find.text('Sofía'), findsOneWidget); // colapsado a una fila
      expect(find.text('1 en total · 1 activos'), findsOneWidget);
    });
  });

  group('AlumnosScreen roster — rediseño kit v2 (Fase 3 WU-03)', () {
    testWidgets('renderiza el roster con CoachHubDataTable + TreinoFilterChips',
        (tester) async {
      await _pump(
        tester,
        links: [
          _link('a1', TrainerLinkStatus.active),
          _link('a2', TrainerLinkStatus.paused),
        ],
        profiles: [_prof('a1', 'Sofía'), _prof('a2', 'Diego')],
      );

      expect(find.byType(CoachHubDataTable), findsOneWidget);
      expect(find.byType(TreinoFilterChips), findsOneWidget);
    });

    testWidgets('los chips de filtro muestran badge con el conteo',
        (tester) async {
      await _pump(
        tester,
        links: [
          _link('a1', TrainerLinkStatus.active),
          _link('a2', TrainerLinkStatus.paused),
        ],
        profiles: [_prof('a1', 'Sofía'), _prof('a2', 'Diego')],
      );

      expect(
        find.descendant(
          of: find.byKey(const Key('filter_chip_Pausados')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('loading → shimmer de la tabla visible, sin filas de datos',
        (tester) async {
      final controller = StreamController<List<TrainerLink>>();
      addTearDown(controller.close);

      // El stream nunca emite: el AsyncValue queda en loading. La tabla usa
      // TreinoShimmer (loop infinito) — NO se puede usar pumpAndSettle acá.
      await _pump(tester, linksStream: controller.stream, settle: false);

      expect(find.byKey(const Key('data_table_skeleton')), findsOneWidget);
      expect(find.byType(CoachHubDataTable), findsOneWidget);
      // El header + filtros siguen visibles durante la carga.
      expect(find.text('ALUMNOS'), findsOneWidget);
    });

    testWidgets('error al cargar links → mensaje de error + retry en la tabla',
        (tester) async {
      await _pump(
        tester,
        linksStream: Stream<List<TrainerLink>>.error(Exception('boom')),
      );

      expect(
        find.text('No se pudieron cargar los alumnos.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('data_table_retry')), findsOneWidget);
    });

    testWidgets('tap en una fila navega al detalle del alumno', (tester) async {
      await _pump(
        tester,
        links: [_link('a1', TrainerLinkStatus.active)],
        profiles: [_prof('a1', 'Sofía')],
      );

      // Tap sobre el nombre (celda «Alumno», sin InkWell propio) en vez del
      // centro geométrico de la fila completa (`tester.tap` por Key tapea el
      // centro del widget): con el breakpoint responsive de esta pieza el
      // ancho de columna varía, y el centro de la fila puede caer sobre
      // Rutina/Nutrición (celdas con su propio `InkWell`, que a propósito
      // absorben el tap y no deben disparar la navegación de la fila — no es
      // un bug, es el mismo criterio que ya usan esos tests dedicados más
      // abajo). Tapear el nombre es un target estable independiente del
      // ancho de columna.
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('data_table_row_a1')),
          matching: find.text('Sofía'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DETALLE a1'), findsOneWidget);
    });
  });

  group('AlumnosScreen roster — columna Rutina', () {
    testWidgets('alumno con rutina activa → chip "Activa"', (tester) async {
      await _pump(
        tester,
        links: [_link('a1', TrainerLinkStatus.active)],
        profiles: [_prof('a1', 'Sofía')],
        routinesByAthleteId: {
          'a1': [_routine('r1')],
        },
      );

      expect(find.text('Activa'), findsOneWidget);
    });

    testWidgets('alumno sin rutina asignada → chip "Sin rutina"',
        (tester) async {
      await _pump(
        tester,
        links: [_link('a1', TrainerLinkStatus.active)],
        profiles: [_prof('a1', 'Sofía')],
      );

      expect(find.text('Sin rutina'), findsOneWidget);
    });

    testWidgets('rutina asignada pero pausada (no activa) → chip "Sin rutina"',
        (tester) async {
      await _pump(
        tester,
        links: [_link('a1', TrainerLinkStatus.active)],
        profiles: [_prof('a1', 'Sofía')],
        routinesByAthleteId: {
          'a1': [_routine('r1', status: RoutineStatus.archived)],
        },
      );

      expect(find.text('Sin rutina'), findsOneWidget);
    });

    testWidgets(
        'tap en el chip Rutina navega a /rutinas/:athleteId sin disparar '
        'la navegación de la fila', (tester) async {
      await _pump(
        tester,
        links: [_link('a1', TrainerLinkStatus.active)],
        profiles: [_prof('a1', 'Sofía')],
        routinesByAthleteId: {
          'a1': [_routine('r1')],
        },
      );

      await tester.tap(find.text('Activa'));
      await tester.pumpAndSettle();

      expect(find.text('RUTINAS a1'), findsOneWidget);
      expect(find.text('DETALLE a1'), findsNothing);
    });
  });

  group('AlumnosScreen roster — columna Nutrición', () {
    testWidgets('alumno con plan de nutrición → chip "Con plan"',
        (tester) async {
      await _pump(
        tester,
        links: [_link('a1', TrainerLinkStatus.active)],
        profiles: [_prof('a1', 'Sofía')],
        plansByAthleteId: {'a1': _plan('a1')},
      );

      expect(find.text('Con plan'), findsOneWidget);
    });

    testWidgets('alumno sin plan de nutrición → chip "Sin plan"',
        (tester) async {
      await _pump(
        tester,
        links: [_link('a1', TrainerLinkStatus.active)],
        profiles: [_prof('a1', 'Sofía')],
      );

      expect(find.text('Sin plan'), findsOneWidget);
    });

    testWidgets(
        'tap en el chip Nutrición navega a /alumnos/:id sin disparar '
        'la navegación de la fila (mismo destino, no duplica evento)',
        (tester) async {
      await _pump(
        tester,
        links: [_link('a1', TrainerLinkStatus.active)],
        profiles: [_prof('a1', 'Sofía')],
        plansByAthleteId: {'a1': _plan('a1')},
      );

      await tester.tap(find.text('Con plan'));
      await tester.pumpAndSettle();

      expect(find.text('DETALLE a1'), findsOneWidget);
    });
  });

  group('AlumnosScreen roster — columna Vencimiento', () {
    testWidgets('alumno con pago vencido → badge "Vencido"', (tester) async {
      await _pump(
        tester,
        links: [_link('a1', TrainerLinkStatus.active)],
        profiles: [_prof('a1', 'Sofía')],
        payments: [
          _payment(
            'a1',
            status: PaymentStatus.pending,
            dueAt: DateTime.now().toUtc().subtract(const Duration(days: 3)),
          ),
        ],
      );

      expect(find.text('Vencido'), findsOneWidget);
    });

    testWidgets(
        'alumno con pago pendiente por vencer → muestra la próxima fecha',
        (tester) async {
      final dueAt = DateTime.now().toUtc().add(const Duration(days: 5));
      await _pump(
        tester,
        links: [_link('a1', TrainerLinkStatus.active)],
        profiles: [_prof('a1', 'Sofía')],
        payments: [
          _payment('a1', status: PaymentStatus.pending, dueAt: dueAt),
        ],
      );

      expect(find.text(fmtDayMonth(dueAt)), findsOneWidget);
    });

    testWidgets('alumno sin ninguna cuota pendiente → "—"', (tester) async {
      await _pump(
        tester,
        links: [_link('a1', TrainerLinkStatus.active)],
        profiles: [_prof('a1', 'Sofía')],
      );

      expect(find.text('—'), findsOneWidget);
    });

    testWidgets(
        'vencido y por vencer a la vez → la fila muestra "Vencido" (peor caso)',
        (tester) async {
      await _pump(
        tester,
        links: [_link('a1', TrainerLinkStatus.active)],
        profiles: [_prof('a1', 'Sofía')],
        payments: [
          _payment(
            'a1',
            id: 'p_venc',
            status: PaymentStatus.pending,
            dueAt: DateTime.now().toUtc().subtract(const Duration(days: 1)),
          ),
          _payment(
            'a1',
            id: 'p_por_vencer',
            status: PaymentStatus.pending,
            dueAt: DateTime.now().toUtc().add(const Duration(days: 10)),
          ),
        ],
      );

      expect(find.text('Vencido'), findsOneWidget);
    });

    testWidgets('pago ya pagado no cuenta como vencimiento → "—"',
        (tester) async {
      await _pump(
        tester,
        links: [_link('a1', TrainerLinkStatus.active)],
        profiles: [_prof('a1', 'Sofía')],
        payments: [
          _payment(
            'a1',
            status: PaymentStatus.paid,
            dueAt: DateTime.now().toUtc().subtract(const Duration(days: 1)),
          ),
        ],
      );

      expect(find.text('—'), findsOneWidget);
    });
  });

  group('AlumnosScreen roster — acciones rápidas (chat/rutina/pago)', () {
    testWidgets(
        'siempre muestra los 3 botones con tooltip, sin importar el estado '
        'del link (no reemplazan pausar/reanudar/terminar)', (tester) async {
      await _pump(
        tester,
        links: [
          _link('a1', TrainerLinkStatus.active),
          _link('a2', TrainerLinkStatus.paused),
          _link('a3', TrainerLinkStatus.terminated),
        ],
        profiles: [
          _prof('a1', 'Sofía'),
          _prof('a2', 'Diego'),
          _prof('a3', 'Ana'),
        ],
      );

      expect(find.byTooltip('Chat'), findsNWidgets(3));
      expect(find.byTooltip('Rutinas'), findsNWidgets(3));
      expect(find.byTooltip('Registrar pago'), findsNWidgets(3));
      // #568: las acciones de vínculo ya no están sueltas en la fila — viven
      // en el menú ⋮, que aparece sólo cuando hay alguna disponible (activo o
      // pausado; el terminado no ofrece ninguna).
      expect(find.byTooltip('Pausar'), findsNothing);
      expect(find.byTooltip('Reanudar'), findsNothing);
      expect(find.byTooltip('Opciones del alumno'), findsNWidgets(2));
    });

    testWidgets('tap en Chat resuelve/crea el chat y navega a /chat',
        (tester) async {
      await _pump(
        tester,
        links: [_link('a1', TrainerLinkStatus.active)],
        profiles: [_prof('a1', 'Sofía')],
      );

      await tester.tap(find.byTooltip('Chat'));
      await tester.pumpAndSettle();

      expect(find.text('CHAT chat_a1'), findsOneWidget);
      expect(find.text('DETALLE a1'), findsNothing);
    });

    testWidgets(
        'tap en Rutinas navega a /rutinas/:athleteId sin disparar la '
        'navegación de la fila', (tester) async {
      await _pump(
        tester,
        links: [_link('a1', TrainerLinkStatus.active)],
        profiles: [_prof('a1', 'Sofía')],
      );

      await tester.tap(find.byTooltip('Rutinas'));
      await tester.pumpAndSettle();

      expect(find.text('RUTINAS a1'), findsOneWidget);
      expect(find.text('DETALLE a1'), findsNothing);
    });

    testWidgets(
        'tap en Registrar pago abre el diálogo y al confirmar crea el pago '
        'del alumno de esa fila', (tester) async {
      final repo = _MockPaymentRepo();
      when(() => repo.add(any())).thenAnswer((_) async {});

      await _pump(
        tester,
        links: [
          _link('a1', TrainerLinkStatus.active),
          _link('a2', TrainerLinkStatus.active),
        ],
        profiles: [_prof('a1', 'Sofía'), _prof('a2', 'Diego')],
        paymentRepo: repo,
      );

      await tester.tap(find.byTooltip('Registrar pago').first);
      await tester.pumpAndSettle();
      expect(find.text('Registrar pago'), findsOneWidget); // título

      // Acotado al diálogo: el roster tiene su propio TextField (buscador),
      // así que `find.byType(TextField)` sin scope agarra ese como índice 0
      // y desalinea Monto/Concepto.
      final dialogFields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(dialogFields.at(0), '5000');
      await tester.enterText(dialogFields.at(1), 'Clase suelta');
      await tester.tap(find.text('Registrar'));
      await tester.pumpAndSettle();

      final p = verify(() => repo.add(captureAny())).captured.single as Payment;
      expect(p.athleteId, 'a1');
      expect(p.amountArs, 5000);
      expect(p.concept, 'Clase suelta');
      expect(p.status, PaymentStatus.paid);
    });

    testWidgets('cancelar el diálogo de Registrar pago NO crea el pago',
        (tester) async {
      final repo = _MockPaymentRepo();

      await _pump(
        tester,
        links: [_link('a1', TrainerLinkStatus.active)],
        profiles: [_prof('a1', 'Sofía')],
        paymentRepo: repo,
      );

      await tester.tap(find.byTooltip('Registrar pago'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      verifyNever(() => repo.add(any()));
    });
  });

  group('AlumnosScreen roster — responsive (breakpoint 900px)', () {
    testWidgets(
        'angosto (<900px) → colapsa último entreno/rutina/nutrición/'
        'vencimiento, mantiene alumno/estado/acciones', (tester) async {
      await _pump(
        tester,
        width: 800,
        links: [_link('a1', TrainerLinkStatus.active)],
        profiles: [_prof('a1', 'Sofía')],
        routinesByAthleteId: {
          'a1': [_routine('r1')],
        },
        plansByAthleteId: {'a1': _plan('a1')},
      );

      expect(find.text('ALUMNO'), findsOneWidget);
      expect(find.text('ESTADO'), findsOneWidget);
      expect(find.text('ACCIONES'), findsOneWidget);
      expect(find.text('ÚLTIMO ENTRENO'), findsNothing);
      expect(find.text('Rutina'), findsNothing);
      expect(find.text('Plan'), findsNothing);
      expect(find.text('Vence'), findsNothing);
      // Las celdas de las columnas colapsadas tampoco se renderizan.
      expect(find.text('Sin entrenos'), findsNothing);
      expect(find.text('Activa'), findsNothing);
      expect(find.text('Con plan'), findsNothing);
      // El núcleo sigue intacto: nombre + estado + acciones rápidas.
      expect(find.text('Sofía'), findsOneWidget);
      expect(find.text('Activo'), findsOneWidget);
      expect(find.byTooltip('Chat'), findsOneWidget);
    });

    testWidgets('ancho (>=900px, borde inclusive) → muestra todas las columnas',
        (tester) async {
      await _pump(
        tester,
        width: 900,
        links: [_link('a1', TrainerLinkStatus.active)],
        profiles: [_prof('a1', 'Sofía')],
      );

      expect(find.text('ALUMNO'), findsOneWidget);
      expect(find.text('ESTADO'), findsOneWidget);
      expect(find.text('ÚLTIMO ENTRENO'), findsOneWidget);
      expect(find.text('Rutina'), findsOneWidget);
      expect(find.text('Plan'), findsOneWidget);
      expect(find.text('Vence'), findsOneWidget);
      expect(find.text('ACCIONES'), findsOneWidget);
    });
  });
}
