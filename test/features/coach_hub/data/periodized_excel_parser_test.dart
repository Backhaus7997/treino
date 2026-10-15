import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/data/periodized_excel_parser.dart';
import 'package:treino/features/coach_hub/domain/periodized_plan.dart';
import 'package:treino/features/workout/domain/set_enums.dart';
import 'package:treino/features/workout/domain/set_spec.dart';

import 'periodized_test_helpers.dart';

ImportDiagnostic _only(
  PeriodizedParseResult r,
  ImportDiagnosticCode code,
) =>
    r.diagnostics.singleWhere((d) => d.code == code);

void main() {
  group('filas', () {
    test('se carga sólo con nombre; sin nombre se ignora aunque tenga reps',
        () {
      final r = parsePeriodizedExcel(programa([
        header1(),
        [1, 'Ejercicio A', 90, '3x8', '3x9', '3x10'],
        [2, null, 60, '3x8', '3x8', '3x8'], // sin nombre: ignorada
        [null, null, null, null, null, null],
        [2, 'Ejercicio B', null, '3x5', '3x5', '3x5'],
      ]));
      expect(r.canImport, isTrue, reason: '${r.diagnostics}');
      final rows = r.plan!.days.single.rows;
      expect(rows.map((e) => e.exercises.single.rawName),
          ['Ejercicio A', 'Ejercicio B']);
      expect(rows.map((e) => e.excelRow), [2, 5]);
    });

    test('renglones vacíos en cualquier lugar del bloque', () {
      final r = parsePeriodizedExcel(programa([
        header1(),
        [],
        [],
        [1, 'Ejercicio A', 90, '3x8', '3x8', '3x8'],
        [],
        [2, 'Ejercicio B', 90, '3x8', '3x8', '3x8'],
        [],
      ]));
      expect(r.canImport, isTrue);
      expect(r.plan!.days.single.rows, hasLength(2));
    });

    test(
        'nombre sin ninguna prescripción se carga con 1 serie sin reps, y el '
        'plan queda en 1 semana', () {
      final r = parsePeriodizedExcel(programa([
        header1(),
        [1, 'Ejercicio A'],
      ]));
      expect(r.canImport, isTrue);
      expect(r.plan!.numWeeks, 1);
      final ex = r.plan!.days.single.rows.single.exercises.single;
      expect(ex.weeks, hasLength(1));
      expect(ex.weeks.every((w) => w.length == 1 && w.single.reps == null),
          isTrue);
      expect(ex.emptyWeeks, {0});
      expect(
          r.warnings.where((d) => d.code == ImportDiagnosticCode.missingReps),
          hasLength(1));
      expect(r.warnings.where((d) => d.code == ImportDiagnosticCode.emptyWeek),
          isEmpty);
    });

    test('sin N° = calentamiento: todas las series son warmup', () {
      final r = parsePeriodizedExcel(programa([
        header1(),
        [
          null,
          'Ejercicio T + Ejercicio U',
          null,
          "8'+3x20",
          "8'+3x24",
          "9'+3x20"
        ],
        [1, 'Ejercicio A', 90, '3x8', '3x8', '3x8'],
      ]));
      expect(r.canImport, isTrue, reason: '${r.diagnostics}');
      final rows = r.plan!.days.single.rows;
      expect(rows[0].isWarmup, isTrue);
      expect(rows[1].isWarmup, isFalse);
      final sets = rows[0].exercises.expand((e) => e.weeks).expand((w) => w);
      expect(sets.every((s) => s.type == SetType.warmup), isTrue);
      expect(rows[1].exercises.single.weeks.first.first.type, SetType.normal);
      // El calentamiento no corre la numeración: el 1 sigue siendo el 1.
      expect(
          r.warnings.where((d) => d.code == ImportDiagnosticCode.numberingGap),
          isEmpty);
    });

    test('numeración salteada o repetida es aviso, no error', () {
      final r = parsePeriodizedExcel(programa([
        header1(),
        [1, 'Ejercicio A', null, '3x8', '3x8', '3x8'],
        [3, 'Ejercicio B', null, '3x8', '3x8', '3x8'],
        [3, 'Ejercicio C', null, '3x8', '3x8', '3x8'],
      ]));
      expect(r.canImport, isTrue);
      final gaps = r.warnings
          .where((d) => d.code == ImportDiagnosticCode.numberingGap)
          .toList();
      expect(gaps.map((d) => d.cellRef), ['Programa!A3', 'Programa!A4']);
    });

    test('N° ilegible es error con coordenadas', () {
      final r = parsePeriodizedExcel(programa([
        header1(),
        ['x', 'Ejercicio A', null, '3x8', '3x8', '3x8'],
      ]));
      final d = _only(r, ImportDiagnosticCode.invalidNumber);
      expect([d.sheet, d.row, d.column, d.rawValue], ['Programa', 2, 'A', 'x']);
    });
  });

  group('superseries', () {
    test(
        'un renglón con + produce un ejercicio por componente, en orden y '
        'con descanso del renglón', () {
      final r = parsePeriodizedExcel(programa([
        header1(),
        [
          1,
          'Ejercicio A + Ejercicio B + Ejercicio C',
          "1'30",
          '3x4+2+6m',
          '3x5+2+6m',
          '3x5+3+8m'
        ],
      ]));
      expect(r.canImport, isTrue, reason: '${r.diagnostics}');
      final row = r.plan!.days.single.rows.single;
      expect(row.isSuperset, isTrue);
      expect(row.restSeconds, 90);
      expect(row.exercises.map((e) => e.rawName),
          ['Ejercicio A', 'Ejercicio B', 'Ejercicio C']);
      expect(row.exercises[2].weeks[0],
          List.filled(3, const SetSpec(distanceMeters: 6)));
      expect(row.exercises[1].weeks[2].first.reps, 3);
    });

    test('cantidad de átomos distinta: error con fila/columna/valor', () {
      final r = parsePeriodizedExcel(programa([
        header1(),
        [
          1,
          'Ejercicio A + Ejercicio B + Ejercicio C',
          90,
          '3x4+2',
          '3x4+2+6m',
          '3x4+2+6m'
        ],
      ]));
      final d = _only(r, ImportDiagnosticCode.atomCountMismatch);
      expect(d.isError, isTrue);
      expect([d.sheet, d.row, d.column, d.rawValue],
          ['Programa', 2, 'D', '3x4+2']);
      expect(r.canImport, isFalse);
    });

    test('un renglón de 1 ejercicio con 2 átomos también es error', () {
      final r = parsePeriodizedExcel(programa([
        header1(weeks: 1),
        [1, 'Ejercicio A', 90, '3x8+2'],
      ]));
      expect(_only(r, ImportDiagnosticCode.atomCountMismatch).column, 'D');
    });

    test('componente vacío ("A +") es error', () {
      final r = parsePeriodizedExcel(programa([
        header1(weeks: 1),
        [1, 'Ejercicio A + ', 90, '3x8'],
      ]));
      expect(_only(r, ImportDiagnosticCode.emptyExerciseComponent).column, 'B');
    });
  });

  group('celdas de semana', () {
    test('celda vacía en renglón con nombre: 1 serie sin reps y aviso', () {
      final r = parsePeriodizedExcel(programa([
        header1(),
        [1, 'Ejercicio A', 90, '3x8', null, '3x8'],
      ]));
      expect(r.canImport, isTrue);
      final ex = r.plan!.days.single.rows.single.exercises.single;
      expect(ex.weeks[1], [const SetSpec()]);
      expect(ex.emptyWeeks, {1});
      final w = _only(r, ImportDiagnosticCode.missingReps);
      expect(w.isError, isFalse);
      expect([w.row, w.column], [2, 'E']);
    });

    test('celda ilegible: error con hoja, fila, columna y valor', () {
      final r = parsePeriodizedExcel(programa([
        header1(),
        [1, 'Ejercicio A', 90, '3x8', 'tres por ocho', '3x8'],
      ]));
      final d = _only(r, ImportDiagnosticCode.unreadableCell);
      expect([d.sheet, d.row, d.column, d.rawValue],
          ['Programa', 2, 'E', 'tres por ocho']);
    });

    test('se juntan TODOS los errores, no sólo el primero', () {
      final r = parsePeriodizedExcel(programa([
        header1(),
        [1, 'Ejercicio A', 'zzz', 'xx', 'yy', '3x8'],
        [2, 'Ejercicio B + Ejercicio C', 90, '3x8', '3x8', '3x8'],
      ]));
      expect(
          r.errors.map((d) => d.code),
          containsAll([
            ImportDiagnosticCode.invalidRest,
            ImportDiagnosticCode.unreadableCell,
            ImportDiagnosticCode.atomCountMismatch,
          ]));
      expect(
          r.errors.where((d) => d.code == ImportDiagnosticCode.unreadableCell),
          hasLength(2));
    });

    test('calificador: nota del slot y aviso', () {
      final r = parsePeriodizedExcel(programa([
        header1(),
        [1, 'Ejercicio A', 90, '3x10 c/pierna', '3x10 c/pierna', '3x10'],
      ]));
      expect(r.canImport, isTrue);
      final ex = r.plan!.days.single.rows.single.exercises.single;
      expect(ex.note, 'c/pierna');
      expect(ex.weeks[0], List.filled(3, const SetSpec(reps: 10)));
      expect(
        r.warnings
            .where((d) => d.code == ImportDiagnosticCode.qualifierSavedAsNote),
        hasLength(2),
      );
    });

    test('mezcla distancia y reps entre semanas: aviso', () {
      final r = parsePeriodizedExcel(programa([
        header1(weeks: 2),
        [1, 'Ejercicio A', 90, '3x8', '20m'],
      ]));
      expect(r.canImport, isTrue);
      expect(_only(r, ImportDiagnosticCode.mixedSetKinds).isError, isFalse);
    });

    test('valores numéricos nativos de Excel (8, 90) se leen', () {
      final r = parsePeriodizedExcel(programa([
        header1(weeks: 1),
        [1, 'Ejercicio A', 90, 8],
      ]));
      expect(r.canImport, isTrue);
      final row = r.plan!.days.single.rows.single;
      expect(row.restSeconds, 90);
      expect(row.exercises.single.weeks.single, [const SetSpec(reps: 8)]);
    });
  });

  group('descanso', () {
    test('vacío = 60, inválido = error con fila y columna C', () {
      final r = parsePeriodizedExcel(programa([
        header1(weeks: 1),
        [1, 'Ejercicio A', null, '3x8'],
        [2, 'Ejercicio B', 'rápido', '3x8'],
      ]));
      expect(r.plan!.days.single.rows.first.restSeconds, 60);
      final d = _only(r, ImportDiagnosticCode.invalidRest);
      expect([d.row, d.column, d.rawValue], [3, 'C', 'rápido']);
    });
  });

  group('semanas vacías', () {
    Iterable<ImportDiagnostic> codeOf(
            PeriodizedParseResult r, ImportDiagnosticCode c) =>
        r.diagnostics.where((d) => d.code == c);

    test('6 columnas con 4 cargadas: numWeeks 4 y sin avisos de la 5 y 6', () {
      final r = parsePeriodizedExcel(programa([
        header1(weeks: 6),
        [1, 'Ejercicio A', 90, '3x8', '3x9', '3x10', '3x11', null, null],
        [],
        header(2),
        [1, 'Ejercicio B', null, '3x5', '3x5', '3x5', '3x5'],
      ]));
      expect(r.canImport, isTrue, reason: '${r.diagnostics}');
      expect(r.plan!.numWeeks, 4);
      for (final row in r.plan!.days.expand((d) => d.rows)) {
        expect(row.exercises.single.weeks, hasLength(4));
        expect(row.exercises.single.emptyWeeks, isEmpty);
      }
      expect(codeOf(r, ImportDiagnosticCode.missingReps), isEmpty);
      expect(codeOf(r, ImportDiagnosticCode.emptyWeek), isEmpty);
    });

    test('una sola celda con texto en la semana 6 conserva las 6', () {
      final r = parsePeriodizedExcel(programa([
        header1(weeks: 6),
        [1, 'Ejercicio A', 90, '3x8', '3x8', '3x8', '3x8', '3x8', '3x8'],
        [2, 'Ejercicio B', 90, '3x8', '3x8', '3x8', '3x8', '3x8', null],
      ]));
      expect(r.plan!.numWeeks, 6);
      // La celda vacía de la semana 6 sigue la regla normal (rojo).
      expect(codeOf(r, ImportDiagnosticCode.missingReps), hasLength(1));
    });

    test('una celda en la semana 6 de otro día también la mantiene', () {
      final r = parsePeriodizedExcel(programa([
        header1(weeks: 6),
        [1, 'Ejercicio A', 90, '3x8'],
        header(2),
        [1, 'Ejercicio B', 90, null, null, null, null, null, '3x8'],
      ]));
      expect(r.plan!.numWeeks, 6);
    });

    test('semana vacía en el medio: se conserva, con aviso y celdas en rojo',
        () {
      final r = parsePeriodizedExcel(programa([
        header1(weeks: 4),
        [1, 'Ejercicio A', 90, '3x8', '3x9', null, '3x11'],
        [2, 'Ejercicio B', 90, '3x8', '3x9', null, '3x11'],
      ]));
      expect(r.canImport, isTrue);
      expect(r.plan!.numWeeks, 4);
      final w = codeOf(r, ImportDiagnosticCode.emptyWeek).single;
      expect(w.severity, ImportDiagnosticSeverity.warning);
      expect(w.message, 'SEMANA 3 está vacía en todo el plan.');
      expect(w.column, 'F');
      expect(codeOf(r, ImportDiagnosticCode.missingReps), hasLength(2));
      for (final row in r.plan!.days.single.rows) {
        expect(row.exercises.single.emptyWeeks, {2});
      }
    });

    test('un renglón sin nombre no cuenta como contenido de la semana', () {
      final r = parsePeriodizedExcel(programa([
        header1(weeks: 6),
        [1, 'Ejercicio A', 90, '3x8', '3x8'],
        [2, null, 90, null, null, null, null, null, '3x8'], // ignorado
      ]));
      expect(r.plan!.numWeeks, 2);
    });

    test('todas las semanas vacías: numWeeks 1, sin error', () {
      final r = parsePeriodizedExcel(programa([
        header1(weeks: 6),
        [1, 'Ejercicio A'],
      ]));
      expect(r.canImport, isTrue, reason: '${r.diagnostics}');
      expect(r.plan!.numWeeks, 1);
      expect(codeOf(r, ImportDiagnosticCode.emptyWeek), isEmpty);
    });
  });

  group('días y semanas', () {
    test('varios días; los encabezados posteriores no repiten SEMANA', () {
      final r = parsePeriodizedExcel(programa([
        header1(),
        [1, 'Ejercicio A', null, '3x8', '3x8', '3x8'],
        [],
        header(2),
        [1, 'Ejercicio B', null, '3x8', '3x8', '3x8'],
      ]));
      expect(r.canImport, isTrue, reason: '${r.diagnostics}');
      expect(r.plan!.numWeeks, 3);
      expect(r.plan!.days.map((d) => d.dayNumber), [1, 2]);
      expect(r.plan!.days.map((d) => d.headerRow), [1, 4]);
    });

    test('hasta 7 días y 16 semanas pasan; la cantidad de renglones no importa',
        () {
      final rows = <List<Object?>>[header1(weeks: 16)];
      for (var d = 1; d <= 7; d++) {
        if (d > 1) rows.add(header(d));
        for (var i = 1; i <= (d == 1 ? 25 : 1); i++) {
          rows.add([i, 'Ejercicio $d.$i', null, ...List.filled(16, '3x8')]);
        }
      }
      final r = parsePeriodizedExcel(programa(rows));
      expect(r.canImport, isTrue, reason: '${r.diagnostics}');
      expect(r.plan!.numWeeks, 16);
      expect(r.plan!.days, hasLength(7));
      expect(r.plan!.days.first.rows, hasLength(25));
    });

    test('8 días: error', () {
      final rows = <List<Object?>>[header1(weeks: 1)];
      for (var d = 1; d <= 8; d++) {
        if (d > 1) rows.add(header(d));
        rows.add([1, 'Ejercicio $d', null, '3x8']);
      }
      final r = parsePeriodizedExcel(programa(rows));
      final d = _only(r, ImportDiagnosticCode.tooManyDays);
      expect(d.isError, isTrue);
      expect(r.canImport, isFalse);
    });

    test('17 semanas: error', () {
      final r = parsePeriodizedExcel(programa([
        header1(weeks: 17),
        [1, 'Ejercicio A', null, ...List.filled(17, '3x8')],
      ]));
      expect(_only(r, ImportDiagnosticCode.tooManyWeeks).isError, isTrue);
    });

    test('día repetido: error', () {
      final r = parsePeriodizedExcel(programa([
        header1(weeks: 1),
        [1, 'Ejercicio A', null, '3x8'],
        header(1),
        [1, 'Ejercicio B', null, '3x8'],
      ]));
      final d = _only(r, ImportDiagnosticCode.duplicatedDay);
      expect([d.row, d.column], [3, 'B']);
    });

    test('semanas no contiguas (hueco) y duplicadas: error', () {
      final hueco = parsePeriodizedExcel(programa([
        ['N°', 'DÍA 1', 'DESCANSOS', 'SEMANA 1', 'SEMANA 2', null, 'SEMANA 3'],
        [1, 'Ejercicio A', null, '3x8'],
      ]));
      final h = _only(hueco, ImportDiagnosticCode.weekColumnsNotContiguous);
      expect([h.row, h.column, h.rawValue], [1, 'G', 'SEMANA 3']);

      final dup = parsePeriodizedExcel(programa([
        ['N°', 'DÍA 1', 'DESCANSOS', 'SEMANA 1', 'SEMANA 2', 'SEMANA 2'],
        [1, 'Ejercicio A', null, '3x8'],
      ]));
      expect(
          _only(dup, ImportDiagnosticCode.weekColumnsDuplicated).column, 'F');
    });

    test('renglón con nombre antes del primer bloque: error', () {
      final r = parsePeriodizedExcel(programa([
        [null, 'Ejercicio perdido'],
        header1(weeks: 1),
        [1, 'Ejercicio A', null, '3x8'],
      ]));
      final d = _only(r, ImportDiagnosticCode.exerciseOutsideBlock);
      expect([d.row, d.column, d.rawValue], [1, 'B', 'Ejercicio perdido']);
    });

    test('plan sin ningún ejercicio: error', () {
      final r = parsePeriodizedExcel(programa([header1(weeks: 2), [], []]));
      expect(_only(r, ImportDiagnosticCode.noExercises).isError, isTrue);
      expect(r.canImport, isFalse);
    });
  });

  group('encabezado', () {
    test('acepta DIA sin tilde, minúsculas y descansos en minúscula', () {
      final r = parsePeriodizedExcel(programa([
        ['n°', 'dia 1', 'descansos', 'semana 1', 'Semana 2'],
        [1, 'Ejercicio A', null, '3x8', '3x8'],
        ['N°', 'DIA 2', 'DESCANSOS'],
        [1, 'Ejercicio B', null],
      ]));
      expect(r.canImport, isTrue, reason: '${r.diagnostics}');
      expect(r.plan!.numWeeks, 2);
      expect(r.plan!.days.map((d) => d.dayNumber), [1, 2]);
    });

    test(
        'el encabezado puede estar más abajo (filas de título arriba en '
        'otras columnas)', () {
      final r = parsePeriodizedExcel(programa([
        ['Plan de prueba'],
        [],
        header1(weeks: 1),
        [1, 'Ejercicio A', null, '3x8'],
      ]));
      expect(r.canImport, isTrue, reason: '${r.diagnostics}');
      expect(r.plan!.days.single.headerRow, 3);
    });

    test('sin encabezado DÍA/DESCANSOS: error', () {
      final r = parsePeriodizedExcel(programa([
        ['algo', 'otra cosa'],
      ]));
      expect(_only(r, ImportDiagnosticCode.noDayHeader).isError, isTrue);
      expect(r.plan, isNull);
    });
  });

  group('celdas que Excel convirtió', () {
    const date = DateCellValue(year: 2026, month: 3, day: 4);
    const time = TimeCellValue(hour: 1, minute: 30);

    ImportDiagnostic cellError(PeriodizedParseResult r, String column) =>
        r.errors.singleWhere((e) => e.column == column);

    test('fecha u hora en SEMANA: error propio con la celda', () {
      final r = parsePeriodizedExcel(programa([
        header1(weeks: 3),
        [1, 'Ejercicio A', 90, date, time, '3x8'],
      ]));
      expect(r.canImport, isFalse);
      for (final col in ['D', 'E']) {
        final d = cellError(r, col);
        expect(d.code, ImportDiagnosticCode.unreadableCell);
        expect(d.row, 2);
        expect(d.message, kAutoConvertedCellMessage);
      }
      expect(r.errors, hasLength(2));
    });

    test('fecha u hora en DESCANSOS: error propio con la celda', () {
      for (final v in <CellValue>[date, time]) {
        final r = parsePeriodizedExcel(programa([
          header1(weeks: 1),
          [1, 'Ejercicio A', v, '3x8'],
        ]));
        final d = cellError(r, 'C');
        expect(d.code, ImportDiagnosticCode.invalidRest);
        expect(d.row, 2);
        expect(d.message, kAutoConvertedCellMessage);
        expect(r.errors, hasLength(1));
      }
    });

    test('fórmula en SEMANA o DESCANSOS: pide pegar el valor', () {
      final r = parsePeriodizedExcel(programa([
        header1(weeks: 1),
        [
          1,
          'Ejercicio A',
          const FormulaCellValue('=60+30'),
          const FormulaCellValue('=3*8')
        ],
      ]));
      expect(cellError(r, 'C').message, kFormulaCellMessage);
      expect(cellError(r, 'C').code, ImportDiagnosticCode.invalidRest);
      expect(cellError(r, 'D').message, kFormulaCellMessage);
      expect(cellError(r, 'D').code, ImportDiagnosticCode.unreadableCell);
    });

    test('un entero en DESCANSOS y en SEMANA se lee como número', () {
      final r = parsePeriodizedExcel(programa([
        header1(weeks: 1),
        [1, 'Ejercicio A', const IntCellValue(90), const IntCellValue(10)],
      ]));
      expect(r.canImport, isTrue, reason: '${r.diagnostics}');
      final row = r.plan!.days.single.rows.single;
      expect(row.restSeconds, 90);
      expect(row.exercises.single.weeks.single, hasLength(1));
    });
  });

  group('formato viejo y archivos ajenos', () {
    test(
        'el formato simple viejo (hojas Plan + Día N) se rechaza con el '
        'mensaje de la plantilla nueva', () {
      final excel = Excel.createExcel();
      excel.rename(excel.getDefaultSheet()!, 'Plan');
      excel['Día 1'];
      final r = parsePeriodizedExcel(Uint8List.fromList(excel.save()!));
      final d = _only(r, ImportDiagnosticCode.oldFormat);
      expect(d.isError, isTrue);
      expect(d.message, kOldFormatMessage);
      expect(d.message, contains('plantilla nueva'));
      expect(r.plan, isNull);
    });

    test('un Excel sin hoja Programa ni formato viejo: no es la plantilla', () {
      final r = parsePeriodizedExcel(programa([
        [1]
      ], sheetName: 'Otra'));
      expect(_only(r, ImportDiagnosticCode.notTemplate).isError, isTrue);
    });

    test('bytes basura: error de archivo ilegible, sin tirar', () {
      final r = parsePeriodizedExcel(Uint8List.fromList([1, 2, 3, 4, 5]));
      expect(_only(r, ImportDiagnosticCode.unreadableFile).isError, isTrue);
    });
  });
}
