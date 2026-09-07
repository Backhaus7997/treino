// Widget smoke tests for BibliotecaWebScreen.
// REQ-BIBW-01, REQ-BIBW-02.
// SCENARIO-BIBW-02a.
// T-BIBW-005

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';
import 'package:treino/features/coach_hub/presentation/sections/biblioteca/biblioteca_web_screen.dart';
import 'package:treino/features/coach_hub/presentation/sections/biblioteca/widgets/biblioteca_filter_chips.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/application/custom_exercise_providers.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/domain/custom_exercise.dart';
import 'package:treino/features/workout/domain/equipment_type.dart';
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_source.dart';

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _kTrainerId = 'trainer-uid-screen-test';

const _bench = Exercise(
  id: 'bench-press',
  name: 'Press de Banca',
  muscleGroup: 'chest',
  category: 'compound',
  equipment: EquipmentType.barra,
  defaultRestSeconds: 90,
);

const _curl = Exercise(
  id: 'biceps-curl',
  name: 'Curl de Bíceps',
  muscleGroup: 'biceps',
  category: 'isolation',
);

final _customEx = CustomExercise(
  id: 'custom-squat',
  ownerId: _kTrainerId,
  name: 'Sentadilla Personalizada',
  muscleGroup: 'quads',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

Routine _makeTemplate(String id, String name) {
  return Routine(
    id: id,
    name: name,
    level: ExperienceLevel.intermediate,
    days: const [
      RoutineDay(dayNumber: 1, name: 'Día 1', slots: []),
    ],
    numWeeks: 8,
    source: RoutineSource.trainerTemplate,
  );
}

final _templateA = _makeTemplate('tpl-a', 'Fuerza Total');
final _templateB = _makeTemplate('tpl-b', 'Hipertrofia Máxima');

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Wraps BibliotecaWebScreen in a minimal shell that mimics what
/// CoachHubScaffold provides (Scaffold + Material theme). The screen itself
/// must NOT render its own Scaffold/SafeArea.
Widget _wrap() {
  return ProviderScope(
    overrides: [
      currentUidProvider.overrideWithValue(_kTrainerId),
      exercisesProvider.overrideWith(
        // Never completes → stays in AsyncLoading; no Timer leak (no
        // Future.delayed — uses Completer as per the gotcha in PR1).
        (ref) => Completer<List<Exercise>>().future,
      ),
      customExercisesForTrainerStreamProvider(_kTrainerId).overrideWith(
        (ref) => Stream.value(<CustomExercise>[]),
      ),
      trainerTemplatesStreamProvider(_kTrainerId).overrideWith(
        (ref) => Stream.value(<Routine>[]),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      // Scaffold provided by the shell — BibliotecaWebScreen must NOT add one.
      home: const Scaffold(
        body: BibliotecaWebScreen(),
      ),
    ),
  );
}

/// Wraps BibliotecaWebScreen with resolved (non-loading) providers so the
/// counts settle to real values — 2 catalog + 1 custom = 3 ejercicios,
/// 2 templates.
Widget _wrapWithData({ThemeData? theme}) {
  return ProviderScope(
    overrides: [
      currentUidProvider.overrideWithValue(_kTrainerId),
      exercisesProvider.overrideWith((ref) async => [_bench, _curl]),
      customExercisesForTrainerStreamProvider(_kTrainerId).overrideWith(
        (ref) => Stream.value(<CustomExercise>[_customEx]),
      ),
      trainerTemplatesStreamProvider(_kTrainerId).overrideWith(
        (ref) => Stream.value(<Routine>[_templateA, _templateB]),
      ),
    ],
    child: MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: const Scaffold(
        body: BibliotecaWebScreen(),
      ),
    ),
  );
}

void _setSurfaceSize(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Finder _inside(Key hostKey, Finder matching) => find.descendant(
      of: find.byKey(hostKey),
      matching: matching,
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // AppTheme.* toca GoogleFonts. Si algun ThemeData llegara a construirse
  // fuera del cuerpo de un testWidgets, sin esto revienta con "Binding has
  // not yet been initialized" antes de la primera asercion.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('BibliotecaWebScreen — contract', () {
    testWidgets('mounts successfully and has 2 tabs — SCENARIO-BIBW-02a',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap());
      await tester.pump(); // single frame

      // TabBar with 2 tabs must exist
      expect(find.byType(TabBar), findsOneWidget);

      // Both tab labels visible (labels include counts: "Ejercicios · N")
      expect(find.textContaining('Ejercicios'), findsWidgets);
      expect(find.textContaining('Templates Rutinas'), findsOneWidget);
    });

    testWidgets('does not render a Scaffold inside itself — SCENARIO-BIBW-02a',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap());
      await tester.pump();

      // The shell provides exactly 1 Scaffold. BibliotecaWebScreen must not
      // add another one inside itself.
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('does not render SafeArea — SCENARIO-BIBW-02a', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap());
      await tester.pump();

      expect(find.byType(SafeArea), findsNothing);
    });

    testWidgets('BIBLIOTECA header text is present', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap());
      await tester.pump();

      expect(find.text('BIBLIOTECA'), findsOneWidget); // i18n
    });

    testWidgets('renders TreinoSectionHeader for the title', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap());
      await tester.pump();

      expect(find.byType(TreinoSectionHeader), findsOneWidget);
    });

    testWidgets(
        'header está envuelto en TreinoFadeSlideIn con stagger explícito '
        '(índice 0) — ADR-B7-03', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap());
      await tester.pump();

      final fadeSlideInAncestor = tester.widget<TreinoFadeSlideIn>(
        find.ancestor(
          of: find.byType(TreinoSectionHeader),
          matching: find.byType(TreinoFadeSlideIn),
        ),
      );

      expect(fadeSlideInAncestor.delay, AppMotion.stagger(0));
    });

    testWidgets('shows honest subtitle with real exercise + template counts',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrapWithData());
      await tester.pumpAndSettle();

      // 2 catalog + 1 custom = 3 ejercicios · 2 templates.
      expect(find.textContaining('3 ejercicios'), findsOneWidget);
      expect(find.textContaining('2 templates'), findsOneWidget);
    });

    testWidgets('still has exactly 2 tabs with no own Scaffold/SafeArea',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap());
      await tester.pump();

      expect(find.byType(Tab), findsNWidgets(2));
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(SafeArea), findsNothing);
    });
  });

  group('Biblioteca Ejercicios — layout responsivo', () {
    testWidgets(
        'tramo A muestra filtros, grilla de 4 columnas y detalle lateral',
        (tester) async {
      _setSurfaceSize(tester, 1600);
      await tester.pumpWidget(_wrapWithData());
      await tester.pumpAndSettle();

      const filtersKey = Key('biblioteca_filter_column');
      const gridKey = Key('biblioteca_exercise_grid');
      const panelKey = Key('biblioteca_detail_panel');

      expect(find.byKey(filtersKey), findsOneWidget);
      expect(find.byKey(gridKey), findsOneWidget);
      final grid = tester.widget<GridView>(find.byKey(gridKey));
      final delegate = grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 4);

      await tester.tap(_inside(gridKey, find.text('Press de Banca')));
      await tester.pumpAndSettle();

      expect(find.byKey(panelKey), findsOneWidget);
      expect(find.byType(TreinoDialog), findsNothing);
      expect(_inside(panelKey, find.text('Press de Banca')), findsOneWidget);
    });

    testWidgets(
        'tramo B mantiene filtros laterales y 4 columnas, pero abre modal',
        (tester) async {
      _setSurfaceSize(tester, 1400);
      await tester.pumpWidget(_wrapWithData());
      await tester.pumpAndSettle();

      const filtersKey = Key('biblioteca_filter_column');
      const gridKey = Key('biblioteca_exercise_grid');

      expect(find.byKey(filtersKey), findsOneWidget);
      final grid = tester.widget<GridView>(find.byKey(gridKey));
      final delegate = grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 4);

      await tester.tap(_inside(gridKey, find.text('Press de Banca')));
      await tester.pumpAndSettle();

      expect(find.byType(TreinoDialog), findsOneWidget);
      expect(find.byKey(const Key('biblioteca_detail_panel')), findsNothing);
    });

    testWidgets('tramo C conserva filtros arriba y abre modal sin panel',
        (tester) async {
      _setSurfaceSize(tester, 1100);
      await tester.pumpWidget(_wrapWithData());
      await tester.pumpAndSettle();

      expect(find.byType(BibliotecaFilterChips), findsOneWidget);
      expect(find.byKey(const Key('biblioteca_filter_column')), findsNothing);

      const gridKey = Key('biblioteca_exercise_grid');
      final grid = tester.widget<GridView>(find.byKey(gridKey));
      expect(grid.gridDelegate, isA<SliverGridDelegateWithMaxCrossAxisExtent>());

      await tester.tap(_inside(gridKey, find.text('Press de Banca')));
      await tester.pumpAndSettle();

      expect(find.byType(TreinoDialog), findsOneWidget);
      expect(find.byKey(const Key('biblioteca_detail_panel')), findsNothing);
    });

    testWidgets('tramo A en tema claro: el panel usa la paleta light',
        (tester) async {
      // El PF navega el Coach Hub en CLARO. Los dos wrappers de este archivo
      // hardcodeaban dark, asi que el rediseño entero venia sin cobertura del
      // tema que el usuario realmente mira.
      _setSurfaceSize(tester, 1600);
      await tester.pumpWidget(_wrapWithData(theme: AppTheme.light()));
      await tester.pumpAndSettle();

      const gridKey = Key('biblioteca_exercise_grid');
      const panelKey = Key('biblioteca_detail_panel');

      await tester.tap(_inside(gridKey, find.text('Press de Banca')));
      await tester.pumpAndSettle();

      expect(find.byKey(panelKey), findsOneWidget);

      final contenedor = tester.widget<Container>(
        find
            .descendant(of: find.byKey(panelKey), matching: find.byType(Container))
            .first,
      );
      final decoracion = contenedor.decoration! as BoxDecoration;
      expect(
        decoracion.color,
        AppPalette.mintMagentaLight.bgCard,
        reason: 'el panel tiene que tomar el color del tema activo, no uno '
            'fijo del tema oscuro',
      );
    });
  });
}
