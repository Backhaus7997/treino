// Tests for the Coach Hub web Alumno detail (W2 PR2).
//
// Header (name + estado + denormalized metrics), the seven groups, and their
// nested navigation —
// pumped with stubbed providers (no Firestore, no GoRouter needed since we
// don't tap the back link).

import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/locale_resolver.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/components/treino_button_tokens.dart';
import 'package:treino/features/coach_hub/presentation/widgets/button/treino_button.dart';
import 'package:treino/core/widgets/treino_segmented_pill.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/chat/domain/chat.dart';
import 'package:treino/features/chat/domain/message.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/application/athlete_note_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/data/trainer_link_repository.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/domain/athlete_note.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/payment_format.dart'
    show fmtDayMonth, nextDueDate;
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
import 'package:treino/features/workout/application/exercise_feedback_providers.dart';
import 'package:treino/features/workout/application/exercise_progression_providers.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/exercise_feedback.dart';
import 'package:treino/features/workout/domain/exercise_progression.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/routine_status.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/features/workout/domain/set_log.dart';
import 'package:treino/features/workout/presentation/widgets/exercise_progression_chart.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show userProfileProvider;
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/l10n/app_l10n.dart';

import 'alumno_detail_test_navigation.dart';

class _MockRepo extends Mock implements TrainerLinkRepository {}

class _MockPaymentRepo extends Mock implements PaymentRepository {}

class _MockSessionRepository extends Mock implements SessionRepository {}

/// Default stub for [SessionRepository] used by the daily heat-map section
/// (AD5, PR2b) in tests that don't exercise it directly — `listByUid` for
/// any uid resolves to an empty list (blank silhouette, no trained days).
SessionRepository _emptySessionRepository() {
  final repo = _MockSessionRepository();
  when(() => repo.listByUid(any())).thenAnswer((_) async => []);
  return repo;
}

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
      // Noon UTC (not midnight): fmtDate now localizes (#380), and noon stays
      // on the same calendar day in both the Argentina dev box (09:00 ART) and
      // UTC CI, so the '10/01/2026' assertion holds in either TZ.
      startedAt: DateTime.utc(2026, 1, 10, 12),
      finishedAt: finishedAt ?? DateTime.utc(2026, 1, 10, 12),
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

/// Un reporte del alumno (#628). El `exerciseId` por defecto NO es el de
/// [_setLog]: el caso que importa es el ejercicio con CERO series.
ExerciseFeedback _feedback({
  String id = 'fb1',
  String exerciseId = 'ex9',
  String exerciseName = 'Remo en polea',
  int? setNumber,
  String text = 'Me tira el hombro',
}) =>
    ExerciseFeedback(
      id: id,
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      setNumber: setNumber,
      kind: ExerciseFeedbackKind.discomfort,
      text: text,
      createdAt: DateTime.utc(2026, 1, 1, 10),
    );

AthleteNote _note({String note = 'Buena progresión', DateTime? updatedAt}) =>
    AthleteNote(
      trainerId: 't1',
      athleteId: 'a1',
      note: note,
      updatedAt: updatedAt ?? DateTime.utc(2026, 7, 1),
    );

UserProfile _trainerProfile({String? paymentAlias = 'Pepe Coach'}) =>
    UserProfile(
      uid: 't1',
      email: 'coach@test.com',
      displayName: 'Coach Test',
      role: UserRole.trainer,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      paymentAlias: paymentAlias,
    );

Chat _chat({String chatId = 'chat-a1'}) => Chat(
      chatId: chatId,
      members: const ['t1', 'a1'],
      createdAt: DateTime.utc(2026, 6, 1),
    );

/// Future start — always after DateTime.now() in test context.
Appointment _appointment({
  String id = 'ap1',
  DateTime? startsAt,
  int durationMin = 60,
  AppointmentStatus status = AppointmentStatus.confirmed,
  String? noteBefore,
}) =>
    Appointment(
      id: id,
      trainerId: 't1',
      athleteId: 'a1',
      athleteDisplayName: 'Sofía',
      startsAt: startsAt ?? DateTime.now().toUtc().add(const Duration(days: 3)),
      durationMin: durationMin,
      status: status,
      noteBefore: noteBefore,
    );

Future<void> _pump(
  WidgetTester tester, {
  /// Tema del harness. Por defecto OSCURO, como el resto de la suite.
  ///
  /// Es un parámetro y no una constante porque en oscuro `accent` y
  /// `accentText` son EL MISMO color: cualquier bug de contraste que dependa
  /// de esa diferencia es invisible acá, y ya nos pasó. Los tests de color
  /// pasan `AppTheme.light()`.
  ThemeData? theme,
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
  // PR2 — exercise progression overrides
  List<ExerciseListEntry>? exerciseList,
  ExerciseProgression? exerciseProgression,
  // PR9 — Resumen tab: nota fijada, próxima sesión, última sesión
  AthleteNote? athleteNote,
  List<Appointment> appointments = const [],
  Map<String, double> lastWeightByExercise = const {},
  // PR2 (pagos) — trainer's own profile (for paymentAlias)
  UserProfile? trainerProfile,
  // PR2b — daily heat-map section (AD5): backs athleteDayInsightsProvider /
  // athleteLast7DaysInsightsProvider. Defaults to an empty-history mock so
  // existing tests that don't care about this section keep passing.
  SessionRepository? sessionRepository,
  // Chat tab (name-flash fix): the resolved Chat for PF↔alumno + its
  // messages. Defaults keep every existing test (which never taps into
  // Chat) unaffected — `chatForOtherUidProvider` only resolves when the
  // tab actually builds.
  Chat? chat,
  List<Message> chatMessages = const [],
  AlumnoDetailIndicators indicators = const AlumnoDetailIndicators(),
  // Escape hatch for id-specific overrides (e.g. a delayed
  // `userPublicProfileProvider('a1')`) that must win over the family-wide
  // defaults above — Riverpod resolves instance-specific overrides before
  // family-wide ones regardless of list position, so appending these last
  // is just for readability, not correctness.
  List<Override> extraOverrides = const [],
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
        assignedRoutinesByTrainerProvider.overrideWith((ref, key) => routines),
        sessionsByUidProvider.overrideWith((ref, id) {
          if (sessionsError != null) throw sessionsError;
          return sessions;
        }),
        coachSessionSetLogsProvider.overrideWith((ref, key) async => setLogs),
        if (paymentRepo != null)
          paymentRepositoryProvider.overrideWithValue(paymentRepo),
        // PR2 — exercise progression providers (default: no exercises / empty)
        athleteExerciseListProvider.overrideWith(
          (ref, uid) async => exerciseList ?? const [],
        ),
        exerciseProgressionProvider.overrideWith(
          (ref, key) async =>
              exerciseProgression ??
              ExerciseProgression.empty(
                exerciseId: key.exerciseId,
                exerciseName: '',
              ),
        ),
        // PR9 — nota fijada, próxima sesión, última sesión por ejercicio
        athleteNoteProvider.overrideWith(
          (ref, key) => Stream.value(athleteNote),
        ),
        trainerAppointmentsStreamProvider.overrideWith(
          (ref, key) => Stream.value(appointments),
        ),
        lastWeightByExerciseProvider.overrideWith(
          (ref, uid) async => lastWeightByExercise,
        ),
        // PR2 (pagos) — trainer profile (paymentAlias for recordar())
        userProfileProvider.overrideWith(
          (ref) => Stream.value(trainerProfile),
        ),
        // PR2b — daily heat-map section (AD5).
        sessionRepositoryProvider.overrideWithValue(
          sessionRepository ?? _emptySessionRepository(),
        ),
        exercisesProvider.overrideWith((ref) async => const []),
        // Chat tab (name-flash fix).
        chatForOtherUidProvider.overrideWith(
          (ref, otherUid) async => chat ?? _chat(),
        ),
        messagesProvider.overrideWith(
          (ref, chatId) => Stream.value(chatMessages),
        ),
        alumnoDetailIndicatorsProvider('a1').overrideWithValue(indicators),
        ...extraOverrides,
      ],
      child: MaterialApp(
        // l10n EXACTO como CoachHubApp (W2 PR8): delegates + supportedLocales +
        // localeResolutionCallback. Sin el callback resuelve a `en` (1º en
        // supportedLocales) y los strings del chart salen en blanco.
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        localeResolutionCallback: (l, s) =>
            resolveLocale(l ?? const Locale('es', 'AR'), s),
        theme: theme ?? AppTheme.dark(),
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
      // Sesiones y racha dejaron de ser cards propias —costaban una fila de
      // ~85px en la pantalla donde el alto es el recurso escaso— y viven en
      // línea con el resto de los metadatos. `find.text` no las ve porque son
      // spans de un RichText, así que se afirma sobre el texto plano del span.
      // `Text.rich`, no `RichText`: el segundo no hereda el DefaultTextStyle y
      // el texto sale en tofu. Se afirma sobre el texto plano del span.
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && w.textSpan?.toPlainText() == '38 sesiones',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && w.textSpan?.toPlainText() == '14 d de racha',
        ),
        findsOneWidget,
      );
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
      expect(find.widgetWithText(TreinoButton, 'Pago'), findsOneWidget);
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

    testWidgets('header: «Pago» se LEE y hace juego con el botón de chat',
        (tester) async {
      // El PF: «esos dos botones en la ficha del alumno están feos». Dos cosas
      // objetivas debajo de eso:
      //
      // 1. «Pago» pintaba con `palette.accent`, que es un color de FONDO. Como
      //    texto sobre la card blanca mide 1,64:1 contra los 4,5 de WCAG AA:
      //    se veía lavado. `accentText` es el acento legible como texto (en
      //    oscuro son el mismo color, por eso el tema oscuro nunca lo mostró).
      // 2. Los dos pills son hermanos y tenían padding horizontal distinto,
      //    14 contra 12. Dos pills contiguas que difieren en 2 px se leen como
      //    un error de alineación.
      // EN CLARO a propósito: en oscuro `accent` y `accentText` son el mismo
      // color y este test no distinguiría nada. La primera versión corría en
      // el tema por defecto y pasaba con el bug puesto — lo cazó el control
      // negativo, no el test.
      await _pump(tester, theme: AppTheme.light());
      await tester.pumpAndSettle();

      final ctx = tester.element(find.widgetWithText(TreinoButton, 'Pago'));
      final palette = AppPalette.of(ctx);

      // El color ya no sale de este callsite: sale de la variante. Que el
      // arreglo de contraste viva en el token es lo que impide que el próximo
      // botón lo vuelva a resolver por su cuenta.
      final fg = TreinoButtonTokens.of(ctx, TreinoButtonVariant.secondaryAccent)
          .foreground;
      expect(fg, palette.accentText, reason: 'texto, no fondo');

      final sobreLaCard = _contraste(fg, palette.bgCard);
      expect(
        sobreLaCard,
        greaterThanOrEqualTo(4.5),
        reason: '«Pago» mide ${sobreLaCard.toStringAsFixed(2)}:1 sobre la '
            'card. Con `accent` daba 1,64:1.',
      );

      // Y el par. Ya no se compara el padding DECLARADO —que ya era igual—
      // sino el alto RENDERIZADO, que es lo que el usuario ve y lo que estaba
      // mal: el árbol de semántica de producción reportaba 16 px para «Chat»
      // y 19 para «Pago», con el mismo padding declarado en los dos.
      final altoPago =
          tester.getSize(find.widgetWithText(TreinoButton, 'Pago')).height;
      final altoChat = tester
          .getSize(find.ancestor(
            of: find.byIcon(TreinoIcon.chat),
            matching: find.byType(TreinoButton),
          ))
          .height;
      expect(altoPago, altoChat,
          reason: 'dos pills hermanas que miden distinto se leen como un '
              'error de alineación');
      expect(altoPago, TreinoButtonSize.sm.height);
    });

    testWidgets('header: botón Pago abre el diálogo de registrar pago (W2 PR7)',
        (tester) async {
      await _pump(tester,
          profile: _prof(),
          link: _link(TrainerLinkStatus.active),
          paymentRepo: _MockPaymentRepo());

      await tester.tap(find.widgetWithText(TreinoButton, 'Pago'));
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
      expect(find.widgetWithText(TreinoButton, 'Pago'), findsOneWidget);
    });

    testWidgets(
        'ningún nivel de navegación usa TreinoSegmentedPill — ni el primero '
        'ni las sub-vistas de los cuatro grupos que la tienen', (tester) async {
      // El guard que faltó. La migración de la sub-navegación se hizo con un
      // reemplazo de texto que NO matcheaba —una coma de más en el patrón— y
      // como el script usaba `if patrón in texto` en vez de `assert`, falló en
      // silencio: migró sólo el grupo Privado, el único escrito con un literal.
      // Los otros tres se mergearon con la píldora intacta y lo encontró el
      // usuario mirando la pantalla, no el CI.
      //
      // Este test recorre los cuatro grupos con sub-vista. Que la píldora sea
      // del kit y siga siendo correcta en Feed, Entrenar, Coach y el discovery
      // es justamente por qué su ausencia acá no se puede afirmar mirando un
      // solo lugar.
      await _pump(tester,
          profile: _prof(), link: _link(TrainerLinkStatus.active));

      expect(find.byType(TreinoSegmentedPill), findsNothing,
          reason: 'el primer nivel volvió a la píldora');

      for (final grupo in ['Entrenamiento', 'Progreso', 'Plan', 'Privado']) {
        await navigateAlumnoDetail(tester, group: grupo);
        expect(
          find.byType(TreinoSegmentedPill),
          findsNothing,
          reason: 'la sub-navegación de $grupo volvió a la píldora',
        );
      }
    });

    testWidgets(
        'tab bar muestra exactamente los 6 grupos — Chat NO es uno de ellos',
        (tester) async {
      await _pump(tester,
          profile: _prof(), link: _link(TrainerLinkStatus.active));
      expect(find.byType(Tab), findsNWidgets(6));
      // Chat salió de la navegación: ya tiene su propia sección en el sidebar,
      // y como pestaña gastaba un destino de primer nivel. Vive en el header
      // como acción, que conserva el acceso de un click a ESTE alumno —
      // `/chat` no toma parámetro de alumno, así que borrarla sin más lo
      // habría perdido.
      expect(
        find.descendant(of: find.byType(TabBar), matching: find.text('Chat')),
        findsNothing,
        reason: 'Chat volvió a ser una pestaña',
      );
      for (final t in [
        'Resumen',
        'Entrenamiento',
        'Progreso',
        'Plan',
        'Privado',
        'Pagos',
      ]) {
        expect(
          find.descendant(of: find.byType(TabBar), matching: find.text(t)),
          findsOneWidget,
          reason: 'falta el tab $t',
        );
      }
      expect(
        tester.widget<TabBar>(find.byType(TabBar).first).isScrollable,
        isFalse,
      );
    });

    testWidgets('Privado explicita que el alumno no ve su contenido',
        (tester) async {
      await _pump(tester,
          profile: _prof(), link: _link(TrainerLinkStatus.active));

      await navigateAlumnoDetail(tester, group: 'Privado');

      expect(find.byIcon(TreinoIcon.lock), findsOneWidget);
      expect(find.text('Nada de esto lo ve el alumno.'), findsOneWidget);
      expect(find.text('Notas'), findsOneWidget);
      expect(find.text('Seguimiento'), findsOneWidget);
    });

    testWidgets(
        'la marca neutra y la de acento salen de tokens distintos — el acento '
        'usa accentText, que es el que se ve en tema CLARO', (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        indicators: const AlumnoDetailIndicators(
          entrenamiento: AlumnoGrupoEstado.conContenido,
          progreso: AlumnoGrupoEstado.conContenido,
          plan: AlumnoGrupoEstado.conContenido,
          chat: AlumnoGrupoEstado.requiereAtencion,
          privado: AlumnoGrupoEstado.conContenido,
          pagos: AlumnoGrupoEstado.requiereAtencion,
        ),
      );

      final palette = AppPalette.of(
        tester.element(find.byType(AlumnoDetailScreen)),
      );

      Color colorDeMarca(int index) {
        final dot = tester.widget<Container>(
          find.byKey(alumnoDetailMarcaKey(index)),
        );
        return (dot.decoration! as BoxDecoration).color!;
      }

      // Índices de _tabs: 1 Entrenamiento, 2 Progreso, 3 Plan, 4 Privado,
      // 5 Pagos. Resumen (0) nunca lleva marca. Chat ya no es una pestaña —
      // su punto de sin-leer vive en la acción del header.
      expect(find.byKey(alumnoDetailMarcaKey(0)), findsNothing);
      for (final index in [1, 2, 3, 4]) {
        expect(colorDeMarca(index), palette.textMuted,
            reason: 'la celda $index es contenido, va neutra');
      }
      expect(colorDeMarca(5), palette.accentText,
          reason: 'Pagos reclama acción, va en acento');

      // El que importa, y por qué se mide contra la paleta LIGHT a mano: este
      // harness pumpea el tema oscuro, donde `accentText` y `accent` son el
      // mismo mint. O sea que las aserciones de arriba pasarían igual si la
      // marca de atención usara `accent` — el bug que se quiere impedir es
      // invisible en dark. En light NO son el mismo color, y ésa es la razón
      // de que el token exista: el mint pleno compone 1,57:1 como tinta sobre
      // fondo claro, que es el tema que el PF usa en el Coach Hub.
      expect(
        AppPalette.mintMagentaLight.accentText,
        isNot(AppPalette.mintMagentaLight.accent),
        reason: 'si en light dejaran de divergir, la marca de atención sería '
            'invisible en el tema del Coach Hub y ningún test lo vería',
      );
    });

    /// Lo que anuncia una pestaña, como patrón anclado al principio.
    ///
    /// `TabBar` le agrega al label su propia pista de posición, así que la
    /// etiqueta real es `"<lo nuestro>\nPestaña N de 7"`. Comparar por
    /// igualdad exacta contra `"Progreso"` da falso negativo, y comparar sin
    /// anclar haría que `"Progreso"` matcheara también `"Progreso, sin
    /// contenido"` — justo la distinción que estos tests existen para probar.
    Finder anuncio(String label) =>
        find.bySemanticsLabel(RegExp('^${RegExp.escape(label)}\n'));

    testWidgets(
        'un grupo cuyo stream todavía carga NO lleva marca ni afirma vacío',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        // Todo en desconocido = el estado real mientras los streams cargan.
        indicators: const AlumnoDetailIndicators(),
      );

      for (var index = 0; index < 6; index++) {
        expect(find.byKey(alumnoDetailMarcaKey(index)), findsNothing,
            reason: 'un estado desconocido no pinta punto');
      }
      expect(anuncio('Progreso'), findsOneWidget);
      expect(anuncio('Progreso, sin contenido'), findsNothing);
      expect(anuncio('Pagos, sin cobros pendientes'), findsNothing);
      handle.dispose();
    });

    testWidgets('Semantics anuncia en palabras el estado de cada grupo',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        indicators: const AlumnoDetailIndicators(
          entrenamiento: AlumnoGrupoEstado.conContenido,
          progreso: AlumnoGrupoEstado.vacio,
          plan: AlumnoGrupoEstado.conContenido,
          chat: AlumnoGrupoEstado.requiereAtencion,
          privado: AlumnoGrupoEstado.vacio,
          pagos: AlumnoGrupoEstado.requiereAtencion,
        ),
      );

      expect(anuncio('Resumen'), findsOneWidget);
      expect(anuncio('Entrenamiento, con contenido'), findsOneWidget);
      expect(anuncio('Progreso, sin contenido'), findsOneWidget);
      expect(anuncio('Plan, con contenido'), findsOneWidget);
      expect(anuncio('Privado, sin contenido'), findsOneWidget);
      expect(anuncio('Pagos, con cobro pendiente'), findsOneWidget);
      handle.dispose();
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

      await navigateAlumnoDetail(
        tester,
        group: 'Entrenamiento',
        subview: 'Sesiones',
      );

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

      await navigateAlumnoDetail(
        tester,
        group: 'Entrenamiento',
        subview: 'Sesiones',
      );

      expect(find.text('El alumno no compartió su historial.'), findsOneWidget);
      expect(find.text('No se pudo cargar el historial.'), findsNothing);
    });

    testWidgets(
        'Entrenamientos: #628 un reporte sobre un ejercicio SIN series se ve',
        (tester) async {
      // Mismo agujero que en el athlete-detail mobile: los bloques salían
      // EXCLUSIVAMENTE de los SetLog, así que un exerciseId con cero logs no
      // tenía grupo y su reporte no se renderizaba en ninguna parte.
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        sessions: [_session(id: 's1', routineName: 'Hipertrofia 4 días')],
        setLogs: [_setLog(exerciseName: 'Sentadilla')],
        extraOverrides: [
          coachSessionExerciseFeedbackProvider
              .overrideWith((ref, key) async => [_feedback()]),
        ],
      );

      await navigateAlumnoDetail(
        tester,
        group: 'Entrenamiento',
        subview: 'Sesiones',
      );
      await tester.tap(find.text('Hipertrofia 4 días'));
      await tester.pumpAndSettle();

      expect(find.text('Sentadilla'), findsOneWidget);
      expect(find.text('Remo en polea'), findsOneWidget);
      expect(find.text('Me tira el hombro'), findsOneWidget);
    });

    testWidgets(
        'Entrenamientos: #628 sesión con reportes y CERO series no muestra '
        'sólo "sin series"', (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        sessions: [_session(id: 's1', routineName: 'Hipertrofia 4 días')],
        setLogs: const [],
        extraOverrides: [
          coachSessionExerciseFeedbackProvider
              .overrideWith((ref, key) async => [_feedback(setNumber: 2)]),
        ],
      );

      await navigateAlumnoDetail(
        tester,
        group: 'Entrenamiento',
        subview: 'Sesiones',
      );
      await tester.tap(find.text('Hipertrofia 4 días'));
      await tester.pumpAndSettle();

      expect(find.text('Sin series registradas en esta sesión.'), findsNothing);
      expect(find.text('Remo en polea'), findsOneWidget);
      expect(find.text('Me tira el hombro'), findsOneWidget);
    });

    testWidgets(
        'Entrenamientos: #628 si FALLA la lectura de reportes se avisa Y las '
        'series siguen', (tester) async {
      // Idéntico al mobile: degradar a lista vacía sin avisar le muestra al PF
      // un historial normal y lo deja concluir que no hubo molestias.
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        sessions: [_session(id: 's1', routineName: 'Hipertrofia 4 días')],
        setLogs: [_setLog(exerciseName: 'Sentadilla')],
        extraOverrides: [
          coachSessionExerciseFeedbackProvider
              .overrideWith((ref, key) async => throw Exception('boom')),
        ],
      );

      await navigateAlumnoDetail(
        tester,
        group: 'Entrenamiento',
        subview: 'Sesiones',
      );
      await tester.tap(find.text('Hipertrofia 4 días'));
      await tester.pumpAndSettle();

      expect(find.text('No pudimos cargar los reportes del alumno.'),
          findsOneWidget);
      expect(find.text('Sentadilla'), findsOneWidget);
      expect(find.text('Sin series registradas en esta sesión.'), findsNothing);
    });

    testWidgets(
        'Entrenamientos: #628 el aviso convive con el placeholder de sesión '
        'vacía', (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        sessions: [_session(id: 's1', routineName: 'Hipertrofia 4 días')],
        setLogs: const [],
        extraOverrides: [
          coachSessionExerciseFeedbackProvider
              .overrideWith((ref, key) async => throw Exception('boom')),
        ],
      );

      await navigateAlumnoDetail(
        tester,
        group: 'Entrenamiento',
        subview: 'Sesiones',
      );
      await tester.tap(find.text('Hipertrofia 4 días'));
      await tester.pumpAndSettle();

      expect(find.text('No pudimos cargar los reportes del alumno.'),
          findsOneWidget);
      expect(
          find.text('Sin series registradas en esta sesión.'), findsOneWidget);
    });

    testWidgets('Progreso muestra antropometría', (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        measurements: [_meas(60.5, fat: 22.4, waist: 71)],
      );

      await navigateAlumnoDetail(tester, group: 'Progreso');

      expect(find.text('Mediciones antropométricas'), findsOneWidget);
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

      await navigateAlumnoDetail(tester, group: 'Progreso');

      expect(
        find.text('Este alumno todavía no tiene mediciones cargadas.'),
        findsOneWidget,
      );
    });

    testWidgets('Progreso con ≥2 mediciones renderiza el gráfico',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        measurements: [_meas(62, day: 1), _meas(60.5, day: 20)],
      );

      await navigateAlumnoDetail(tester, group: 'Progreso');

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

      await navigateAlumnoDetail(
        tester,
        group: 'Progreso',
        subview: 'Rendimiento',
      );

      expect(find.byType(PerformanceProgressChart), findsOneWidget);
      // El heading dejó de ser el «RENDIMIENTO» suelto del viejo tab Progreso:
      // ahora la sub-vista lleva el header propio que venía de Mediciones.
      expect(find.text('Pruebas de rendimiento'), findsOneWidget);
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

      await navigateAlumnoDetail(
        tester,
        group: 'Progreso',
        subview: 'Rendimiento',
      );

      expect(find.text('Pruebas de rendimiento'), findsOneWidget);
      expect(find.byType(PerformanceProgressChart), findsNothing);
      expect(find.byType(MeasurementProgressChart), findsNothing);
    });

    testWidgets('Progreso separa antropometría y rendimiento sin perder datos',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        measurements: [_meas(62, day: 1), _meas(60.5, day: 20)],
        performanceTests: [_perf(cmjCm: 28, day: 1), _perf(cmjCm: 32, day: 20)],
      );

      await navigateAlumnoDetail(tester, group: 'Progreso');

      expect(find.byType(MeasurementProgressChart), findsOneWidget);
      expect(find.byType(PerformanceProgressChart), findsNothing);

      await navigateAlumnoDetail(
        tester,
        group: 'Progreso',
        subview: 'Rendimiento',
      );

      expect(find.byType(MeasurementProgressChart), findsNothing);
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

      await navigateAlumnoDetail(tester, group: 'Progreso');

      expect(find.text('No se pudo cargar el progreso.'), findsOneWidget);
      expect(find.text('Peso'), findsNothing); // gateado, no se muestra
    });

    // Removed: "tab placeholder muestra 'Próximamente.'" — al implementar
    // Nutrición (última tab pendiente) ningún tab cae ya al fallback
    // `_TabPlaceholder`. Todos los tabs tienen su implementación real.

    testWidgets(
        'Resumen CON rutina asignada muestra las 4 métricas + heatmap (W2 PR4)',
        (tester) async {
      // El fixture ahora trae rutina: sin ella tres de las cuatro métricas no
      // existen, y este test decía "las 4 métricas" mientras montaba un alumno
      // sin plan. Medía el caso equivocado.
      await _pump(tester,
          profile: _prof(),
          link: _link(TrainerLinkStatus.active),
          routines: [_routine()]);

      // Resumen es el tab por defecto: no hace falta tapear.
      expect(find.text('ADHERENCIA 30D'), findsOneWidget);
      expect(find.text('SESIONES / SEM'), findsOneWidget);
      expect(find.text('VOLUMEN'), findsOneWidget);
      expect(find.text('PESO CORPORAL'), findsOneWidget);
      expect(find.text('ADHERENCIA · 12 SEMANAS'), findsOneWidget);
    });

    testWidgets(
        'Resumen SIN rutina no muestra tres métricas en cero: lo dice una vez',
        (tester) async {
      await _pump(tester,
          profile: _prof(), link: _link(TrainerLinkStatus.active));

      // Adherencia, sesiones/sem y volumen se miden CONTRA el plan: sin plan no
      // son cero, son indefinidas. Mostrarlas en cero se lee como un alumno que
      // no entrena, y no es lo mismo que un alumno al que todavía no le
      // asignaron nada.
      expect(find.text('ADHERENCIA 30D'), findsNothing);
      expect(find.text('SESIONES / SEM'), findsNothing);
      expect(find.text('VOLUMEN'), findsNothing);

      // Se dice UNA vez, no susurrado dos veces en los captions.
      expect(find.text('Sin rutina asignada'), findsOneWidget);
      expect(find.text('Sin plan'), findsNothing);

      // El peso NO depende del plan: el alumno se pesa igual, así que su
      // tarjeta se queda.
      expect(find.text('PESO CORPORAL'), findsOneWidget);

      // Y la salida está al lado del problema.
      expect(find.text('Asignar rutina'), findsWidgets);
    });

    testWidgets('heatmap sin una sola sesión no pinta 84 celdas grises',
        (tester) async {
      await _pump(tester,
          profile: _prof(), link: _link(TrainerLinkStatus.active));

      // Con actividad esporádica la grilla informa (se ve dónde entrenó y dónde
      // no). Con CERO, las 84 celdas caen al nivel 0 y la card se vuelve un
      // rectángulo gris del ancho de la pantalla: se lee como un componente
      // roto, no como un alumno que todavía no arrancó.
      expect(find.text('ADHERENCIA · 12 SEMANAS'), findsOneWidget);
      expect(
        find.text('Sin sesiones en las últimas 12 semanas.'),
        findsOneWidget,
      );
    });

    testWidgets('tab Pagos: al día + sin historial (W2 PR5)', (tester) async {
      await _pump(tester,
          profile: _prof(), link: _link(TrainerLinkStatus.active));

      await navigateAlumnoDetail(tester, group: 'Pagos');

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

      await navigateAlumnoDetail(tester, group: 'Pagos');

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

      await navigateAlumnoDetail(tester, group: 'Pagos');

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

      await navigateAlumnoDetail(tester, group: 'Pagos');

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

      await navigateAlumnoDetail(tester, group: 'Pagos');
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

      await navigateAlumnoDetail(tester, group: 'Pagos');
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

      await navigateAlumnoDetail(tester, group: 'Pagos');
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

      await navigateAlumnoDetail(tester, group: 'Pagos');
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

      await navigateAlumnoDetail(tester, group: 'Pagos');
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

      await navigateAlumnoDetail(tester, group: 'Pagos');
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

      await navigateAlumnoDetail(tester, group: 'Pagos');
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

      await navigateAlumnoDetail(tester, group: 'Pagos');
      await tester.tap(find.text('Marcar pagado'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      verifyNever(() => repo.add(any()));
      verifyNever(() => repo.markManyPaid(any(), any()));
    });

    testWidgets('Entrenamiento separa los estados vacíos por sub-vista',
        (tester) async {
      await _pump(tester,
          profile: _prof(), link: _link(TrainerLinkStatus.active));

      await navigateAlumnoDetail(tester, group: 'Entrenamiento');

      expect(find.text('RUTINA ACTIVA'), findsOneWidget);
      expect(find.text('Sin rutina activa asignada.'), findsOneWidget);

      await navigateAlumnoDetail(
        tester,
        group: 'Entrenamiento',
        subview: 'Sesiones',
      );
      expect(find.text('HISTORIAL DE SESIONES'), findsNothing);
      expect(
        find.text('Este alumno todavía no registró sesiones.'),
        findsOneWidget,
      );
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

      await navigateAlumnoDetail(tester, group: 'Entrenamiento');

      expect(find.text('Hipertrofia 4 días'), findsOneWidget); // rutina activa
      expect(
          find.text('2 días · 4 semanas'), findsOneWidget); // resumen (plural)
      expect(find.text('Lunes - Push'), findsOneWidget); // día
      expect(find.text('0 ejercicios'), findsNWidgets(2)); // 2 días sin slots

      await navigateAlumnoDetail(
        tester,
        group: 'Entrenamiento',
        subview: 'Sesiones',
      );
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

      await navigateAlumnoDetail(tester, group: 'Entrenamiento');

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

      await navigateAlumnoDetail(tester, group: 'Entrenamiento');

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

      await navigateAlumnoDetail(tester, group: 'Entrenamiento');

      expect(find.text('Plan heredado'), findsOneWidget);
      expect(find.text('Sin rutina activa asignada.'), findsNothing);
    });

    testWidgets(
        'Entrenamiento excluye rutina archivada y conserva sesión en curso',
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

      await navigateAlumnoDetail(tester, group: 'Entrenamiento');

      expect(find.text('Sin rutina activa asignada.'), findsOneWidget);
      expect(find.text('Rutina vieja'), findsNothing);

      await navigateAlumnoDetail(
        tester,
        group: 'Entrenamiento',
        subview: 'Sesiones',
      );
      expect(find.text('En curso'), findsOneWidget);
      expect(find.text('EN CURSO'), findsOneWidget);
    });

    testWidgets('Sesiones conserva una sesión incompleta con su badge',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        sessions: [
          _session(routineName: 'Abandonada', wasFullyCompleted: false)
        ],
      );

      await navigateAlumnoDetail(
        tester,
        group: 'Entrenamiento',
        subview: 'Sesiones',
      );

      expect(find.text('Abandonada'), findsOneWidget);
      expect(find.text('INCOMPLETA'), findsOneWidget);
    });

    testWidgets('Sesiones usa startedAt cuando finishedAt falta',
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
            // Local, no `.utc`: la tabla formatea instantes reales y los
            // localiza (#380), así que un `DateTime.utc(2026,1,10)` se
            // renderiza 09/01 en ART y el test mediría el huso, no el fallback
            // a startedAt que quiere probar.
            startedAt: DateTime(2026, 1, 10),
            status: SessionStatus.finished,
            wasFullyCompleted: true,
            durationMin: 30,
            totalVolumeKg: 1000,
          ),
        ],
      );

      await navigateAlumnoDetail(
        tester,
        group: 'Entrenamiento',
        subview: 'Sesiones',
      );

      expect(find.text('Sin fecha'), findsOneWidget);
      expect(find.text('10/01/2026'), findsOneWidget);
    });

    testWidgets('Sesiones no conserva el viejo límite de 20 filas',
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

      await navigateAlumnoDetail(
        tester,
        group: 'Entrenamiento',
        subview: 'Sesiones',
      );

      expect(find.text('Sesión 0'), findsOneWidget);
      expect(find.text('Sesión 19'), findsOneWidget);
      expect(find.text('Sesión 20'), findsOneWidget);
      expect(find.text('HISTORIAL DE SESIONES'), findsNothing);
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
              body: AlumnoDetailScreen(
                athleteId: s.pathParameters['id']!,
                tabInicial: s.uri.queryParameters['tab'],
              ),
            ),
          ),
          // Doble del Chat global: alcanza con que diga que se llego.
          GoRoute(
            path: '/chat',
            builder: (_, __) => const Scaffold(body: Text('CHAT GLOBAL')),
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
            // El boton de Chat del header resuelve/crea el chat 1-1 antes de
            // navegar; sin este stub pega contra Firestore real y la
            // navegacion nunca llega.
            chatForOtherUidProvider.overrideWith(
              (ref, otherUid) async => Chat(
                chatId: 'chat_$otherUid',
                members: ['trainer-1', otherUid],
                createdAt: DateTime.utc(2026, 1, 1),
              ),
            ),
            trainerLinkRepositoryProvider.overrideWithValue(repo),
            // El detalle abre en Resumen (W2 PR4), que lee estos providers.
            sessionsByUidProvider.overrideWith((ref, id) => const <Session>[]),
            assignedRoutinesByTrainerProvider
                .overrideWith((ref, key) => const <Routine>[]),
            currentUidProvider.overrideWithValue('t1'),
            alumnoDetailIndicatorsProvider('a1').overrideWithValue(
              const AlumnoDetailIndicators(),
            ),
            // El header (W2 PR7) lee el billing del alumno.
            athleteBillingProvider
                .overrideWith((ref, id) => Stream.value(null)),
            // PR9 — nuevos widgets del Resumen tab.
            athleteNoteProvider.overrideWith((ref, key) => Stream.value(null)),
            trainerAppointmentsStreamProvider
                .overrideWith((ref, key) => Stream.value(const [])),
            lastWeightByExerciseProvider
                .overrideWith((ref, uid) async => const {}),
            coachSessionSetLogsProvider
                .overrideWith((ref, key) async => const []),
          ],
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            routerConfig: router,
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            locale: const Locale('es', 'AR'),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('el boton de Chat del header NAVEGA al chat, no abre un modal',
        (tester) async {
      // Antes abria un `Dialog` con la conversacion adentro. El PF lo tocaba
      // esperando ir al chat y se quedaba en un modal: «si toco el chat que me
      // redirija al chat directamente».
      //
      // Es el mismo destino al que lleva el boton de chat del roster —misma
      // funcion compartida—, asi que el mismo icono lleva al mismo lugar desde
      // los dos lados.
      await pumpRouter(tester, repo: _MockRepo());
      await tester.tap(find.text('Sofía'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Chat'));
      await tester.pumpAndSettle();

      expect(find.text('CHAT GLOBAL'), findsOneWidget);
      // Y no quedo un modal encima: se NAVEGA, no se superpone.
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('entrar con ?tab=plan abre la ficha en Plan, no en Resumen',
        (tester) async {
      // Es el camino que usa Nutricion: «si entro a un alumno, que me mande
      // directamente al apartado para cargarle plan nutricional, derecho».
      await pumpRouter(tester, repo: _MockRepo());
      final router = GoRouter.of(tester.element(find.text('Sofía')));
      router.push('/alumnos/a1?tab=plan');
      await tester.pumpAndSettle();

      // El heatmap es marcador exclusivo del Resumen: si estuviera, la ficha
      // habria abierto en la pestana de siempre.
      expect(find.text('ADHERENCIA · 12 SEMANAS'), findsNothing);
    });

    testWidgets('una clave de tab inexistente abre en Resumen y no rompe',
        (tester) async {
      // La URL la puede escribir cualquiera, y un link viejo tiene que abrir
      // la ficha, no romperla.
      await pumpRouter(tester, repo: _MockRepo());
      final router = GoRouter.of(tester.element(find.text('Sofía')));
      router.push('/alumnos/a1?tab=noExiste');
      await tester.pumpAndSettle();

      expect(find.text('ADHERENCIA · 12 SEMANAS'), findsOneWidget);
    });

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

    testWidgets(
        'tap en la acción Terminar (vía menú ⋮) abre diálogo y NO navega',
        (tester) async {
      final repo = _MockRepo();
      when(() => repo.terminate(any(), reason: any(named: 'reason')))
          .thenAnswer((_) async {});

      await pumpRouter(tester, repo: repo);
      // La acción vive detrás del menú ⋮ de la fila (ya no es un ícono
      // inline) — abrirlo primero prueba también que el ⋮ no dispara la
      // navegación de la fila (tap independiente, no propaga).
      await tester.tap(find.byIcon(TreinoIcon.dotsThree));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Terminar')); // item del bottom sheet
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

  // ── PR2: Entrenamientos tab — evolución por ejercicio (TASK-10) ──────────────

  group('tab Entrenamientos: evolución por ejercicio (PR2)', () {
    testWidgets(
        'placeholder "Próximamente" ya no existe en el tab Entrenamientos (TASK-10)',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
      );

      await navigateAlumnoDetail(
        tester,
        group: 'Entrenamiento',
        subview: 'Sesiones',
      );

      // SCENARIO-PROG-11A: placeholder gone.
      expect(
        find.textContaining('Próximamente: evolución'),
        findsNothing,
      );
    });

    testWidgets(
        'sin setLogs → empty-state "sin registros" (SCENARIO-PROG-08A / REQ-PROG-11)',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        exerciseList: const [], // no exercises
      );

      await navigateAlumnoDetail(
        tester,
        group: 'Entrenamiento',
        subview: 'Sesiones',
      );

      // Empty state label (SCENARIO-PROG-08A).
      expect(find.text('EVOLUCIÓN POR EJERCICIO'), findsOneWidget);
      expect(find.textContaining('Sin registros'), findsOneWidget);
      // Picker and chart are NOT rendered when list is empty.
      expect(find.byType(ExercisePickerRow), findsNothing);
    });

    testWidgets(
        'con setLogs → picker + chart renderizan (SCENARIO-PROG-11A / REQ-PROG-11)',
        (tester) async {
      const entry = ExerciseListEntry(
        exerciseId: 'squat',
        exerciseName: 'Sentadilla',
      );
      final progression = ExerciseProgression(
        exerciseId: 'squat',
        exerciseName: 'Sentadilla',
        heaviestWeightSeries: [
          ProgressionPoint(date: DateTime.utc(2026, 1, 1), value: 90),
          ProgressionPoint(date: DateTime.utc(2026, 1, 8), value: 95),
        ],
        oneRepMaxSeries: [
          ProgressionPoint(date: DateTime.utc(2026, 1, 1), value: 105),
          ProgressionPoint(date: DateTime.utc(2026, 1, 8), value: 110.833),
        ],
        bestSetVolumeSeries: [
          ProgressionPoint(date: DateTime.utc(2026, 1, 1), value: 450),
          ProgressionPoint(date: DateTime.utc(2026, 1, 8), value: 475),
        ],
        bestSessionVolumeSeries: [
          ProgressionPoint(date: DateTime.utc(2026, 1, 1), value: 450),
          ProgressionPoint(date: DateTime.utc(2026, 1, 8), value: 475),
        ],
        personalRecords: const [],
        frequencySessionCount: 3,
      );

      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        exerciseList: [entry],
        exerciseProgression: progression,
      );

      await navigateAlumnoDetail(
        tester,
        group: 'Entrenamiento',
        subview: 'Sesiones',
      );

      // Section header always present.
      expect(find.text('EVOLUCIÓN POR EJERCICIO'), findsOneWidget);
      // Picker renders with exercise name (SCENARIO-PROG-11A).
      expect(find.byType(ExercisePickerRow), findsOneWidget);
      expect(find.text('Sentadilla'), findsOneWidget);
      // Chart widget renders (SCENARIO-PROG-11A).
      expect(find.byType(ExerciseProgressionChart), findsOneWidget);
    });

    testWidgets(
        'strings en web son español hardcodeado, no AppL10n (SCENARIO-PROG-11B)',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
      );

      await navigateAlumnoDetail(
        tester,
        group: 'Entrenamiento',
        subview: 'Sesiones',
      );

      // The section label is always rendered as hardcoded 'EVOLUCIÓN POR EJERCICIO'
      // regardless of locale — never sourced from AppL10n.
      expect(find.text('EVOLUCIÓN POR EJERCICIO'), findsOneWidget);
    });
  });

  // ── PR2b: Entrenamientos tab — heat-map diario (AD5) ──────────────────────

  group('tab Entrenamientos: heat-map diario (PR2b, AD5)', () {
    testWidgets(
        'SCENARIO-DAILY-HEATMAP-COACH-WEB-01: renders the web wrapper\'s '
        'hardcoded-Spanish section title, driven by the alumno\'s athleteId '
        '(a1) — proves no currentUidProvider leak (trainer uid is t1)',
        (tester) async {
      final repo = _MockSessionRepository();
      when(() => repo.listByUid('a1')).thenAnswer((_) async => []);

      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        sessionRepository: repo,
      );

      await navigateAlumnoDetail(
        tester,
        group: 'Entrenamiento',
        subview: 'Sesiones',
      );

      // Web wrapper injects hardcoded Spanish labels — distinct bag from the
      // mobile wrapper's AppL10n-sourced strings (dedup-contract style).
      expect(find.text('MÚSCULOS DEL DÍA'), findsOneWidget);
    });
  });

  // ── PR9: Resumen tab — nota fijada, próxima sesión, última sesión ──────────

  group('Resumen tab — nota fijada (W2 PR9)', () {
    testWidgets('muestra el texto de la nota truncado a 3 líneas (PR9)',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        athleteNote: _note(note: 'Buena progresión en press banca.'),
      );

      // Resumen es el tab default — no hace falta tapear.
      expect(find.text('NOTA FIJADA'), findsOneWidget);
      expect(find.textContaining('Buena progresión'), findsOneWidget);
    });

    testWidgets('sin nota → estado vacío "Sin nota fijada." (PR9)',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        athleteNote: null,
      );

      expect(find.text('NOTA FIJADA'), findsOneWidget);
      expect(find.text('Sin nota fijada.'), findsOneWidget);
    });

    testWidgets('nota con texto vacío → estado vacío (PR9)', (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        athleteNote: _note(note: '   '),
      );

      expect(find.text('Sin nota fijada.'), findsOneWidget);
    });

    testWidgets('muestra "hoy" si updatedAt es reciente (PR9)', (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        athleteNote: _note(updatedAt: DateTime.now().toUtc()),
      );

      expect(find.text('hoy'), findsOneWidget);
    });
  });

  group('Resumen tab — próxima sesión (W2 PR9)', () {
    testWidgets('con sesión futura confirmada → muestra la fecha (PR9)',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        appointments: [_appointment(durationMin: 45)],
      );

      expect(find.text('PRÓXIMA SESIÓN'), findsOneWidget);
      expect(find.text('45 min'), findsOneWidget);
    });

    testWidgets('sin sesiones futuras → estado vacío (PR9)', (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        appointments: const [],
      );

      expect(find.text('PRÓXIMA SESIÓN'), findsOneWidget);
      expect(find.text('Sin sesiones próximas.'), findsOneWidget);
    });

    testWidgets('sesión cancelled no aparece como próxima (PR9)',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        appointments: [
          _appointment(status: AppointmentStatus.cancelled),
        ],
      );

      expect(find.text('Sin sesiones próximas.'), findsOneWidget);
    });

    testWidgets('sesión pasada (confirmed) no aparece como próxima (PR9)',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        appointments: [
          _appointment(
            startsAt: DateTime.utc(2020, 1, 1), // en el pasado
            status: AppointmentStatus.confirmed,
          ),
        ],
      );

      expect(find.text('Sin sesiones próximas.'), findsOneWidget);
    });

    testWidgets('muestra noteBefore si existe (PR9)', (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        appointments: [
          _appointment(noteBefore: 'Traer bandas de resistencia'),
        ],
      );

      expect(find.textContaining('Traer bandas'), findsOneWidget);
    });
  });

  group('Resumen tab — última sesión por ejercicio (W2 PR9)', () {
    testWidgets('sin sesiones → estado vacío "Sin sesiones registradas." (PR9)',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        sessions: const [],
      );

      expect(find.text('ÚLTIMA SESIÓN · POR EJERCICIO'), findsOneWidget);
      expect(find.text('Sin sesiones registradas.'), findsOneWidget);
    });

    testWidgets(
        'con sesión y setLogs → muestra nombre de ejercicio y sets (PR9)',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        sessions: [_session(routineName: 'Push - Pecho')],
        setLogs: [
          _setLog(exerciseName: 'Press banca', setNumber: 1),
          _setLog(exerciseName: 'Press banca', setNumber: 2),
          _setLog(exerciseName: 'Press banca', setNumber: 3),
        ],
      );

      expect(find.text('ÚLTIMA SESIÓN · POR EJERCICIO'), findsOneWidget);
      expect(find.textContaining('Press banca'), findsOneWidget);
      expect(find.text('3 × sets'), findsOneWidget);
    });

    testWidgets('alumno no compartió historial → mensaje "no compartió" (PR9)',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        sessions: [_session()],
        sessionsError: FirebaseException(
            plugin: 'cloud_firestore', code: 'permission-denied'),
      );

      // Un permission-denied en sessionsByUidProvider (link pausado → el CF
      // borró session_shares) NO tumba el Resumen entero: el tab renderiza el
      // resto (métricas, plan, datos) y el card de última sesión avisa que el
      // alumno no comparte su historial, en vez del engañoso "sin sesiones" o
      // un error de tab completo.
      expect(find.text('No se pudo cargar el resumen.'), findsNothing);
      expect(find.text('ÚLTIMA SESIÓN · POR EJERCICIO'), findsOneWidget);
      expect(find.text('El alumno no compartió su historial.'), findsWidgets);
    });

    testWidgets('placeholder viejo ya no existe en Resumen (PR9)',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
      );

      expect(
        find.textContaining('Próximamente: última sesión'),
        findsNothing,
      );
    });
  });

  // ── PR2 (pagos): recordatorios + exportar CSV (alumnos-detail-finish) ─────────

  group('tab Pagos: recordatorios + exportar (PR2 alumnos-detail-finish)', () {
    testWidgets(
        'placeholder "Próximamente: recordatorios y exportar." ya no existe (PR2-PAG)',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        trainerProfile: _trainerProfile(),
      );

      await navigateAlumnoDetail(tester, group: 'Pagos');

      expect(
        find.textContaining('Próximamente: recordatorios y exportar.'),
        findsNothing,
      );
    });

    testWidgets(
        'Exportar CSV button renders when there is payment history (PR2-PAG)',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        payments: [_pago(concept: 'Mensual julio', amountArs: 28000)],
        trainerProfile: _trainerProfile(),
      );

      await navigateAlumnoDetail(tester, group: 'Pagos');

      expect(find.text('Exportar CSV'), findsOneWidget);
    });

    testWidgets('Exportar CSV button renders even with empty history (PR2-PAG)',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        payments: const [],
        trainerProfile: _trainerProfile(),
      );

      await navigateAlumnoDetail(tester, group: 'Pagos');

      // Button always present (even with empty history, 0-row CSV is valid)
      expect(find.text('Exportar CSV'), findsOneWidget);
    });

    testWidgets(
        'Recordar button appears on pending payments in PagosTable (PR2-PAG)',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        payments: [
          _pago(
            id: 'p-pending',
            concept: 'Clase suelta',
            amountArs: 5000,
            status: PaymentStatus.pending,
          ),
        ],
        trainerProfile: _trainerProfile(),
      );

      await navigateAlumnoDetail(tester, group: 'Pagos');

      expect(find.text('Recordar'), findsOneWidget);
    });

    testWidgets('Recordar button does NOT appear on paid payments (PR2-PAG)',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        payments: [
          _pago(
            id: 'p-paid',
            concept: 'Mensual mayo',
            amountArs: 28000,
            status: PaymentStatus.paid,
          ),
        ],
        trainerProfile: _trainerProfile(),
      );

      await navigateAlumnoDetail(tester, group: 'Pagos');

      expect(find.text('Recordar'), findsNothing);
    });

    testWidgets(
        'mix of paid + pending → Recordar only on pending row (PR2-PAG)',
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
          ),
          _pago(
            id: 'p2',
            concept: 'Clase extra',
            amountArs: 5000,
            status: PaymentStatus.pending,
          ),
        ],
        trainerProfile: _trainerProfile(),
      );

      await navigateAlumnoDetail(tester, group: 'Pagos');

      // Exactly one Recordar button (only the pending row)
      expect(find.text('Recordar'), findsOneWidget);
    });
  });
}

/// Contraste WCAG entre dos colores ya opacos.
double _contraste(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
