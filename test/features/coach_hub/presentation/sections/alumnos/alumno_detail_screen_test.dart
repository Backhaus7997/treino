// Tests for the Coach Hub web Alumno detail (W2 PR2).
//
// Header (name + estado + denormalized metrics), the 10-tab bar, the Progreso
// tab (Antropometría: measurement cards + chart), and placeholder tabs —
// pumped with stubbed providers (no Firestore, no GoRouter needed since we
// don't tap the back link).

import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/locale_resolver.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/data/trainer_link_repository.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen.dart';
import 'package:treino/features/coach_hub/presentation/sections/alumnos/alumnos_screen.dart';
import 'package:treino/features/gyms/application/gym_providers.dart';
import 'package:treino/features/gyms/domain/gym.dart';
import 'package:treino/features/measurements/application/measurement_providers.dart';
import 'package:treino/features/measurements/domain/measurement.dart';
import 'package:treino/features/measurements/presentation/widgets/measurement_progress_chart.dart';
import 'package:treino/features/payments/application/billing_providers.dart';
import 'package:treino/features/payments/application/pagos_por_cobrar_provider.dart';
import 'package:treino/features/payments/application/payment_providers.dart';
import 'package:treino/features/payments/data/payment_repository.dart';
import 'package:treino/features/payments/domain/athlete_billing.dart'
    show AthleteBilling, BillingCadence;
import 'package:treino/features/payments/domain/payment.dart';
import 'package:treino/features/performance/application/performance_test_providers.dart';
import 'package:treino/features/performance/domain/performance_test.dart';
import 'package:treino/features/performance/presentation/widgets/performance_progress_chart.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/routine_status.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/features/workout/domain/set_log.dart';
import 'package:treino/l10n/app_l10n.dart';

class _MockRepo extends Mock implements TrainerLinkRepository {}

class _MockPaymentRepo extends Mock implements PaymentRepository {}

UserPublicProfile _prof({String name = 'Sofía', int wc = 38, int racha = 14}) =>
    UserPublicProfile(
        uid: 'a1', displayName: name, workoutsCount: wc, racha: racha);

TrainerLink _link(TrainerLinkStatus status) => TrainerLink(
      id: 'l1',
      trainerId: 't1',
      athleteId: 'a1',
      status: status,
      requestedAt: DateTime.utc(2026, 1, 1),
      acceptedAt: DateTime.utc(2026, 1, 2),
    );

Measurement _meas(double weightKg, {double? fat, double? waist, int day = 1}) =>
    Measurement(
      id: 'm$day',
      athleteId: 'a1',
      recordedBy: 't1',
      recordedAt: DateTime.utc(2026, 1, day),
      weightKg: weightKg,
      fatPercentage: fat,
      waistCm: waist,
    );

Routine _routine({
  String id = 'r1',
  String name = 'Hipertrofia 4 días',
  String assignedBy = 't1',
  RoutineStatus status = RoutineStatus.active,
  int numWeeks = 4,
  List<RoutineDay> days = const [
    RoutineDay(dayNumber: 1, name: 'Lunes - Push', slots: []),
    RoutineDay(dayNumber: 2, name: 'Martes - Pull', slots: []),
  ],
}) =>
    Routine(
      id: id,
      name: name,
      level: ExperienceLevel.intermediate,
      days: days,
      status: status,
      assignedBy: assignedBy,
      numWeeks: numWeeks,
    );

const _slot = RoutineSlot(
  exerciseId: 'e1',
  exerciseName: 'Press banca',
  muscleGroup: 'Pecho',
  targetSets: 3,
  targetRepsMin: 8,
  targetRepsMax: 12,
  restSeconds: 90,
);

// finishedAt por defecto no-null (DateTime no es const, por eso `?? `);
// para el caso null se construye un Session inline en el test correspondiente.
Session _session({
  String id = 's1',
  String routineName = 'Push - Pecho',
  SessionStatus status = SessionStatus.finished,
  bool wasFullyCompleted = true,
  int durationMin = 52,
  double totalVolumeKg = 7840,
  DateTime? finishedAt,
}) =>
    Session(
      id: id,
      uid: 'a1',
      routineId: 'r1',
      routineName: routineName,
      startedAt: DateTime.utc(2026, 1, 10),
      finishedAt: finishedAt ?? DateTime.utc(2026, 1, 10),
      status: status,
      durationMin: durationMin,
      totalVolumeKg: totalVolumeKg,
      wasFullyCompleted: wasFullyCompleted,
    );

Payment _pago({
  String id = 'p1',
  String athleteId = 'a1',
  int amountArs = 28000,
  String concept = 'Mensual Junio 2026',
  PaymentStatus status = PaymentStatus.paid,
  DateTime? createdAt,
}) =>
    Payment(
      id: id,
      trainerId: 't1',
      athleteId: athleteId,
      amountArs: amountArs,
      concept: concept,
      status: status,
      createdAt: createdAt ?? DateTime.utc(2026, 6, 1),
    );

CobroPendiente _cobro({
  String athleteId = 'a1',
  int amountArs = 18000,
  String concept = 'Mensual Junio 2026',
  BillingCadence cadence = BillingCadence.mensual,
  List<String> pendingPaymentIds = const [],
}) =>
    CobroPendiente(
      athleteId: athleteId,
      amountArs: amountArs,
      cadence: cadence,
      concept: concept,
      pendingPaymentIds: pendingPaymentIds,
    );

AthleteBilling _billing({
  int amountArs = 24000,
  BillingCadence cadence = BillingCadence.mensual,
}) =>
    AthleteBilling(
      trainerId: 't1',
      athleteId: 'a1',
      amountArs: amountArs,
      cadence: cadence,
      updatedAt: DateTime.utc(2026, 1, 1),
    );

PerformanceTest _perf({double cmjCm = 30, int day = 1}) => PerformanceTest(
      id: 'pt$day',
      athleteId: 'a1',
      recordedBy: 't1',
      recordedAt: DateTime.utc(2026, 1, day),
      cmjCm: cmjCm,
    );

SetLog _setLog({
  String exerciseId = 'ex1',
  String exerciseName = 'Sentadilla',
  int setNumber = 1,
  int reps = 5,
  double weightKg = 100,
}) =>
    SetLog(
      id: 'sl-$exerciseId-$setNumber',
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      setNumber: setNumber,
      reps: reps,
      weightKg: weightKg,
      completedAt: DateTime.utc(2026, 1, 1),
    );

Future<void> _pump(
  WidgetTester tester, {
  UserPublicProfile? profile,
  TrainerLink? link,
  List<Measurement> measurements = const [],
  List<Routine> routines = const [],
  List<Session> sessions = const [],
  List<Payment> payments = const [],
  List<CobroPendiente> pendingCobros = const [],
  PaymentRepository? paymentRepo,
  AthleteBilling? billing,
  List<PerformanceTest> performanceTests = const [],
  Object? performanceError,
  List<SetLog> setLogs = const [],
  Object? sessionsError,
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userPublicProfileProvider
            .overrideWith((ref, id) => Stream.value(profile)),
        trainerLinksStreamProvider
            .overrideWith((ref) => Stream.value(link == null ? [] : [link])),
        pagosPorCobrarProvider.overrideWith((ref) => AsyncData(pendingCobros)),
        trainerPaymentsProvider.overrideWith((ref) => Stream.value(payments)),
        athleteBillingProvider.overrideWith((ref, id) => Stream.value(billing)),
        measurementsForAthleteProvider
            .overrideWith((ref, id) => Stream.value(measurements)),
        performanceTestsForAthleteProvider.overrideWith((ref, id) =>
            performanceError != null
                ? Stream.error(performanceError)
                : Stream.value(performanceTests)),
        currentUidProvider.overrideWithValue('t1'),
        assignedRoutinesProvider.overrideWith((ref, id) => routines),
        sessionsByUidProvider.overrideWith((ref, id) {
          if (sessionsError != null) throw sessionsError;
          return sessions;
        }),
        coachSessionSetLogsProvider.overrideWith((ref, key) async => setLogs),
        if (paymentRepo != null)
          paymentRepositoryProvider.overrideWithValue(paymentRepo),
      ],
      child: MaterialApp(
        // l10n EXACTO como CoachHubApp (W2 PR8): delegates + supportedLocales +
        // localeResolutionCallback. Sin el callback resuelve a `en` (1º en
        // supportedLocales) y los strings del chart salen en blanco.
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        localeResolutionCallback: (l, s) =>
            resolveLocale(l ?? const Locale('es', 'AR'), s),
        theme: AppTheme.dark(),
        home: const Scaffold(body: AlumnoDetailScreen(athleteId: 'a1')),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    registerFallbackValue('');
    registerFallbackValue(<String>[]);
    registerFallbackValue(DateTime.utc(2020));
    registerFallbackValue(_pago());
  });

  group('AlumnoDetailScreen (W2 PR2)', () {
    testWidgets('header: nombre + estado + métricas denormalizadas',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(name: 'Sofía', wc: 38, racha: 14),
        link: _link(TrainerLinkStatus.active),
        measurements: [_meas(60.5)],
      );

      expect(find.text('Sofía'), findsOneWidget);
      expect(find.text('Activo'), findsOneWidget);
      expect(find.text('38'), findsOneWidget); // sesiones
      expect(find.text('14 d'), findsOneWidget); // racha
    });

    testWidgets(
        'header: plan (monto·cadencia) + próximo cobro + botón Pago (W2 PR7)',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        billing: _billing(amountArs: 24000, cadence: BillingCadence.mensual),
      );

      expect(find.text('\$24.000 · Mensual'), findsOneWidget);
      expect(find.textContaining('Próx. cobro:'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Pago'), findsOneWidget);
    });

    testWidgets('header: cadencia semanal se etiqueta "Semanal" (W2 PR7)',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        billing: _billing(amountArs: 9000, cadence: BillingCadence.semanal),
      );

      expect(find.text('\$9.000 · Semanal'), findsOneWidget);
    });

    testWidgets('header: botón Pago abre el diálogo de registrar pago (W2 PR7)',
        (tester) async {
      await _pump(tester,
          profile: _prof(),
          link: _link(TrainerLinkStatus.active),
          paymentRepo: _MockPaymentRepo());

      await tester.tap(find.widgetWithText(OutlinedButton, 'Pago'));
      await tester.pumpAndSettle();

      expect(find.text('Registrar pago'), findsOneWidget); // título del diálogo
      expect(find.text('Monto (ARS)'), findsOneWidget);
    });

    testWidgets('header: sin billing no muestra chips de plan (W2 PR7)',
        (tester) async {
      await _pump(tester,
          profile: _prof(), link: _link(TrainerLinkStatus.active));

      expect(find.textContaining('Próx. cobro:'), findsNothing);
      expect(find.text('· Mensual'), findsNothing);
      // El botón Pago está siempre (no depende de billing).
      expect(find.widgetWithText(OutlinedButton, 'Pago'), findsOneWidget);
    });

    testWidgets('tab bar muestra exactamente las 10 secciones', (tester) async {
      await _pump(tester,
          profile: _prof(), link: _link(TrainerLinkStatus.active));
      expect(find.byType(Tab), findsNWidgets(10));
      for (final t in [
        'Resumen',
        'Entrenamientos',
        'Progreso',
        'Nutrición',
        'Pagos',
        'Historial',
        'Chat',
        'Notas privadas',
        'Archivos',
        'Seguimiento'
      ]) {
        expect(
          find.descendant(of: find.byType(TabBar), matching: find.text(t)),
          findsOneWidget,
          reason: 'falta el tab $t',
        );
      }
    });

    testWidgets(
        'Entrenamientos: tap en una sesión expande sus sets reales '
        '(trainer-athlete-set-logs)', (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        sessions: [_session(id: 's1', routineName: 'Hipertrofia 4 días')],
        setLogs: [_setLog(exerciseName: 'Sentadilla', reps: 5, weightKg: 100)],
      );

      await tester.tap(find.descendant(
          of: find.byType(TabBar), matching: find.text('Entrenamientos')));
      await tester.pumpAndSettle();

      // Colapsado: los sets no se ven todavía.
      expect(find.text('Sentadilla'), findsNothing);

      // Tap en la fila de la sesión → expande y carga los sets reales.
      await tester.tap(find.text('Hipertrofia 4 días'));
      await tester.pumpAndSettle();

      expect(find.text('Sentadilla'), findsOneWidget);
    });

    testWidgets(
        'Entrenamientos: alumno no compartió → mensaje claro (no error genérico)',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        sessionsError: FirebaseException(
            plugin: 'cloud_firestore', code: 'permission-denied'),
      );

      await tester.tap(find.descendant(
          of: find.byType(TabBar), matching: find.text('Entrenamientos')));
      await tester.pumpAndSettle();

      expect(find.text('El alumno no compartió su historial.'), findsOneWidget);
      expect(find.text('No se pudo cargar el historial.'), findsNothing);
    });

    testWidgets('Progreso muestra antropometría', (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        measurements: [_meas(60.5, fat: 22.4, waist: 71)],
      );

      await tester.tap(find.text('Progreso'));
      await tester.pumpAndSettle();

      expect(find.text('ANTROPOMETRÍA'), findsOneWidget);
      expect(find.text('Peso'), findsOneWidget);
      expect(find.text('60.5 kg'), findsOneWidget);
    });

    testWidgets('Progreso sin datos (ni mediciones ni tests) → estado vacío',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        measurements: const [],
        performanceTests: const [],
      );

      await tester.tap(find.text('Progreso'));
      await tester.pumpAndSettle();

      expect(find.text('Sin datos de progreso todavía.'), findsOneWidget);
    });

    testWidgets('Progreso con ≥2 mediciones renderiza el gráfico',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        measurements: [_meas(62, day: 1), _meas(60.5, day: 20)],
      );

      await tester.tap(find.text('Progreso'));
      await tester.pumpAndSettle();

      expect(find.byType(MeasurementProgressChart), findsOneWidget);
    });

    testWidgets(
        'Progreso con ≥2 tests de performance renderiza el chart (W2 PR8)',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        performanceTests: [_perf(cmjCm: 28, day: 1), _perf(cmjCm: 32, day: 20)],
      );

      await tester.tap(find.text('Progreso'));
      await tester.pumpAndSettle();

      expect(find.byType(PerformanceProgressChart), findsOneWidget);
      expect(find.text('RENDIMIENTO'), findsOneWidget); // mi heading de sección
      // El chart renderea su label l10n («PROGRESO») en es-AR, NO en blanco:
      // prueba que el localeResolutionCallback del harness resuelve es-AR.
      expect(find.text('PROGRESO'), findsOneWidget);
    });

    testWidgets('Progreso con 1 test de performance → hint, sin chart (W2 PR8)',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        performanceTests: [_perf(cmjCm: 30, day: 1)],
      );

      await tester.tap(find.text('Progreso'));
      await tester.pumpAndSettle();

      expect(find.text('RENDIMIENTO'), findsOneWidget);
      expect(find.text('Cargá al menos 2 tests para ver la evolución.'),
          findsOneWidget);
      expect(find.byType(PerformanceProgressChart), findsNothing);
      // Sin mediciones → la sección Antropometría queda totalmente suprimida.
      expect(find.text('ANTROPOMETRÍA'), findsNothing);
      expect(find.byType(MeasurementProgressChart), findsNothing);
    });

    testWidgets('Progreso muestra antropometría + rendimiento juntos (W2 PR8)',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        measurements: [_meas(62, day: 1), _meas(60.5, day: 20)],
        performanceTests: [_perf(cmjCm: 28, day: 1), _perf(cmjCm: 32, day: 20)],
      );

      await tester.tap(find.text('Progreso'));
      await tester.pumpAndSettle();

      expect(find.text('ANTROPOMETRÍA'), findsOneWidget);
      expect(find.byType(MeasurementProgressChart), findsOneWidget);
      expect(find.byType(PerformanceProgressChart), findsOneWidget);
    });

    testWidgets('Progreso: error en una fuente gatea todo el tab (W2 PR8)',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        measurements: [_meas(60.5)], // mediciones OK
        performanceError: 'boom', // performance falla
      );

      await tester.tap(find.text('Progreso'));
      await tester.pumpAndSettle();

      expect(find.text('No se pudo cargar el progreso.'), findsOneWidget);
      expect(
          find.text('ANTROPOMETRÍA'), findsNothing); // gateado, no se muestra
    });

    testWidgets('tab placeholder muestra "Próximamente."', (tester) async {
      await _pump(tester,
          profile: _prof(), link: _link(TrainerLinkStatus.active));

      await tester.tap(find.text('Nutrición'));
      await tester.pumpAndSettle();

      expect(find.text('Próximamente.'), findsOneWidget);
    });

    testWidgets(
        'Resumen (tab default) muestra las 4 métricas + heatmap (W2 PR4)',
        (tester) async {
      await _pump(tester,
          profile: _prof(), link: _link(TrainerLinkStatus.active));

      // Resumen es el tab por defecto: no hace falta tapear.
      expect(find.text('ADHERENCIA 30D'), findsOneWidget);
      expect(find.text('SESIONES / SEM'), findsOneWidget);
      expect(find.text('VOLUMEN'), findsOneWidget);
      expect(find.text('PESO CORPORAL'), findsOneWidget);
      expect(find.text('ADHERENCIA · 12 SEMANAS'), findsOneWidget);
    });

    testWidgets('Resumen sin plan ni mediciones → estados neutros (W2 PR4)',
        (tester) async {
      await _pump(tester,
          profile: _prof(), link: _link(TrainerLinkStatus.active));

      // Sin rutina activa → ambas cards (adherencia + sesiones/sem) dicen
      // "Sin plan" con el mismo wording.
      expect(find.text('Sin plan'), findsNWidgets(2));
      expect(find.text('Sin plan asignado'), findsNothing);
    });

    testWidgets('tab Pagos: al día + sin historial (W2 PR5)', (tester) async {
      await _pump(tester,
          profile: _prof(), link: _link(TrainerLinkStatus.active));

      await tester.tap(find.text('Pagos'));
      await tester.pumpAndSettle();

      expect(find.text('ESTADO DE CUENTA'), findsOneWidget);
      expect(find.text('Al día'), findsOneWidget);
      expect(find.text('HISTORIAL DE PAGOS'), findsOneWidget);
      expect(find.text('Sin pagos registrados todavía.'), findsOneWidget);
    });

    testWidgets('tab Pagos: pendiente + historial con datos (W2 PR5)',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        payments: [
          _pago(
              id: 'p1',
              concept: 'Mensual mayo',
              amountArs: 28000,
              status: PaymentStatus.paid,
              createdAt: DateTime.utc(2026, 5, 1)),
          _pago(
              id: 'p2',
              concept: 'Clase suelta',
              amountArs: 5000,
              status: PaymentStatus.pending,
              createdAt: DateTime.utc(2026, 6, 10)),
          // De otro alumno → debe filtrarse por athleteId.
          _pago(
              id: 'pX', athleteId: 'otro', concept: 'Ajeno', amountArs: 99000),
        ],
        pendingCobros: [
          _cobro(amountArs: 18000, concept: 'Mensual Junio 2026')
        ],
      );

      await tester.tap(find.text('Pagos'));
      await tester.pumpAndSettle();

      // Estado de cuenta: el total (24px) + la línea del único cobro (mismo
      // monto) → el texto aparece 2 veces; más el botón Marcar pagado.
      expect(find.text('Pendiente de cobro'), findsOneWidget);
      expect(find.text('\$18.000'), findsNWidgets(2));
      expect(find.text('Marcar pagado'), findsOneWidget);

      // Historial del alumno (no el pago "Ajeno" de otro).
      expect(find.text('Mensual mayo'), findsOneWidget);
      expect(find.text('\$28.000'), findsOneWidget);
      expect(find.text('\$5.000'), findsOneWidget); // 4 dígitos → un separador
      expect(find.text('Pagado'), findsOneWidget);
      expect(find.text('Clase suelta'), findsOneWidget);
      expect(find.text('Pendiente'), findsOneWidget);
      expect(find.text('Ajeno'), findsNothing);

      // Orden DESC por createdAt: la fila de junio va ARRIBA de la de mayo.
      expect(
        tester.getTopLeft(find.text('Clase suelta')).dy,
        lessThan(tester.getTopLeft(find.text('Mensual mayo')).dy),
      );
    });

    testWidgets('tab Pagos: suma varios cobros pendientes (W2 PR5)',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        pendingCobros: [
          _cobro(amountArs: 18000, concept: 'Mensual'),
          _cobro(amountArs: 12000, concept: 'Extra'),
        ],
      );

      await tester.tap(find.text('Pagos'));
      await tester.pumpAndSettle();

      expect(find.text('\$30.000'), findsOneWidget); // total 18.000 + 12.000
      expect(find.text('Mensual'), findsOneWidget); // un concepto por cobro
      expect(find.text('Extra'), findsOneWidget);
      expect(
          find.text('Marcar pagado'), findsNWidgets(2)); // un botón por cobro
    });

    testWidgets('tab Pagos: monto de 7 dígitos usa dos separadores (W2 PR5)',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        payments: [_pago(concept: 'Plan anual', amountArs: 1200000)],
      );

      await tester.tap(find.text('Pagos'));
      await tester.pumpAndSettle();

      expect(find.text('\$1.200.000'), findsOneWidget);
    });

    testWidgets('tab Pagos: registrar pago crea un Payment pagado (W2 PR6)',
        (tester) async {
      final repo = _MockPaymentRepo();
      when(() => repo.add(any())).thenAnswer((_) async {});

      await _pump(tester,
          profile: _prof(),
          link: _link(TrainerLinkStatus.active),
          paymentRepo: repo);

      await tester.tap(find.text('Pagos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('+ Registrar pago'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), '5000');
      await tester.enterText(find.byType(TextField).at(1), 'Clase de prueba');
      await tester.tap(find.text('Registrar'));
      await tester.pumpAndSettle();

      final p = verify(() => repo.add(captureAny())).captured.single as Payment;
      expect(p.athleteId, 'a1');
      expect(p.amountArs, 5000);
      expect(p.concept, 'Clase de prueba');
      expect(p.status, PaymentStatus.paid);
    });

    testWidgets(
        'tab Pagos: registrar pago con monto inválido NO escribe (W2 PR6)',
        (tester) async {
      final repo = _MockPaymentRepo();

      await _pump(tester,
          profile: _prof(),
          link: _link(TrainerLinkStatus.active),
          paymentRepo: repo);

      await tester.tap(find.text('Pagos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('+ Registrar pago'));
      await tester.pumpAndSettle();

      // Concepto sin monto → validación, sin escritura.
      await tester.enterText(find.byType(TextField).at(1), 'Algo');
      await tester.tap(find.text('Registrar'));
      await tester.pumpAndSettle();

      expect(find.text('Ingresá un monto válido.'), findsOneWidget);
      verifyNever(() => repo.add(any()));
    });

    testWidgets('tab Pagos: registrar pago sin concepto NO escribe (W2 PR6)',
        (tester) async {
      final repo = _MockPaymentRepo();

      await _pump(tester,
          profile: _prof(),
          link: _link(TrainerLinkStatus.active),
          paymentRepo: repo);

      await tester.tap(find.text('Pagos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('+ Registrar pago'));
      await tester.pumpAndSettle();

      // Monto válido pero concepto vacío → validación, sin escritura.
      await tester.enterText(find.byType(TextField).at(0), '5000');
      await tester.tap(find.text('Registrar'));
      await tester.pumpAndSettle();

      expect(find.text('Completá todos los campos.'), findsOneWidget);
      verifyNever(() => repo.add(any()));
    });

    testWidgets('tab Pagos: marcar pagado (suelto) llama markManyPaid (W2 PR6)',
        (tester) async {
      final repo = _MockPaymentRepo();
      when(() => repo.markManyPaid(any(), any())).thenAnswer((_) async {});

      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        paymentRepo: repo,
        pendingCobros: [
          _cobro(
            concept: 'Cobro suelto',
            amountArs: 5000,
            cadence: BillingCadence.suelto,
            pendingPaymentIds: ['pp1', 'pp2'],
          ),
        ],
      );

      await tester.tap(find.text('Pagos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Marcar pagado'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cobrado')); // confirma
      await tester.pumpAndSettle();

      verify(() => repo.markManyPaid(['pp1', 'pp2'], any())).called(1);
      verifyNever(() => repo.add(any()));
    });

    testWidgets(
        'tab Pagos: marcar pagado (mensual) crea Payment pagado con periodKey (W2 PR6)',
        (tester) async {
      final repo = _MockPaymentRepo();
      when(() => repo.add(any())).thenAnswer((_) async {});

      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        paymentRepo: repo,
        pendingCobros: [_cobro(concept: 'Mensual', amountArs: 18000)],
      );

      await tester.tap(find.text('Pagos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Marcar pagado'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cobrado'));
      await tester.pumpAndSettle();

      final p = verify(() => repo.add(captureAny())).captured.single as Payment;
      expect(p.status, PaymentStatus.paid);
      expect(p.amountArs, 18000);
      // El key EXACTO que compara pagosPorCobrarProvider (si no, el cobro no
      // desaparece): mismo formato/now que el provider.
      final n = DateTime.now().toUtc();
      expect(p.periodKey, '${n.year}-${n.month.toString().padLeft(2, '0')}');
    });

    testWidgets(
        'tab Pagos: marcar pagado (semanal) usa periodKey ISO-week (W2 PR6)',
        (tester) async {
      final repo = _MockPaymentRepo();
      when(() => repo.add(any())).thenAnswer((_) async {});

      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        paymentRepo: repo,
        pendingCobros: [
          _cobro(
              concept: 'Semana',
              amountArs: 9000,
              cadence: BillingCadence.semanal),
        ],
      );

      await tester.tap(find.text('Pagos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Marcar pagado'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cobrado'));
      await tester.pumpAndSettle();

      final p = verify(() => repo.add(captureAny())).captured.single as Payment;
      expect(p.status, PaymentStatus.paid);
      expect(p.periodKey, isoWeekPeriodKey(DateTime.now().toUtc()));
    });

    testWidgets(
        'tab Pagos: marcar pagado (porSesión) crea Payment sin periodKey (W2 PR6)',
        (tester) async {
      final repo = _MockPaymentRepo();
      when(() => repo.add(any())).thenAnswer((_) async {});

      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        paymentRepo: repo,
        pendingCobros: [
          _cobro(
              concept: '3 sesiones',
              amountArs: 9000,
              cadence: BillingCadence.porSesion),
        ],
      );

      await tester.tap(find.text('Pagos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Marcar pagado'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cobrado'));
      await tester.pumpAndSettle();

      final p = verify(() => repo.add(captureAny())).captured.single as Payment;
      expect(p.status, PaymentStatus.paid);
      expect(p.periodKey, isNull);
      verifyNever(() => repo.markManyPaid(any(), any()));
    });

    testWidgets('tab Pagos: cancelar el marcar pagado NO escribe (W2 PR6)',
        (tester) async {
      final repo = _MockPaymentRepo();

      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        paymentRepo: repo,
        pendingCobros: [_cobro(concept: 'Mensual', amountArs: 18000)],
      );

      await tester.tap(find.text('Pagos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Marcar pagado'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      verifyNever(() => repo.add(any()));
      verifyNever(() => repo.markManyPaid(any(), any()));
    });

    testWidgets('tab Entrenamientos: estados vacíos (W2 PR3)', (tester) async {
      await _pump(tester,
          profile: _prof(), link: _link(TrainerLinkStatus.active));

      await tester.tap(find.text('Entrenamientos'));
      await tester.pumpAndSettle();

      expect(find.text('RUTINA ACTIVA'), findsOneWidget);
      expect(find.text('Sin rutina activa asignada.'), findsOneWidget);
      expect(find.text('HISTORIAL DE SESIONES'), findsOneWidget);
      expect(find.text('Sin sesiones registradas todavía.'), findsOneWidget);
    });

    testWidgets(
        'tab Entrenamientos: rutina activa + historial con datos (W2 PR3)',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        routines: [_routine()],
        sessions: [_session(totalVolumeKg: 7839.6)],
      );

      await tester.tap(find.text('Entrenamientos'));
      await tester.pumpAndSettle();

      expect(find.text('Hipertrofia 4 días'), findsOneWidget); // rutina activa
      expect(
          find.text('2 días · 4 semanas'), findsOneWidget); // resumen (plural)
      expect(find.text('Lunes - Push'), findsOneWidget); // día
      expect(find.text('0 ejercicios'), findsNWidgets(2)); // 2 días sin slots
      expect(find.text('Push - Pecho'), findsOneWidget); // fila de sesión
      expect(find.text('10/01/2026'), findsOneWidget); // fecha formateada
      expect(find.text('52 min'), findsOneWidget);
      expect(find.text('7840 kg'), findsOneWidget); // .round() de 7839.6
    });

    testWidgets(
        'tab Entrenamientos: 1 semana / 1 ejercicio usa singular (W2 PR3)',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        routines: [
          _routine(numWeeks: 1, days: const [
            RoutineDay(dayNumber: 1, name: 'Día A', slots: [_slot]),
          ]),
        ],
      );

      await tester.tap(find.text('Entrenamientos'));
      await tester.pumpAndSettle();

      expect(find.text('1 días · 1 semana'), findsOneWidget); // semana singular
      expect(find.text('1 ejercicio'), findsOneWidget); // ejercicio singular
    });

    testWidgets(
        'tab Entrenamientos: prioriza la rutina del trainer logueado (W2 PR3)',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        routines: [
          _routine(id: 'rOtro', name: 'Plan de otro coach', assignedBy: 't2'),
          _routine(id: 'rMia', name: 'Mi plan', assignedBy: 't1'),
        ],
      );

      await tester.tap(find.text('Entrenamientos'));
      await tester.pumpAndSettle();

      expect(find.text('Mi plan'), findsOneWidget);
      expect(find.text('Plan de otro coach'), findsNothing);
    });

    testWidgets(
        'tab Entrenamientos: sin rutina propia cae a la activa de otro trainer (W2 PR3)',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        routines: [_routine(name: 'Plan heredado', assignedBy: 't2')],
      );

      await tester.tap(find.text('Entrenamientos'));
      await tester.pumpAndSettle();

      expect(find.text('Plan heredado'), findsOneWidget);
      expect(find.text('Sin rutina activa asignada.'), findsNothing);
    });

    testWidgets(
        'tab Entrenamientos: rutina archivada y sesión en curso quedan excluidas (W2 PR3)',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        routines: [
          _routine(name: 'Rutina vieja', status: RoutineStatus.archived)
        ],
        sessions: [
          _session(routineName: 'En curso', status: SessionStatus.active)
        ],
      );

      await tester.tap(find.text('Entrenamientos'));
      await tester.pumpAndSettle();

      expect(find.text('Sin rutina activa asignada.'), findsOneWidget);
      expect(find.text('Rutina vieja'), findsNothing);
      expect(find.text('Sin sesiones registradas todavía.'), findsOneWidget);
      expect(find.text('En curso'), findsNothing);
    });

    testWidgets(
        'tab Entrenamientos: sesión abandonada (wasFullyCompleted=false) queda excluida (W2 PR3)',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        sessions: [
          _session(routineName: 'Abandonada', wasFullyCompleted: false)
        ],
      );

      await tester.tap(find.text('Entrenamientos'));
      await tester.pumpAndSettle();

      expect(find.text('Abandonada'), findsNothing);
      expect(find.text('Sin sesiones registradas todavía.'), findsOneWidget);
    });

    testWidgets(
        'tab Entrenamientos: sesión sin finishedAt muestra "—" (W2 PR3)',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        sessions: [
          Session(
            id: 's-null',
            uid: 'a1',
            routineId: 'r1',
            routineName: 'Sin fecha',
            startedAt: DateTime.utc(2026, 1, 10),
            status: SessionStatus.finished,
            wasFullyCompleted: true,
            durationMin: 30,
            totalVolumeKg: 1000,
          ),
        ],
      );

      await tester.tap(find.text('Entrenamientos'));
      await tester.pumpAndSettle();

      expect(find.text('Sin fecha'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('tab Entrenamientos: historial se topa en 20 filas (W2 PR3)',
        (tester) async {
      final many = [
        for (var i = 0; i < 21; i++)
          _session(id: 's$i', routineName: 'Sesión $i'),
      ];
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        sessions: many,
      );

      await tester.tap(find.text('Entrenamientos'));
      await tester.pumpAndSettle();

      // El .take(20) descarta la 21.ª (índice 20); las primeras 20 entran.
      expect(find.text('Sesión 0'), findsOneWidget);
      expect(find.text('Sesión 19'), findsOneWidget);
      expect(find.text('Sesión 20'), findsNothing);
    });
  });

  group('navegación roster → detalle (W2 PR2)', () {
    Future<void> pumpRouter(WidgetTester tester,
        {required TrainerLinkRepository repo}) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final profiles = {'a1': _prof(name: 'Sofía')};
      final router = GoRouter(
        initialLocation: '/alumnos',
        routes: [
          GoRoute(
            path: '/alumnos',
            builder: (_, __) => const Scaffold(body: AlumnosScreen()),
          ),
          GoRoute(
            path: '/alumnos/:id',
            builder: (_, s) => Scaffold(
                body: AlumnoDetailScreen(athleteId: s.pathParameters['id']!)),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trainerLinksStreamProvider.overrideWith(
                (ref) => Stream.value([_link(TrainerLinkStatus.active)])),
            userPublicProfilesBatchProvider
                .overrideWith((ref, key) => profiles),
            userPublicProfileProvider
                .overrideWith((ref, id) => Stream.value(profiles[id])),
            pagosPorCobrarProvider
                .overrideWith((ref) => const AsyncData(<CobroPendiente>[])),
            finishedTodayByUidProvider
                .overrideWith((ref, uid) => const <Session>[]),
            measurementsForAthleteProvider
                .overrideWith((ref, id) => Stream.value(const <Measurement>[])),
            gymsProvider.overrideWith((ref) => const <Gym>[]),
            trainerLinkRepositoryProvider.overrideWithValue(repo),
            // El detalle abre en Resumen (W2 PR4), que lee estos providers.
            sessionsByUidProvider.overrideWith((ref, id) => const <Session>[]),
            assignedRoutinesProvider
                .overrideWith((ref, id) => const <Routine>[]),
            currentUidProvider.overrideWithValue('t1'),
            // El header (W2 PR7) lee el billing del alumno.
            athleteBillingProvider
                .overrideWith((ref, id) => Stream.value(null)),
          ],
          child:
              MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('tap en la fila del roster navega al detalle', (tester) async {
      await pumpRouter(tester, repo: _MockRepo());
      // En el roster todavía: el detalle abre en Resumen, cuya sección de
      // heatmap es marcador exclusivo del detalle.
      expect(find.text('ADHERENCIA · 12 SEMANAS'), findsNothing);

      await tester.tap(find.text('Sofía'));
      await tester.pumpAndSettle();

      // Ahora en el detalle (tab Resumen por defecto).
      expect(find.text('ADHERENCIA · 12 SEMANAS'), findsOneWidget);
    });

    testWidgets('tap en la acción Terminar abre diálogo y NO navega',
        (tester) async {
      final repo = _MockRepo();
      when(() => repo.terminate(any(), reason: any(named: 'reason')))
          .thenAnswer((_) async {});

      await pumpRouter(tester, repo: repo);
      await tester.tap(find.byTooltip('Terminar'));
      await tester.pumpAndSettle();

      expect(find.text('Terminar vínculo'), findsOneWidget); // diálogo
      // No navegó al detalle (su tab Resumen mostraría el heatmap).
      expect(find.text('ADHERENCIA · 12 SEMANAS'), findsNothing);
    });
  });

  group('nextDueDate (W2 PR7)', () {
    test('mensual → 1º del mes que viene', () {
      expect(
        nextDueDate(
            _billing(cadence: BillingCadence.mensual), DateTime(2026, 6, 18)),
        DateTime(2026, 7, 1),
      );
    });

    test('mensual en diciembre → 1º de enero del año que viene', () {
      expect(
        nextDueDate(
            _billing(cadence: BillingCadence.mensual), DateTime(2026, 12, 10)),
        DateTime(2027, 1, 1),
      );
    });

    test('semanal → lunes de la semana que viene', () {
      // 2026-06-18 es jueves → lunes próximo = 2026-06-22.
      expect(
        nextDueDate(
            _billing(cadence: BillingCadence.semanal), DateTime(2026, 6, 18)),
        DateTime(2026, 6, 22),
      );
    });

    test('semanal cuando hoy ES lunes → el lunes siguiente (+7)', () {
      // 2026-06-22 es lunes → próximo = 2026-06-29 (no el mismo día).
      expect(
        nextDueDate(
            _billing(cadence: BillingCadence.semanal), DateTime(2026, 6, 22)),
        DateTime(2026, 6, 29),
      );
    });

    test('porSesión y suelto → null (sin fecha fija)', () {
      expect(
          nextDueDate(_billing(cadence: BillingCadence.porSesion),
              DateTime(2026, 6, 18)),
          isNull);
      expect(
          nextDueDate(
              _billing(cadence: BillingCadence.suelto), DateTime(2026, 6, 18)),
          isNull);
    });
  });

  group('fmtDayMonth (W2 PR7)', () {
    test('formatea día + mes en es-AR', () {
      expect(fmtDayMonth(DateTime(2026, 5, 22)), '22 mayo');
    });

    test('diciembre (tope del array de meses)', () {
      expect(fmtDayMonth(DateTime(2026, 12, 1)), '1 diciembre');
    });
  });
}
