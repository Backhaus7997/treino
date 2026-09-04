// Widget tests del gate del paywall del alumno en el editor de rutinas.
//
// Cubren las dos mitades que importan:
//   1. Con el flag APAGADO —el estado en que esto shipea— el editor se
//      comporta EXACTAMENTE como antes. Es el test que garantiza que este PR
//      no le saca nada a los testers de hoy.
//   2. Con el flag encendido, el gate muerde donde tiene que morder y NO
//      muerde donde no: ni al PF, ni al alumno con derecho, ni mientras el
//      entitlement no resolvió.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/analytics/analytics_service.dart';
import 'package:treino/features/paywall/application/athlete_entitlement_provider.dart';
import 'package:treino/features/paywall/domain/athlete_entitlement.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/application/custom_exercise_providers.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart'
    show routineRepositoryProvider;
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/application/user_routines_providers.dart'
    show userCreatedRoutinesProvider;
import 'package:treino/features/workout/data/routine_repository.dart';
import 'package:treino/features/workout/domain/custom_exercise.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/features/workout/presentation/routine_editor_mode.dart';
import 'package:treino/features/workout/presentation/routine_editor_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../../fixtures/exercises.dart';
import '../../../fixtures/routine_editor_ui.dart';
import '../../../helpers/fake_analytics_service.dart';

class _MockRoutineRepository extends Mock implements RoutineRepository {}

Future<void> _pumpEditor(
  WidgetTester tester, {
  required RoutineEditorMode mode,
  required List<Override> overrides,
}) async {
  usarViewportAlto(tester);
  final router = GoRouter(
    initialLocation: '/workout/editor',
    routes: [
      GoRoute(
        path: '/workout/editor',
        pageBuilder: (_, __) => NoTransitionPage(
          child: RoutineEditorScreen(mode: mode),
        ),
      ),
      GoRoute(
        path: '/workout',
        pageBuilder: (_, __) => const NoTransitionPage(
          child: Scaffold(body: Center(child: Text('WorkoutHome'))),
        ),
      ),
      GoRoute(
        path: '/coach',
        pageBuilder: (_, __) => const NoTransitionPage(
          child: Scaffold(body: Center(child: Text('CoachHome'))),
        ),
      ),
    ],
  );
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
  await tester.pumpAndSettle();
}

List<Override> _overrides({
  String uid = 'athlete-1',
  bool? paywallEnabled,
  AthleteEntitlement? entitlement,
}) {
  return [
    currentUidProvider.overrideWithValue(uid),
    routineRepositoryProvider.overrideWithValue(_MockRoutineRepository()),
    exercisesProvider.overrideWith((ref) async => kExerciseSeed),
    customExercisesForTrainerStreamProvider(uid).overrideWith(
      (ref) => Stream<List<CustomExercise>>.value(const <CustomExercise>[]),
    ),
    analyticsServiceProvider.overrideWithValue(FakeAnalyticsService()),
    userCreatedRoutinesProvider(uid).overrideWith(
      (ref) => Stream<List<Routine>>.value(const []),
    ),
    if (paywallEnabled != null)
      athletePaywallEnabledProvider.overrideWithValue(paywallEnabled),
    if (entitlement != null)
      athleteEntitlementProvider.overrideWithValue(entitlement),
  ];
}

/// Tap en el "+" de la barra de días. Por key: el botón es sólo un ícono y
/// "Agregar día" vive en su `Semantics.label`.
Future<void> _tapAgregarDia(WidgetTester tester) async {
  await cerrarDatosDelPlan(tester);
  final boton = find.byKey(const Key('day_tab_add'));
  await tester.ensureVisible(boton);
  await tester.tap(boton);
  await tester.pumpAndSettle();
}

Future<void> _tapAgregarSemana(WidgetTester tester) async {
  await abrirDatosDelPlan(tester);
  final boton = find.byKey(const Key('add_week_button'));
  await desplazarHasta(tester, boton);
  await tester.tap(boton);
  await tester.pumpAndSettle();
}

Finder get _sheet => find.byKey(const Key('free_plan_limit_grabber'));

void main() {
  setUpAll(() {
    registerFallbackValue(
      const Routine(
        id: '',
        name: '',
        split: null,
        level: ExperienceLevel.beginner,
        days: [],
        source: RoutineSource.userCreated,
        visibility: RoutineVisibility.private,
        numWeeks: 1,
      ),
    );
  });

  group('flag apagado — el estado en que esto shipea', () {
    testWidgets('el alumno free llega al tercer día sin ver ninguna hoja',
        (tester) async {
      // ESTE es el test que protege a los 8 testers de hoy: nadie puede pagar
      // todavía, así que todos son `free`. Si el gate estuviera activo, este
      // camino quedaría cortado sin salida.
      await _pumpEditor(
        tester,
        mode: const SelfCreating(),
        overrides: _overrides(
          paywallEnabled: false,
          entitlement: AthleteEntitlement.free,
        ),
      );

      await _tapAgregarDia(tester);
      await _tapAgregarDia(tester); // el que cruzaría el tope de 2

      expect(_sheet, findsNothing);
      expect(find.byKey(const Key('day_tab_2')), findsOneWidget,
          reason: 'con el flag apagado el tercer día se agrega igual');
    });
  });

  group('flag encendido', () {
    testWidgets('alumno free: el "+" del tercer día abre la hoja y NO agrega',
        (tester) async {
      await _pumpEditor(
        tester,
        mode: const SelfCreating(),
        overrides: _overrides(
          paywallEnabled: true,
          entitlement: AthleteEntitlement.free,
        ),
      );

      await _tapAgregarDia(tester); // 1 → 2, dentro del tope
      expect(_sheet, findsNothing, reason: 'el segundo día es gratis');

      await _tapAgregarDia(tester); // 2 → 3, cruza

      expect(_sheet, findsOneWidget);
      expect(find.byKey(const Key('day_tab_2')), findsNothing,
          reason: 'el día no se agregó');
    });

    testWidgets('la hoja no ofrece un botón de pago que no lleva a ningún lado',
        (tester) async {
      // Mientras no exista checkout, `onUpgrade` es null y el CTA no se dibuja.
      // Un botón que promete una salida inexistente es peor que no tenerlo.
      await _pumpEditor(
        tester,
        mode: const SelfCreating(),
        overrides: _overrides(
          paywallEnabled: true,
          entitlement: AthleteEntitlement.free,
        ),
      );
      await _tapAgregarDia(tester);
      await _tapAgregarDia(tester);

      expect(_sheet, findsOneWidget);
      expect(find.byKey(const Key('free_plan_limit_upgrade')), findsNothing);
      expect(find.byKey(const Key('free_plan_limit_dismiss')), findsOneWidget);
    });

    testWidgets('alumno con derecho: no se le gatea nada', (tester) async {
      await _pumpEditor(
        tester,
        mode: const SelfCreating(),
        overrides: _overrides(
          paywallEnabled: true,
          entitlement: AthleteEntitlement.entitled,
        ),
      );

      await _tapAgregarDia(tester);
      await _tapAgregarDia(tester);

      expect(_sheet, findsNothing);
      expect(find.byKey(const Key('day_tab_2')), findsOneWidget);
    });

    testWidgets('entitlement unknown: falla ABIERTO, deja pasar',
        (tester) async {
      // El servidor rebota la escritura si no corresponde. Bloquear acá por un
      // read en vuelo sería castigar a quien paga por una red lenta.
      await _pumpEditor(
        tester,
        mode: const SelfCreating(),
        overrides: _overrides(
          paywallEnabled: true,
          entitlement: AthleteEntitlement.unknown,
        ),
      );

      await _tapAgregarDia(tester);
      await _tapAgregarDia(tester);

      expect(_sheet, findsNothing);
      expect(find.byKey(const Key('day_tab_2')), findsOneWidget);
    });

    testWidgets('el PF nunca ve el gate, aunque figure como free',
        (tester) async {
      // El editor del PF escribe `trainer-assigned`, no `user-created`. El PF
      // ya paga por su cupo — este paywall no es el suyo.
      await _pumpEditor(
        tester,
        mode: const TrainerAssigning(athleteId: 'athlete-9'),
        overrides: _overrides(
          uid: 'trainer-1',
          paywallEnabled: true,
          entitlement: AthleteEntitlement.free,
        ),
      );

      await _tapAgregarDia(tester);
      await _tapAgregarDia(tester);

      expect(_sheet, findsNothing);
      expect(find.byKey(const Key('day_tab_2')), findsOneWidget);
    });

    testWidgets('alumno free: "+ Semana" abre la hoja y no suma la semana',
        (tester) async {
      await _pumpEditor(
        tester,
        mode: const SelfCreating(),
        overrides: _overrides(
          paywallEnabled: true,
          entitlement: AthleteEntitlement.free,
        ),
      );

      await _tapAgregarSemana(tester); // 1 → 2, cruza el tope de 1

      expect(_sheet, findsOneWidget);
      await tester.tap(find.byKey(const Key('free_plan_limit_dismiss')));
      await tester.pumpAndSettle();
      await abrirDatosDelPlan(tester);
      expect(find.byKey(const Key('week_tab_1')), findsNothing,
          reason: 'la semana no se agregó');
    });
  });
}
