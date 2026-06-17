// Tests for the Coach Hub web Alumno detail (W2 PR2).
//
// Header (name + estado + denormalized metrics), the 9-tab bar, the Progreso
// tab (Antropometría: measurement cards + chart), and placeholder tabs —
// pumped with stubbed providers (no Firestore, no GoRouter needed since we
// don't tap the back link).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
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
import 'package:treino/features/payments/application/pagos_por_cobrar_provider.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/domain/session.dart';

class _MockRepo extends Mock implements TrainerLinkRepository {}

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

Future<void> _pump(
  WidgetTester tester, {
  UserPublicProfile? profile,
  TrainerLink? link,
  List<Measurement> measurements = const [],
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
        pagosPorCobrarProvider
            .overrideWith((ref) => const AsyncData(<CobroPendiente>[])),
        measurementsForAthleteProvider
            .overrideWith((ref, id) => Stream.value(measurements)),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: AlumnoDetailScreen(athleteId: 'a1')),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => registerFallbackValue(''));

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

    testWidgets('tab bar muestra exactamente las 9 secciones', (tester) async {
      await _pump(tester,
          profile: _prof(), link: _link(TrainerLinkStatus.active));
      expect(find.byType(Tab), findsNWidgets(9));
      for (final t in [
        'Resumen',
        'Entrenamientos',
        'Progreso',
        'Nutrición',
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

    testWidgets('Progreso (tab default) muestra antropometría', (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        measurements: [_meas(60.5, fat: 22.4, waist: 71)],
      );

      expect(find.text('ANTROPOMETRÍA'), findsOneWidget);
      expect(find.text('Peso'), findsOneWidget);
      expect(find.text('60.5 kg'), findsOneWidget);
    });

    testWidgets('Progreso sin mediciones → estado vacío', (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        measurements: const [],
      );
      expect(find.text('Sin mediciones cargadas todavía.'), findsOneWidget);
    });

    testWidgets('Progreso con ≥2 mediciones renderiza el gráfico',
        (tester) async {
      await _pump(
        tester,
        profile: _prof(),
        link: _link(TrainerLinkStatus.active),
        measurements: [_meas(62, day: 1), _meas(60.5, day: 20)],
      );
      expect(find.byType(MeasurementProgressChart), findsOneWidget);
    });

    testWidgets('tab placeholder muestra "Próximamente."', (tester) async {
      await _pump(tester,
          profile: _prof(), link: _link(TrainerLinkStatus.active));

      await tester.tap(find.text('Resumen'));
      await tester.pumpAndSettle();

      expect(find.text('Próximamente.'), findsOneWidget);
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
          ],
          child:
              MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('tap en la fila del roster navega al detalle', (tester) async {
      await pumpRouter(tester, repo: _MockRepo());
      // En el roster todavía (el detalle vacío diría "Sin mediciones…").
      expect(find.text('Sin mediciones cargadas todavía.'), findsNothing);

      await tester.tap(find.text('Sofía'));
      await tester.pumpAndSettle();

      // Ahora en el detalle (Progreso vacío).
      expect(find.text('Sin mediciones cargadas todavía.'), findsOneWidget);
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
      // No navegó al detalle.
      expect(find.text('Sin mediciones cargadas todavía.'), findsNothing);
    });
  });
}
