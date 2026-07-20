// Widget tests for TemplatesTab, TemplateGridCard, and TemplateDetailDialog.
// REQ-BIBW-09, REQ-BIBW-10, REQ-BIBW-11.
// SCENARIO-BIBW-09a, SCENARIO-BIBW-09b, SCENARIO-BIBW-09c,
// SCENARIO-BIBW-10a, SCENARIO-BIBW-11b.
// T-BIBW-004

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/motion/treino_shimmer.dart';
import 'package:treino/features/coach_hub/presentation/sections/biblioteca/widgets/templates_tab.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/profile/domain/experience_level.dart';

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _kTrainerId = 'trainer-uid-templates-test';

Routine _makeRoutine(String id, String name, {int days = 3, int weeks = 8}) {
  return Routine(
    id: id,
    name: name,
    level: ExperienceLevel.intermediate,
    days: List.generate(
      days,
      (i) => RoutineDay(
        dayNumber: i + 1,
        name: 'Día ${i + 1}',
        slots: const [],
      ),
    ),
    numWeeks: weeks,
    source: RoutineSource.trainerTemplate,
  );
}

final _templateA = _makeRoutine('tpl-a', 'Fuerza Total', days: 3, weeks: 8);
final _templateB =
    _makeRoutine('tpl-b', 'Hipertrofia Máxima', days: 4, weeks: 12);
final _templateC = _makeRoutine('tpl-c', 'Full Body Básico', days: 5, weeks: 4);

// ── Helpers ───────────────────────────────────────────────────────────────────

Widget _wrap(
  Widget child, {
  List<Routine> templates = const [],
  bool loading = false,
  bool error = false,
}) {
  return ProviderScope(
    overrides: [
      currentUidProvider.overrideWithValue(_kTrainerId),
      trainerTemplatesStreamProvider(_kTrainerId).overrideWith((ref) {
        if (loading) return const Stream.empty();
        if (error) {
          return Stream.error(Exception('templates error'));
        }
        return Stream.value(templates);
      }),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: child),
    ),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('TemplatesTab — smoke renders', () {
    testWidgets('renders 3 template cards — SCENARIO-BIBW-09a', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(
          const TemplatesTab(),
          templates: [_templateA, _templateB, _templateC],
        ),
      );
      await tester.pumpAndSettle();

      // Names visible
      expect(find.text('Fuerza Total'), findsOneWidget);
      expect(find.text('Hipertrofia Máxima'), findsOneWidget);
      expect(find.text('Full Body Básico'), findsOneWidget);
    });

    testWidgets(
        'each card shows días/sem · semanas subtitle — SCENARIO-BIBW-09a',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(const TemplatesTab(), templates: [_templateA]),
      );
      await tester.pumpAndSettle();

      // templateA: 3 días, 8 semanas
      expect(find.textContaining('3 días/sem'), findsOneWidget);
      expect(find.textContaining('8 semanas'), findsOneWidget);
    });

    testWidgets('singulariza día/semana cuando el conteo es 1', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final single =
          _makeRoutine('tpl-single', 'Plan Corto', days: 1, weeks: 1);
      await tester.pumpWidget(
        _wrap(const TemplatesTab(), templates: [single]),
      );
      await tester.pumpAndSettle();

      // 1 día → "día" (no "días") · 1 semana → "semana" (no "semanas").
      expect(find.text('1 día/sem · 1 semana'), findsOneWidget);
    });

    testWidgets('each card shows level — SCENARIO-BIBW-09a', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(const TemplatesTab(), templates: [_templateA]),
      );
      await tester.pumpAndSettle();

      // ExperienceLevel.intermediate → displayNameEs = "Intermedio" → uppercased in chip → "INTERMEDIO"
      expect(find.textContaining('INTERMEDIO'), findsOneWidget);
    });

    testWidgets('no text matching "alumnos" anywhere — SCENARIO-BIBW-09b',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(
          const TemplatesTab(),
          templates: [_templateA, _templateB, _templateC],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('alumnos'), findsNothing);
      expect(find.textContaining('alumno'), findsNothing);
    });

    testWidgets('shows empty-state when list is empty — SCENARIO-BIBW-09c',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(const TemplatesTab(), templates: const []),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GridView), findsNothing);
      expect(find.byType(TreinoEmptyState), findsOneWidget);
      expect(find.textContaining('plantilla'), findsWidgets);
    });

    testWidgets('shows TreinoShimmer skeleton when loading — SCENARIO-BIBW-11b',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Use a Completer-based stream that never emits (stays in loading)
      final completer = Completer<List<Routine>>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUidProvider.overrideWithValue(_kTrainerId),
            trainerTemplatesStreamProvider(_kTrainerId).overrideWith(
              (ref) => Stream.fromFuture(completer.future),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: TemplatesTab()),
          ),
        ),
      );
      await tester.pump(); // single frame — stream still pending

      expect(find.byType(TreinoShimmer), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows error text when stream errors — SCENARIO-BIBW-11b',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(const TemplatesTab(), error: true),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('Error'), findsOneWidget);
    });
  });

  group('TemplatesTab — template detail dialog', () {
    testWidgets('tap template card opens TreinoDialog — SCENARIO-BIBW-10a',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(const TemplatesTab(), templates: [_templateA]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Fuerza Total'));
      await tester.pumpAndSettle();

      expect(find.byType(TreinoDialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets(
        'detail dialog is read-only — no edit controls — SCENARIO-BIBW-10a',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(const TemplatesTab(), templates: [_templateA]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Fuerza Total'));
      await tester.pumpAndSettle();

      // No TextField or editing widgets in dialog
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(EditableText), findsNothing);
    });

    testWidgets('detail dialog has Cerrar button that dismisses it',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(const TemplatesTab(), templates: [_templateA]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Fuerza Total'));
      await tester.pumpAndSettle();

      expect(find.text('Cerrar'), findsOneWidget);

      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();

      expect(find.byType(TreinoDialog), findsNothing);
    });
  });
}
