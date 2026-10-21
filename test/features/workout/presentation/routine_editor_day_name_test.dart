// Campo NOMBRE DEL DÍA del editor de rutina.
//
// Hasta la revisión en device del 21/10 renombrar era un modo aparte (lápiz →
// campo → check). Ahora es un campo más del formulario, siempre visible, con la
// decoración del campo NOMBRE de la rutina; guarda en cada tecla y al perder el
// foco normaliza. Vacío (o sólo espacios) vuelve a «Día N» (decisión 2A).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/presentation/widgets/day_tab_bar.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/analytics/analytics_service.dart';
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
import 'package:treino/features/workout/presentation/routine_editor_mode.dart';
import 'package:treino/features/workout/presentation/routine_editor_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../../fixtures/exercises.dart';
import '../../../helpers/fake_analytics_service.dart';

class _MockRoutineRepository extends Mock implements RoutineRepository {}

Future<void> _pumpEditor(
  WidgetTester tester, {
  required RoutineEditorMode mode,
  required List<Override> overrides,
}) async {
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

List<Override> _overrides({String uid = 'athlete-1'}) {
  final mockRepo = _MockRoutineRepository();
  return [
    currentUidProvider.overrideWithValue(uid),
    routineRepositoryProvider.overrideWithValue(mockRepo),
    exercisesProvider.overrideWith((ref) async => kExerciseSeed),
    customExercisesForTrainerStreamProvider(uid).overrideWith(
      (ref) => Stream<List<CustomExercise>>.value(const <CustomExercise>[]),
    ),
    userCreatedRoutinesProvider(uid)
        .overrideWith((ref) => Stream<List<Routine>>.value(const [])),
    analyticsServiceProvider.overrideWithValue(FakeAnalyticsService()),
  ];
}

const _dayFieldKey = Key('day_name_field');

/// Nombre del día, leído de la PESTAÑA.
///
/// Se lee del widget y no con `find.text` porque la pestaña trunca a 15
/// caracteres para mostrar: `labels` tiene el nombre entero.
String _nombreEnPestana(WidgetTester tester) =>
    tester.widget<DayTabBar>(find.byType(DayTabBar)).labels.first;

TextField _campoDelDia(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(_dayFieldKey));

Future<void> _soltarFoco(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

void main() {
  group('Campo NOMBRE DEL DÍA', () {
    testWidgets(
      'está siempre visible, con su label y el nombre actual, sin lápiz ni '
      'check',
      (tester) async {
        await _pumpEditor(
          tester,
          mode: const SelfCreating(),
          overrides: _overrides(),
        );

        expect(find.text('NOMBRE DEL DÍA'), findsOneWidget);
        expect(_campoDelDia(tester).controller!.text, 'Día 1');
        // El modo aparte se fue entero: ni el lápiz ni el check existen.
        expect(find.byKey(const Key('day_name_edit_button_1')), findsNothing);
        expect(find.byKey(const Key('day_name_commit_button_1')), findsNothing);
      },
    );

    testWidgets(
      'usa la misma decoración y tipografía que el campo NOMBRE de la rutina',
      (tester) async {
        await _pumpEditor(
          tester,
          mode: const SelfCreating(),
          overrides: _overrides(),
        );

        final nombre = tester.widget<TextField>(
          find.byKey(const Key('editor_name_field')),
        );
        final dia = _campoDelDia(tester);

        expect(dia.style, nombre.style);
        expect(dia.decoration!.fillColor, nombre.decoration!.fillColor);
        expect(dia.decoration!.filled, nombre.decoration!.filled);
        expect(
          dia.decoration!.contentPadding,
          nombre.decoration!.contentPadding,
        );
        expect(dia.decoration!.hintStyle, nombre.decoration!.hintStyle);
        expect(dia.decoration!.enabledBorder, nombre.decoration!.enabledBorder);
        expect(dia.decoration!.focusedBorder, nombre.decoration!.focusedBorder);
        // Y miden lo mismo en pantalla.
        expect(
          tester.getSize(find.byKey(_dayFieldKey)).height,
          tester.getSize(find.byKey(const Key('editor_name_field'))).height,
        );
        expect(
          tester.getSize(find.byKey(_dayFieldKey)).height,
          greaterThanOrEqualTo(44),
        );
      },
    );

    testWidgets(
      'guarda en cada tecla: la pestaña cambia mientras escribís',
      (tester) async {
        await _pumpEditor(
          tester,
          mode: const SelfCreating(),
          overrides: _overrides(),
        );

        await tester.enterText(find.byKey(_dayFieldKey), 'Pecho');
        await tester.pumpAndSettle();

        expect(_nombreEnPestana(tester), 'Pecho');
      },
    );

    testWidgets(
      'vaciar el campo mientras escribís no te repone «Día 1» encima',
      (tester) async {
        await _pumpEditor(
          tester,
          mode: const SelfCreating(),
          overrides: _overrides(),
        );

        await tester.enterText(find.byKey(_dayFieldKey), '');
        await tester.pumpAndSettle();
        // El padre ya guardó el default, pero el campo con foco sigue vacío.
        expect(_campoDelDia(tester).controller!.text, '');

        await tester.enterText(find.byKey(_dayFieldKey), 'Piernas');
        await tester.pumpAndSettle();
        expect(_nombreEnPestana(tester), 'Piernas');
        expect(_campoDelDia(tester).controller!.text, 'Piernas');
      },
    );

    testWidgets(
      '2A: vacío al soltar el foco vuelve a «Día 1» en la pestaña y en el '
      'campo',
      (tester) async {
        await _pumpEditor(
          tester,
          mode: const SelfCreating(),
          overrides: _overrides(),
        );

        await tester.enterText(find.byKey(_dayFieldKey), 'PUSH');
        await tester.pumpAndSettle();
        expect(_nombreEnPestana(tester), 'PUSH');

        await tester.enterText(find.byKey(_dayFieldKey), '');
        await _soltarFoco(tester);

        expect(_nombreEnPestana(tester), 'Día 1');
        expect(_campoDelDia(tester).controller!.text, 'Día 1');
      },
    );

    testWidgets(
      '2A: sólo espacios cuenta como vacío, y los bordes se recortan',
      (tester) async {
        await _pumpEditor(
          tester,
          mode: const SelfCreating(),
          overrides: _overrides(),
        );

        await tester.enterText(find.byKey(_dayFieldKey), '   ');
        await _soltarFoco(tester);
        expect(_nombreEnPestana(tester), 'Día 1');

        await tester.enterText(find.byKey(_dayFieldKey), '  Espalda  ');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(_nombreEnPestana(tester), 'Espalda');
        expect(_campoDelDia(tester).controller!.text, 'Espalda');
      },
    );

    testWidgets(
      'un nombre largo no desborda en una pantalla chica',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await _pumpEditor(
          tester,
          mode: const SelfCreating(),
          overrides: _overrides(),
        );

        await tester.enterText(
          find.byKey(_dayFieldKey),
          'Tren superior con énfasis en espalda y bíceps',
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );
  });
}
