// La entrada rápida cableada con el editor real (#870).
//
// Lo que importa afirmar acá no es el parser —eso vive en
// `quick_entry_parser_test.dart`, sin widgets— sino que el ejercicio que entra
// por el atajo sea INDISTINGUIBLE de uno agregado por el picker, y que el
// picker siga estando.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:treino/features/workout/presentation/routine_editor_mode.dart';
import 'package:treino/features/workout/presentation/routine_editor_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

import 'package:treino/features/workout/presentation/widgets/exercise_card.dart';

import '../../../fixtures/exercises.dart';
import '../../../fixtures/routine_editor_ui.dart';
import '../../../helpers/fake_analytics_service.dart';

class _MockRoutineRepository extends Mock implements RoutineRepository {}

Future<void> _pumpEditor(WidgetTester tester) async {
  usarViewportAlto(tester);
  const uid = 'user-1';
  final router = GoRouter(
    initialLocation: '/workout/editor',
    routes: [
      GoRoute(
        path: '/workout/editor',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: RoutineEditorScreen(mode: SelfCreating()),
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
      overrides: [
        currentUidProvider.overrideWithValue(uid),
        routineRepositoryProvider.overrideWithValue(_MockRoutineRepository()),
        exercisesProvider.overrideWith((ref) async => kExerciseSeed),
        customExercisesForTrainerStreamProvider(uid).overrideWith(
          (ref) => Stream<List<CustomExercise>>.value(const <CustomExercise>[]),
        ),
        analyticsServiceProvider.overrideWithValue(FakeAnalyticsService()),
        userCreatedRoutinesProvider(uid).overrideWith(
          (ref) => Stream.value(const []),
        ),
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
  await tester.pumpAndSettle();
}

void main() {
  Future<void> abrirRapido(WidgetTester tester) async {
    final toggle = find.byKey(const Key('quick_entry_toggle'));
    await desplazarHasta(tester, toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
  }

  /// El flujo completo: buscar, ELEGIR (que sólo autocompleta), escribir la
  /// prescripción, y recién ahí confirmar.
  Future<void> elegirYAgregar(
    WidgetTester tester, {
    required String busqueda,
    required String prescripcion,
  }) async {
    await tester.enterText(
        find.byKey(const Key('quick_entry_field')), busqueda);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quick_entry_result_0')));
    await tester.pumpAndSettle();

    final campo =
        tester.widget<TextField>(find.byKey(const Key('quick_entry_field')));
    await tester.enterText(
      find.byKey(const Key('quick_entry_field')),
      '${campo.controller!.text}$prescripcion',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quick_entry_confirm')));
    await tester.pumpAndSettle();
  }

  testWidgets('elegir un resultado autocompleta, NO agrega', (tester) async {
    // El hallazgo de la revisión del 31/08: el tap agregaba el ejercicio en el
    // acto con lo que hubiera escrito. Como el nombre se escribe primero, el
    // atajo se cerraba justo antes de poder decir "4x10 55".
    await _pumpEditor(tester);
    await abrirRapido(tester);

    await tester.enterText(find.byKey(const Key('quick_entry_field')), 'banca');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quick_entry_result_0')));
    await tester.pumpAndSettle();

    // El panel sigue abierto, con el nombre puesto y listo para seguir.
    expect(find.byKey(const Key('quick_entry_field')), findsOneWidget);
    final campo =
        tester.widget<TextField>(find.byKey(const Key('quick_entry_field')));
    expect(campo.controller!.text, startsWith('Press de Banca'));
    expect(campo.controller!.text, endsWith(' '),
        reason: 'con el espacio puesto, para escribir la prescripción');
    expect(find.byKey(const Key('quick_entry_confirm')), findsOneWidget);
    // Y el ejercicio NO entró todavía.
    expect(find.byType(ExerciseCard), findsNothing);
  });

  testWidgets('el flujo completo agrega con la prescripción tipeada',
      (tester) async {
    await _pumpEditor(tester);
    await abrirRapido(tester);
    await elegirYAgregar(tester, busqueda: 'banca', prescripcion: '3x8 60');

    await expandirEjercicios(tester);
    expect(celdasConHint('reps'), findsNWidgets(3));
    expect(find.text('8'), findsWidgets);
    expect(find.text('60'), findsWidgets);
  });

  testWidgets('una pirámide deja cada set con SUS reps', (tester) async {
    await _pumpEditor(tester);
    await abrirRapido(tester);
    await elegirYAgregar(tester,
        busqueda: 'banca', prescripcion: '4x10, 8, 6, 4');

    await expandirEjercicios(tester);
    expect(celdasConHint('reps'), findsNWidgets(4));
    for (final valor in ['10', '8', '6', '4']) {
      expect(find.text(valor), findsWidgets, reason: 'falta la rep $valor');
    }
  });

  testWidgets('una descarga deja cada set con SU peso', (tester) async {
    await _pumpEditor(tester);
    await abrirRapido(tester);
    await elegirYAgregar(tester,
        busqueda: 'banca', prescripcion: '4x10 55, 45, 35, 25');

    await expandirEjercicios(tester);
    expect(celdasConHint('kg'), findsNWidgets(4));
    for (final valor in ['55', '45', '35', '25']) {
      expect(find.text(valor), findsWidgets, reason: 'falta el peso $valor');
    }
  });

  testWidgets('sin números entra con 3 sets vacíos', (tester) async {
    await _pumpEditor(tester);
    await abrirRapido(tester);
    await elegirYAgregar(tester, busqueda: 'banca', prescripcion: '');

    await expandirEjercicios(tester);
    expect(celdasConHint('reps'), findsNWidgets(3));
    final primera = tester.widget<TextField>(celdasConHint('reps').at(0));
    expect(primera.controller!.text, '',
        reason: 'los sets entran vacíos y se completan después, igual que los '
            'de un ejercicio agregado por el picker');
  });

  testWidgets('el panel se cierra al confirmar', (tester) async {
    await _pumpEditor(tester);
    await abrirRapido(tester);
    await elegirYAgregar(tester, busqueda: 'banca', prescripcion: '3x8');

    expect(find.byKey(const Key('quick_entry_field')), findsNothing);
  });

  testWidgets('borrar el nombre elegido devuelve la lista', (tester) async {
    await _pumpEditor(tester);
    await abrirRapido(tester);
    await tester.enterText(find.byKey(const Key('quick_entry_field')), 'banca');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quick_entry_result_0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quick_entry_results')), findsNothing);

    // Se equivocó de ejercicio: vuelve a buscar sin cerrar el panel.
    await tester.enterText(find.byKey(const Key('quick_entry_field')), 'press');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('quick_entry_results')), findsOneWidget,
        reason: 'soltar el nombre tiene que devolver la búsqueda');
    expect(find.byKey(const Key('quick_entry_confirm')), findsNothing);
  });

  testWidgets('no ofrece un ejercicio que ya está en el día', (tester) async {
    await _pumpEditor(tester);
    await abrirRapido(tester);
    await elegirYAgregar(tester, busqueda: 'banca', prescripcion: '3x8');

    await abrirRapido(tester);
    await tester.enterText(
        find.byKey(const Key('quick_entry_field')), 'Press de Banca');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('quick_entry_result_0')), findsNothing,
        reason: 'un ejercicio por día es invariante del dominio '
            '(QA-WKT-004): ofrecerlo para que el tap no haga nada es peor '
            'que no ofrecerlo');
  });

  testWidgets('busca por tokens: "press banca" llega a "Press de Banca"',
      (tester) async {
    await _pumpEditor(tester);
    await abrirRapido(tester);
    await tester.enterText(
        find.byKey(const Key('quick_entry_field')), 'press banca');
    await tester.pumpAndSettle();

    expect(find.text('Press de Banca'), findsWidgets);
  });

  testWidgets('el picker completo sigue estando, sin cambios', (tester) async {
    await _pumpEditor(tester);
    await desplazarHastaAgregarEjercicio(tester);
    expect(find.text('Agregar ejercicio'), findsWidgets,
        reason: 'la entrada rápida NUNCA es el único camino');

    await tester.tap(find.text('Agregar ejercicio'));
    await tester.pumpAndSettle();
    expect(find.text('Press de Banca'), findsWidgets);
  });
}
