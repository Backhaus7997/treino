// Unir dos ejercicios YA cargados en una superserie (#908).
//
// Hasta acá no había forma de hacerlo: el botón `+ Superserie` abre el picker y
// agrega ejercicios NUEVOS agrupados, así que el caso normal —cargás dos por
// separado y después decidís hacerlos juntos— obligaba a borrarlos y volver a
// agregarlos desde el picker.
//
// El botón del día NO cambia: esto se suma en el ⋮ de cada ejercicio, que es
// donde vive el resto de sus acciones.
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
import 'package:treino/features/workout/presentation/widgets/exercise_card.dart';
import 'package:treino/features/workout/presentation/widgets/superset_block.dart';
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

/// Agrega varios ejercicios de una: el picker es multi-select, y abrirlo una
/// vez por ejercicio hace crecer la lista entre medio hasta que el botón de
/// agregar se va de pantalla.
Future<void> _agregarVarios(WidgetTester tester, List<String> nombres) async {
  await desplazarHastaAgregarEjercicio(tester);
  await tester.tap(find.text('Agregar ejercicio'));
  await tester.pumpAndSettle();
  for (final n in nombres) {
    await tester.tap(find.text(n).first);
    await tester.pumpAndSettle();
  }
  final confirmar = find.byWidgetPredicate(
    (w) =>
        w is Text &&
        (w.data ?? '').startsWith('Agregar ') &&
        w.data != 'Agregar ejercicio',
  );
  await tester.tap(confirmar.last);
  await tester.pumpAndSettle();
}

Future<void> _agregar(WidgetTester tester, String nombre) async {
  await desplazarHastaAgregarEjercicio(tester);
  await tester.tap(find.text('Agregar ejercicio'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(nombre).first);
  await tester.pumpAndSettle();
  // El contador del picker NO es siempre "Agregar 1": desde el fix del botón
  // mudo, el picker abre con los ejercicios que el día ya tiene pre-marcados,
  // así que al sumar el segundo dice "Agregar 2".
  final confirmar = find.byWidgetPredicate(
    (w) =>
        w is Text &&
        (w.data ?? '').startsWith('Agregar ') &&
        w.data != 'Agregar ejercicio',
  );
  await tester.tap(confirmar.last);
  await tester.pumpAndSettle();
}

/// Abre el ⋮ del ejercicio en la posición [i].
///
/// `scrollUntilVisible` y no `ensureVisible`: el editor es un `ListView` y el
/// botón no está CONSTRUIDO hasta que se scrollea hasta él.
Future<void> _abrirMenu(WidgetTester tester, int i) async {
  final boton = find.byKey(Key('slot_menu_button_$i'));
  if (boton.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      boton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(boton);
  await tester.pumpAndSettle();
  await tester.tap(boton);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('unir con el de arriba agrupa dos ejercicios ya cargados',
      (tester) async {
    await _pumpEditor(tester);
    await _agregar(tester, 'Press de Banca');
    await _agregar(tester, 'Press Militar');

    expect(find.byType(ExerciseCard), findsNWidgets(2));
    expect(find.byType(SupersetBlock), findsNothing);

    await _abrirMenu(tester, 1);
    await tester.tap(find.text('Unir con el de arriba'));
    await tester.pumpAndSettle();

    expect(find.byType(SupersetBlock), findsOneWidget,
        reason: 'el caso que no tenía solución: dos ejercicios ya cargados '
            'que se quieren juntar, sin borrarlos');
    expect(find.text('A1'), findsOneWidget);
    expect(find.text('A2'), findsOneWidget);
  });

  testWidgets('el primero no tiene con quién unirse: la acción está apagada',
      (tester) async {
    await _pumpEditor(tester);
    await _agregar(tester, 'Press de Banca');
    await _agregar(tester, 'Press Militar');

    await _abrirMenu(tester, 0);
    final item = find.byKey(
      const Key('exercise_sheet_action__SlotAction.mergeWithPrevious'),
    );
    expect(item, findsOneWidget);
    expect(tester.widget<InkWell>(item).onTap, isNull,
        reason: 'no hay nada arriba del primero');
  });

  testWidgets('sacar de la superserie deshace el grupo', (tester) async {
    await _pumpEditor(tester);
    await _agregar(tester, 'Press de Banca');
    await _agregar(tester, 'Press Militar');
    await _abrirMenu(tester, 1);
    await tester.tap(find.text('Unir con el de arriba'));
    await tester.pumpAndSettle();
    expect(find.byType(SupersetBlock), findsOneWidget);

    await _abrirMenu(tester, 1);
    await tester.tap(find.text('Sacar de la superserie'));
    await tester.pumpAndSettle();

    expect(find.byType(SupersetBlock), findsNothing,
        reason: 'el grupo quedaba con UN miembro: un grupo de uno no es una '
            'superserie, y buildRoutineSlot lo descartaría igual al guardar');
    expect(find.byType(ExerciseCard), findsNWidgets(2),
        reason: 'los dos ejercicios siguen ahí, sueltos');
  });

  testWidgets('un tercero se suma al grupo existente', (tester) async {
    await _pumpEditor(tester);
    await _agregarVarios(
        tester, ['Press de Banca', 'Press Militar', 'Aperturas con Cable']);

    await _abrirMenu(tester, 1);
    await tester.tap(find.text('Unir con el de arriba'));
    await tester.pumpAndSettle();
    await _abrirMenu(tester, 2);
    await tester.tap(find.text('Unir con el de arriba'));
    await tester.pumpAndSettle();

    expect(find.byType(SupersetBlock), findsOneWidget,
        reason: 'UN bloque de tres, no dos bloques: el tercero se suma al '
            'grupo del anterior en vez de estrenar uno');
    expect(find.text('A3'), findsOneWidget);
  });

  testWidgets('un ejercicio suelto no ofrece "sacar de la superserie"',
      (tester) async {
    await _pumpEditor(tester);
    await _agregar(tester, 'Press de Banca');

    await _abrirMenu(tester, 0);
    expect(find.text('Sacar de la superserie'), findsNothing);
    expect(find.text('Unir con el de arriba'), findsOneWidget);
  });
}
