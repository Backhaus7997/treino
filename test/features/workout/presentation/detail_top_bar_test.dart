import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_collapsing_top_bar.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/presentation/exercise_detail_screen.dart';
import 'package:treino/features/workout/presentation/routine_detail_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

/// #1559: en el detalle de rutina y de ejercicio la flecha (y editar) flotan
/// sin fondo en offset 0, el contenido arranca DEBAJO (medido con los rects
/// reales, con el texto agrandado y un notch simulado) y, al scrollear, aparece
/// la barra con el título chico.

const _uid = 'athlete-1';
const _safeTop = 47.0;
const _surface = Key('treino-top-bar-surface');
const _smallTitle = Key('treino-top-bar-title');
const _back = Key('treino-top-bar-back');

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  required List<Override> overrides,
  double textScale = 1,
}) async {
  // A 2× de texto hay filas del CUERPO que ya desbordan a 390 px (otra deuda),
  // y acá sólo se mide el encabezado: ancho y alto de sobra.
  tester.view.physicalSize =
      textScale > 1 ? const Size(800, 2400) : const Size(390, 700);
  tester.view.devicePixelRatio = 1.0;
  tester.view.padding = const FakeViewPadding(top: _safeTop);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [currentUidProvider.overrideWithValue(_uid), ...overrides],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        // Como el shell: el SafeArea consume el notch antes de la pantalla.
        home: Scaffold(body: SafeArea(child: screen)),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

RoutineSlot _slot(int i) => RoutineSlot(
      exerciseId: 'ex-$i',
      exerciseName: 'Ejercicio $i',
      muscleGroup: 'chest',
      targetSets: 3,
      targetRepsMin: 8,
      targetRepsMax: 12,
      restSeconds: 90,
    );

// Rutina propia sin foto ni coach: encabezado compacto con la menor cantidad
// de pills, el botón editar a la derecha y contenido de sobra para scrollear.
final _ownRoutine = Routine(
  id: 'own-1',
  name: 'Mi rutina',
  level: ExperienceLevel.beginner,
  source: RoutineSource.userCreated,
  createdBy: _uid,
  days: [
    RoutineDay(
      dayNumber: 1,
      name: 'Título del día',
      slots: [for (var i = 0; i < 12; i++) _slot(i)],
    ),
  ],
);

/// La `Column` del encabezado que contiene el título: su borde superior es
/// donde arranca el contenido que los botones no pueden pisar.
Finder _headerContent(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(Column)).first;

Future<void> _scroll(WidgetTester tester, double dy) async {
  await tester.drag(find.byType(CustomScrollView), Offset(0, dy));
  await tester.pumpAndSettle();
}

void main() {
  group('routine_detail', () {
    final overrides = [
      routineByIdStreamProvider('own-1')
          .overrideWith((ref) => Stream.value(_ownRoutine)),
    ];

    testWidgets('offset 0: sin fondo y el título queda debajo de los botones',
        (tester) async {
      await _pump(
        tester,
        const RoutineDetailScreen(routineId: 'own-1'),
        overrides: overrides,
        textScale: 2,
      );

      expect(find.byKey(_surface), findsNothing);
      expect(find.byKey(_smallTitle), findsNothing);

      final contentTop = tester.getRect(_headerContent('TÍTULO DEL DÍA')).top;
      final buttons = [
        tester.getRect(find.byKey(_back)),
        tester.getRect(find.byKey(const Key('routine_edit'))),
      ];
      for (final rect in buttons) {
        expect(rect.size.shortestSide, greaterThanOrEqualTo(44));
        expect(rect.top, _safeTop + TreinoTopBarMetrics.topInset);
        expect(
          contentTop,
          greaterThanOrEqualTo(rect.bottom + TreinoTopBarMetrics.clearance),
          reason: 'el botón $rect pisa el contenido que arranca en $contentTop',
        );
      }
    });

    testWidgets('al scrollear aparece la barra con el título; al volver, no',
        (tester) async {
      await _pump(
        tester,
        const RoutineDetailScreen(routineId: 'own-1'),
        overrides: overrides,
      );

      await _scroll(tester, -400);
      expect(
        tester.widget<Opacity>(find.byKey(_surface)).opacity,
        1,
      );
      expect(
        find.descendant(
          of: find.byKey(_smallTitle),
          matching: find.text('TÍTULO DEL DÍA'),
        ),
        findsOneWidget,
      );

      await _scroll(tester, 800);
      expect(find.byKey(_surface), findsNothing);
      expect(find.byKey(_smallTitle), findsNothing);
    });
  });

  group('exercise_detail', () {
    final overrides = [
      // `custom` → encabezado compacto, sin foto.
      exerciseByIdProvider('mi-ejercicio').overrideWith(
        (ref) async => const Exercise(
          id: 'mi-ejercicio',
          name: 'Mi ejercicio',
          muscleGroup: 'Pecho',
          category: 'custom',
        ),
      ),
    ];

    testWidgets('offset 0: sin fondo y el título queda debajo de la flecha',
        (tester) async {
      await _pump(
        tester,
        const ExerciseDetailScreen(exerciseId: 'mi-ejercicio'),
        overrides: overrides,
        textScale: 2,
      );

      expect(find.byKey(_surface), findsNothing);

      final back = tester.getRect(find.byKey(_back));
      final contentTop = tester.getRect(_headerContent('MI EJERCICIO')).top;
      expect(back.size.shortestSide, greaterThanOrEqualTo(44));
      expect(
        contentTop,
        greaterThanOrEqualTo(back.bottom + TreinoTopBarMetrics.clearance),
        reason: 'la flecha $back pisa el contenido que arranca en $contentTop',
      );
    });

    testWidgets('al scrollear aparece la barra con el título', (tester) async {
      await _pump(
        tester,
        const ExerciseDetailScreen(exerciseId: 'mi-ejercicio'),
        overrides: overrides,
      );

      await _scroll(tester, -400);

      expect(find.byKey(_surface), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(_smallTitle),
          matching: find.text('MI EJERCICIO'),
        ),
        findsOneWidget,
      );
    });
  });
}
