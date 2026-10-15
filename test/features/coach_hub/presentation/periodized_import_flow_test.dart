import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/coach_hub/data/periodized_template_builder.dart';
import 'package:treino/features/coach_hub/presentation/coach_hub_plan_preview_screen.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/features/workout/domain/set_enums.dart';
import 'package:treino/features/workout/domain/exercise.dart';

import '../data/periodized_test_helpers.dart';
import 'periodized_draft_fixtures.dart';

Exercise _ex(String letter) => Exercise(
      id: 'ex-$letter',
      name: 'Ejercicio $letter',
      muscleGroup: 'legs',
      category: 'compound',
    );

/// Plan armado sobre la PLANTILLA descargable (6 semanas), con nombres
/// genéricos. Filas base 0: el encabezado del DÍA 1 es la 0, los renglones
/// 1..10; el DÍA 2 arranca en la 11.
///
/// DÍA 1
///   - calentamiento: Ejercicio A, 2x10 todas las semanas
///   - 1: superserie Ejercicio B + Ejercicio C, descanso 90, `3x{3+w}+2`
///   - 2: Ejercicio D, descanso 1'30, S1 `3xmax`, S3 vacía, resto `3x8`
/// DÍA 2
///   - 1: Ejercicio E, duración `8'` todas las semanas
///   - 2: Ejercicio F, descanso 45, distancia `4x20m`
Map<(int, int), Object> _plan() {
  const w0 = 3; // columna D = SEMANA 1
  const day2 = 1 + kTemplateRowsPerDay + 1; // primer renglón del 2.º bloque
  return {
    // DÍA 1 — calentamiento
    (1, 1): 'Ejercicio A',
    for (var w = 0; w < 6; w++) (1, w0 + w): '2x10',
    // DÍA 1 — superserie
    (2, 0): 1,
    (2, 1): 'Ejercicio B + Ejercicio C',
    (2, 2): 90,
    for (var w = 0; w < 6; w++) (2, w0 + w): '3x${3 + w}+2',
    // DÍA 1 — al fallo, con S3 vacía
    (3, 0): 2,
    (3, 1): 'Ejercicio D',
    (3, 2): "1'30",
    for (var w = 0; w < 6; w++)
      if (w != 2) (3, w0 + w): w == 0 ? '3xmax' : '3x8',
    // DÍA 2
    (day2, 0): 1,
    (day2, 1): 'Ejercicio E',
    for (var w = 0; w < 6; w++) (day2, w0 + w): "8'",
    (day2 + 1, 0): 2,
    (day2 + 1, 1): 'Ejercicio F',
    (day2 + 1, 2): 45,
    for (var w = 0; w < 6; w++) (day2 + 1, w0 + w): '4x20m',
  };
}

void main() {
  useTallSurface();

  setUpAll(() => registerFallbackValue(
        const Routine(
            id: '', name: '', level: ExperienceLevel.beginner, days: []),
      ));

  testWidgets(
      'plantilla llena → subir → vista previa → asignar: la Routine que se '
      'persiste', (tester) async {
    final repo = MockRoutineRepo();
    final captured = <Routine>[];
    when(() => repo.createAssigned(any())).thenAnswer((inv) async {
      final r = inv.positionalArguments.first as Routine;
      captured.add(r);
      return r.copyWith(id: 'r-1');
    });

    final bytes = fillTemplate(buildPeriodizedTemplateBytes(), _plan());
    await pumpUploadFlow(
      tester,
      bytes: bytes,
      catalog: [for (final l in 'ABCDEF'.split('')) _ex(l)],
      routineRepo: repo,
      fileName: 'Bloque de fuerza.xlsx',
    );
    await pickAndProcess(tester);

    // Vista previa: 6 semanas, la celda vacía de D en la SEMANA 3 en rojo.
    expect(find.byType(CoachHubPlanPreviewScreen), findsOneWidget);
    expect(find.text('SEMANA 6'), findsOneWidget);
    await tester.tap(find.text('SEMANA 3'));
    await tester.pumpAndSettle();
    expect(find.text('falta cargar reps'), findsOneWidget);
    expect(find.textContaining('Programa!F4'), findsOneWidget);

    // Asignar a la alumna: el aviso NO bloquea.
    await tester.tap(find.text('Ana'));
    await tester.pump();
    await tester.tap(find.text('ASIGNAR PLAN'));
    await tester.pumpAndSettle();

    expect(captured, hasLength(1));
    expect(find.text('DASHBOARD'), findsOneWidget);
    final r = captured.single;

    // Procedencia, como la asignación de siempre.
    expect(r.name, 'Bloque de fuerza');
    expect(r.numWeeks, 6);
    expect(r.source, RoutineSource.trainerAssigned);
    expect(r.assignedBy, kTrainerUid);
    expect(r.assignedTo, kAthleteId);
    expect(r.visibility, RoutineVisibility.private);
    expect(r.split, 'Custom');
    expect(r.days.map((d) => d.dayNumber), [1, 2]);

    // ── DÍA 1 ────────────────────────────────────────────────────────────
    final d1 = r.days[0].slots;
    expect(d1.map((s) => s.exerciseId), ['ex-A', 'ex-B', 'ex-C', 'ex-D']);

    // Calentamiento: 2 series warmup de 10 en las 6 semanas.
    final a = d1[0];
    expect(a.supersetGroup, isNull);
    expect(a.weeklySets, hasLength(6));
    for (final week in a.weeklySets) {
      expect(week, hasLength(2));
      expect(
          week.every((s) => s.type == SetType.warmup && s.reps == 10), isTrue);
    }
    expect(a.restSeconds, 60, reason: 'descanso vacío = 60 s');

    // Superserie B + C: mismo grupo, el descanso va en el ÚLTIMO slot.
    final b = d1[1];
    final c = d1[2];
    expect(b.supersetGroup, isNotNull);
    expect(b.supersetGroup, c.supersetGroup);
    expect(d1[0].supersetGroup, isNull);
    expect(d1[3].supersetGroup, isNull);
    expect(b.restSeconds, 0);
    expect(c.restSeconds, 90);
    for (var w = 0; w < 6; w++) {
      // `3x{3+w}+2`: B hace 3 series de 3+w y C 3 series de 2 (el conteo del
      // primer átomo se propaga).
      expect(b.weeklySets[w].map((s) => s.reps), List.filled(3, 3 + w));
      expect(c.weeklySets[w].map((s) => s.reps), List.filled(3, 2));
    }

    // D: S1 al fallo, S3 sin reps (aviso), el resto 3x8; descanso 1'30 = 90.
    final dd = d1[3];
    expect(dd.restSeconds, 90);
    expect(dd.weeklySets[0], hasLength(3));
    expect(dd.weeklySets[0].every((s) => s.type == SetType.failure), isTrue);
    expect(dd.weeklySets[0].every((s) => s.reps == null), isTrue);
    expect(dd.weeklySets[2], hasLength(1));
    expect(dd.weeklySets[2].single.reps, isNull);
    expect(dd.weeklySets[2].single.type, SetType.normal);
    expect(dd.weeklySets[1].map((s) => s.reps), [8, 8, 8]);
    expect(dd.activeWeeks, isEmpty, reason: 'ningún slot falta en una semana');

    // ── DÍA 2 ────────────────────────────────────────────────────────────
    final d2 = r.days[1].slots;
    expect(d2.map((s) => s.exerciseId), ['ex-E', 'ex-F']);

    final e = d2[0];
    expect(e.exerciseMode, ExerciseMode.duration);
    for (final week in e.weeklySets) {
      expect(week.single.durationSeconds, 480);
    }
    expect(e.durationSeconds, 480, reason: 'legacy = semana 1');

    final f = d2[1];
    expect(f.exerciseMode, ExerciseMode.distance);
    expect(f.restSeconds, 45);
    for (final week in f.weeklySets) {
      expect(week, hasLength(4));
      expect(week.every((s) => s.distanceMeters == 20), isTrue);
    }

    // Campos legacy del slot = SEMANA 1, como el editor.
    expect(b.targetSets, 3);
    expect(b.sets, b.weeklySets.first);
  });
}
