// La línea de ayuda del ⋮ (E2E 1.3.0): el texto escribía el glifo ⋮ y la
// Barlow no lo tiene, así que en pantalla se leía «El : de cada ejercicio…».
// El ícono tiene que ir DIBUJADO, el mismo del menú, y el texto no puede
// volver a depender del glifo.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/analytics/analytics_service.dart';
import 'package:treino/core/widgets/treino_icon.dart';
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

/// Agrega varios ejercicios de una: el picker es multi-select, y abrirlo una
/// vez por ejercicio hace crecer la lista entre medio hasta que el botón de
/// agregar se va de pantalla.
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

void main() {
  testWidgets('la ayuda del menú dibuja el ícono real, no el glifo',
      (tester) async {
    await _pumpEditor(tester);
    await _agregar(tester, 'Press de Banca');

    final hint = find.byKey(const Key('slot_menu_hint'));
    expect(hint, findsOneWidget);
    expect(
      find.descendant(of: hint, matching: find.byIcon(TreinoIcon.dotsThree)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: hint,
        matching: find.text(
          'Menú de cada ejercicio: cambiarlo, copiar sets o moverlo.',
        ),
      ),
      findsOneWidget,
    );
  });

  test('ningún idioma escribe el glifo ⋮ en la ayuda', () {
    for (final arb in Directory('lib/l10n')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.arb'))) {
      final json = jsonDecode(arb.readAsStringSync()) as Map<String, dynamic>;
      final value = json['routineEditorSlotMenuHint'];
      if (value == null) continue;
      expect(value, isNot(contains('⋮')), reason: arb.path);
    }
  });
}
