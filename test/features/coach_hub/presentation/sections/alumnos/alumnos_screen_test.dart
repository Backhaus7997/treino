// Tests for the Coach Hub web Alumnos roster (W2 PR1).
//
// Unit: estadoForLink composite-state derivation.
// Widget: roster rows + estados, filter chips, name search, empty state,
// Con-deuda badge, "Hoy" column, partition counts, link actions, and the
// per-athlete dedup — pumped with stubbed providers (no Firestore).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/data/trainer_link_repository.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/alumnos/alumnos_screen.dart';
import 'package:treino/features/gyms/application/gym_providers.dart';
import 'package:treino/features/gyms/domain/gym.dart';
import 'package:treino/features/payments/application/pagos_por_cobrar_provider.dart';
import 'package:treino/features/payments/domain/athlete_billing.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';

class _MockRepo extends Mock implements TrainerLinkRepository {}

TrainerLink _link(String athleteId, TrainerLinkStatus status, {String? id}) =>
    TrainerLink(
      id: id ?? 'l_$athleteId',
      trainerId: 't1',
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

Session _session(String uid) => Session(
      id: 's_$uid',
      uid: uid,
      routineId: 'r1',
      routineName: 'Push',
      startedAt: DateTime.utc(2026, 1, 1),
      status: SessionStatus.finished,
    );

Future<void> _pump(
  WidgetTester tester,
  List<TrainerLink> links, {
  List<UserPublicProfile> profiles = const [],
  List<CobroPendiente> cobros = const [],
  Set<String> trainedTodayIds = const {},
  TrainerLinkRepository? repo,
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        trainerLinksStreamProvider.overrideWith((ref) => Stream.value(links)),
        userPublicProfilesBatchProvider.overrideWith(
          (ref, key) => {for (final p in profiles) p.uid: p},
        ),
        pagosPorCobrarProvider.overrideWith((ref) => AsyncData(cobros)),
        finishedTodayByUidProvider.overrideWith(
          (ref, uid) => trainedTodayIds.contains(uid)
              ? [_session(uid)]
              : const <Session>[],
        ),
        gymsProvider.overrideWith((ref) => const <Gym>[]),
        if (repo != null) trainerLinkRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const Scaffold(body: AlumnosScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => registerFallbackValue(''));

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

  group('AlumnosScreen roster (W2 PR1)', () {
    testWidgets('renderiza nombres + estados de los alumnos', (tester) async {
      await _pump(
        tester,
        [
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
        [
          _link('a1', TrainerLinkStatus.active),
          _link('a2', TrainerLinkStatus.paused),
        ],
        profiles: [_prof('a1', 'Sofía'), _prof('a2', 'Diego')],
      );

      await tester.tap(find.text('PAUSADOS · 1'));
      await tester.pumpAndSettle();

      expect(find.text('Diego'), findsOneWidget);
      expect(find.text('Sofía'), findsNothing);
    });

    testWidgets('búsqueda filtra por nombre', (tester) async {
      await _pump(
        tester,
        [
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
      await _pump(tester, const []);
      expect(find.text('Todavía no tenés alumnos vinculados.'), findsOneWidget);
    });

    testWidgets('active con deuda → badge Con deuda y NO cuenta como activo',
        (tester) async {
      await _pump(
        tester,
        [_link('a1', TrainerLinkStatus.active)],
        profiles: [_prof('a1', 'Sofía')],
        cobros: [_cobro('a1')],
      );

      expect(find.text('Con deuda'), findsOneWidget); // badge
      // Partición: con-deuda NO se cuenta bajo activos (mockup).
      expect(find.text('1 en total · 0 activos'), findsOneWidget);
    });

    testWidgets('entrenó hoy → columna muestra "Hoy"', (tester) async {
      await _pump(
        tester,
        [_link('a1', TrainerLinkStatus.active)],
        profiles: [_prof('a1', 'Sofía')],
        trainedTodayIds: const {'a1'},
      );
      expect(find.text('Hoy'), findsOneWidget);
    });

    testWidgets('terminar abre diálogo y al confirmar llama repo.terminate',
        (tester) async {
      final repo = _MockRepo();
      when(() => repo.terminate(any(), reason: any(named: 'reason')))
          .thenAnswer((_) async {});

      await _pump(
        tester,
        [_link('a1', TrainerLinkStatus.active)],
        profiles: [_prof('a1', 'Sofía')],
        repo: repo,
      );

      await tester.tap(find.byTooltip('Terminar'));
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
        [_link('a1', TrainerLinkStatus.active)],
        profiles: [_prof('a1', 'Sofía')],
        repo: repo,
      );

      await tester.tap(find.byTooltip('Terminar'));
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
        [
          _link('a1', TrainerLinkStatus.active, id: 'l_new'),
          _link('a1', TrainerLinkStatus.terminated, id: 'l_old'),
        ],
        profiles: [_prof('a1', 'Sofía')],
      );

      expect(find.text('Sofía'), findsOneWidget); // colapsado a una fila
      expect(find.text('1 en total · 1 activos'), findsOneWidget);
    });
  });
}
