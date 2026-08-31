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

  testWidgets('el atajo agrega el ejercicio con sets, reps y peso cargados',
      (tester) async {
    await _pumpEditor(tester);
    await abrirRapido(tester);

    await tester.enterText(
        find.byKey(const Key('quick_entry_field')), 'banca 3x8 60');
    await tester.pumpAndSettle();

    expect(find.text('Press de Banca'), findsWidgets,
        reason: 'el catálogo real responde a "banca"');
    await tester.tap(find.byKey(const Key('quick_entry_result_0')));
    await tester.pumpAndSettle();

    // El ejercicio quedó en el día, con su prescripción ya cargada.
    await expandirEjercicios(tester);
    expect(celdasConHint('reps'), findsNWidgets(3),
        reason: '3x8 tiene que dejar TRES filas de set');
    expect(find.text('8'), findsWidgets);
    expect(find.text('60'), findsWidgets);
  });

  testWidgets('sin números entra con 3 sets vacíos', (tester) async {
    await _pumpEditor(tester);
    await abrirRapido(tester);

    await tester.enterText(find.byKey(const Key('quick_entry_field')), 'banca');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quick_entry_result_0')));
    await tester.pumpAndSettle();

    await expandirEjercicios(tester);
    expect(celdasConHint('reps'), findsNWidgets(3));
    final primera = tester.widget<TextField>(celdasConHint('reps').at(0));
    expect(primera.controller!.text, '',
        reason: 'los sets entran vacíos y se completan después, igual que los '
            'de un ejercicio agregado por el picker');
  });

  testWidgets('el panel se cierra al elegir', (tester) async {
    await _pumpEditor(tester);
    await abrirRapido(tester);
    expect(find.byKey(const Key('quick_entry_field')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('quick_entry_field')), 'banca');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quick_entry_result_0')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('quick_entry_field')), findsNothing,
        reason: 'el atajo termina cuando el ejercicio entró');
  });

  testWidgets('no ofrece un ejercicio que ya está en el día', (tester) async {
    await _pumpEditor(tester);
    await abrirRapido(tester);
    await tester.enterText(find.byKey(const Key('quick_entry_field')), 'banca');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quick_entry_result_0')));
    await tester.pumpAndSettle();

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
    // Un `contains` no sirve: el `de` del medio lo rompe. La búsqueda usa el
    // mismo matcher que el picker (ADR-BIBW-01) — dos búsquedas que difieren
    // en la misma pantalla es peor que una sola imperfecta.
    await _pumpEditor(tester);
    await abrirRapido(tester);
    await tester.enterText(
        find.byKey(const Key('quick_entry_field')), 'press banca 4x10');
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

  testWidgets('cerrar el panel limpia lo tipeado', (tester) async {
    await _pumpEditor(tester);
    await abrirRapido(tester);
    await tester.enterText(
        find.byKey(const Key('quick_entry_field')), 'banca 4x10');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('quick_entry_toggle')));
    await tester.pumpAndSettle();
    await abrirRapido(tester);

    final campo =
        tester.widget<TextField>(find.byKey(const Key('quick_entry_field')));
    expect(campo.controller!.text, '',
        reason: 'volver a abrir el atajo empieza de cero, no retoma una '
            'búsqueda vieja');
  });
}
