import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/data/periodized_excel_parser.dart';
import 'package:treino/features/coach_hub/presentation/coach_hub_plan_preview_screen.dart';
import 'package:treino/features/coach_hub/presentation/coach_hub_upload_plan_screen.dart';
import 'package:treino/features/workout/domain/exercise.dart';

import '../data/periodized_test_helpers.dart';
import 'periodized_draft_fixtures.dart';

Exercise _ex(String id, String name) =>
    Exercise(id: id, name: name, muscleGroup: 'legs', category: 'compound');

void main() {
  useTallSurface();

  group('errores del archivo', () {
    testWidgets(
        'lista TODOS los errores agrupados, cada uno con su celda, y no '
        'avanza', (tester) async {
      // Programa: fila 2 (D2) con 2 términos en un renglón de 3 ejercicios,
      // fila 3 (C3) con descanso inválido, fila 4 (E4) celda ilegible.
      final bytes = programa([
        header1(weeks: 3),
        [
          1,
          'Ejercicio A + Ejercicio B + Ejercicio C',
          null,
          '3x4+2',
          '3x8+8+8',
          '3x8+8+8'
        ],
        [2, 'Ejercicio D', 'abc', '3x8', '3x8', '3x8'],
        [3, 'Ejercicio E', null, '3x8', 'tres series', '3x8'],
      ]);
      await pumpUploadFlow(
        tester,
        bytes: bytes,
        catalog: [_ex('a', 'Ejercicio A')],
        routineRepo: MockRoutineRepo(),
      );
      await pickAndProcess(tester);

      expect(
          find.textContaining('Hay 3 errores en el archivo'), findsOneWidget);
      // Cada error con su celda y el valor recibido.
      expect(find.textContaining('Programa!D2'), findsOneWidget);
      expect(find.textContaining('`3x4+2`'), findsOneWidget);
      expect(find.textContaining('Programa!C3'), findsOneWidget);
      expect(find.textContaining('`abc`'), findsOneWidget);
      expect(find.textContaining('Programa!E4'), findsOneWidget);
      expect(find.textContaining('`tres series`'), findsOneWidget);
      // Agrupados por tipo, con su cantidad.
      expect(
        find.text(
            'Valores que no coinciden con los ejercicios del renglón (1)'),
        findsOneWidget,
      );
      expect(find.text('Descansos inválidos (1)'), findsOneWidget);
      expect(find.text('Celdas que no se entienden (1)'), findsOneWidget);

      // No avanzó a la vista previa y no dejó nada cargado.
      expect(find.byType(CoachHubPlanPreviewScreen), findsNothing);
      expect(find.byType(CoachHubUploadPlanScreen), findsOneWidget);
    });

    testWidgets('un Excel del formato viejo pide bajar la plantilla nueva',
        (tester) async {
      // Hoja "Plan": la señal del formato simple anterior.
      final bytes = programa([
        ['Campo', 'Valor'],
        ['Nombre', 'Mi plan'],
      ], sheetName: 'Plan');
      await pumpUploadFlow(
        tester,
        bytes: bytes,
        catalog: const [],
        routineRepo: MockRoutineRepo(),
      );
      await pickAndProcess(tester);

      expect(find.textContaining(kOldFormatMessage), findsOneWidget);
      expect(find.text('Formato viejo (1)'), findsOneWidget);
      expect(find.byType(CoachHubPlanPreviewScreen), findsNothing);
    });

    testWidgets('un archivo que no es la plantilla tampoco avanza',
        (tester) async {
      final bytes = programa([
        ['cualquier cosa'],
      ], sheetName: 'Otra hoja');
      await pumpUploadFlow(
        tester,
        bytes: bytes,
        catalog: const [],
        routineRepo: MockRoutineRepo(),
      );
      await pickAndProcess(tester);

      expect(find.text('No es la plantilla nueva (1)'), findsOneWidget);
      expect(find.byType(CoachHubPlanPreviewScreen), findsNothing);
    });
  });

  testWidgets(
      'un archivo válido avanza a la vista previa con el nombre del '
      'archivo', (tester) async {
    final bytes = programa([
      header1(weeks: 2),
      [1, 'Ejercicio A', 60, '3x8', '3x9'],
    ]);
    await pumpUploadFlow(
      tester,
      bytes: bytes,
      catalog: [_ex('a', 'Ejercicio A')],
      routineRepo: MockRoutineRepo(),
      fileName: 'Plan de fuerza.xlsx',
    );
    await pickAndProcess(tester);

    expect(find.byType(CoachHubPlanPreviewScreen), findsOneWidget);
    expect(find.text('Plan de fuerza'), findsWidgets);
    expect(find.text('SEMANA 2'), findsOneWidget);
  });
}
