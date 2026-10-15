import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../../workout/domain/set_enums.dart';
import '../../workout/domain/set_spec.dart';
import '../domain/periodized_plan.dart';
import 'excel_parser.dart';
import 'periodized_cell_grammar.dart';

/// Hoja de la plantilla periodizada donde vive el plan.
const String kProgramSheet = 'Programa';

/// Hoja de ayuda de la plantilla (el parser la ignora).
const String kInstructionsSheet = 'Instrucciones';

/// Techos del producto (`athlete_entitlement.dart`).
const int kMaxImportDays = 7;
const int kMaxImportWeeks = 16;

/// Mensaje de rechazo del formato simple viejo.
const String kOldFormatMessage =
    'Este Excel es del formato viejo. Bajá la plantilla nueva desde el '
    'Coach Hub y cargá tu plan ahí.';

final RegExp _dayHeaderRegex =
    RegExp(r'^d[ií]a\s*(\d+)$', caseSensitive: false);
final RegExp _weekHeaderRegex =
    RegExp(r'^semana\s*(\d+)$', caseSensitive: false);

/// Letra de columna de Excel para un índice base 0 (0 → A, 26 → AA).
String columnLetter(int index) {
  var n = index + 1;
  var out = '';
  while (n > 0) {
    final rem = (n - 1) % 26;
    out = String.fromCharCode(65 + rem) + out;
    n = (n - 1) ~/ 26;
  }
  return out;
}

String _text(Data? data) {
  final v = data?.value;
  if (v == null) return '';
  if (v is DoubleCellValue) {
    final d = v.value;
    return d == d.truncateToDouble() ? d.toInt().toString() : d.toString();
  }
  return v.toString().trim();
}

/// Lee la plantilla periodizada y devuelve el borrador MÁS todos los
/// diagnósticos (no corta en el primer error).
PeriodizedParseResult parsePeriodizedExcel(Uint8List bytes) {
  final Excel workbook;
  try {
    workbook = decodeWorkbookBytes(bytes);
  } on ExcelParseException catch (e) {
    return PeriodizedParseResult(plan: null, diagnostics: [
      ImportDiagnostic(
        severity: ImportDiagnosticSeverity.error,
        code: ImportDiagnosticCode.unreadableFile,
        message: e.message,
      ),
    ]);
  }

  final sheet = workbook.sheets[kProgramSheet];
  if (sheet == null) {
    final isOld = workbook.sheets.containsKey('Plan') ||
        workbook.sheets.keys.any((n) => RegExp(r'^D[ií]a\s*\d+$').hasMatch(n));
    return PeriodizedParseResult(plan: null, diagnostics: [
      ImportDiagnostic(
        severity: ImportDiagnosticSeverity.error,
        code: isOld
            ? ImportDiagnosticCode.oldFormat
            : ImportDiagnosticCode.notTemplate,
        message: isOld
            ? kOldFormatMessage
            : 'No encontramos la hoja "$kProgramSheet". Bajá la plantilla '
                'desde el Coach Hub y cargá tu plan ahí.',
      ),
    ]);
  }
  return _ProgramParser(sheet).run();
}

class _Header {
  _Header(this.rowIndex, this.exerciseCol, this.dayNumber);
  final int rowIndex;
  final int exerciseCol;
  final int dayNumber;
}

class _ProgramParser {
  _ProgramParser(Sheet sheet)
      : _grid = sheet.rows,
        _sheetName = sheet.sheetName;

  final List<List<Data?>> _grid;
  final String _sheetName;
  final List<ImportDiagnostic> _diags = [];

  String _at(int row, int col) {
    if (row < 0 || row >= _grid.length) return '';
    final r = _grid[row];
    if (col < 0 || col >= r.length) return '';
    return _text(r[col]);
  }

  void _add(
    ImportDiagnosticSeverity sev,
    ImportDiagnosticCode code,
    String message, {
    int? row,
    int? col,
    String? raw,
  }) {
    _diags.add(ImportDiagnostic(
      severity: sev,
      code: code,
      message: message,
      sheet: _sheetName,
      row: row == null ? null : row + 1,
      column: col == null ? null : columnLetter(col),
      rawValue: raw,
    ));
  }

  void _error(ImportDiagnosticCode code, String message,
          {int? row, int? col, String? raw}) =>
      _add(ImportDiagnosticSeverity.error, code, message,
          row: row, col: col, raw: raw);

  void _warn(ImportDiagnosticCode code, String message,
          {int? row, int? col, String? raw}) =>
      _add(ImportDiagnosticSeverity.warning, code, message,
          row: row, col: col, raw: raw);

  /// Encabezado de día: `DÍA N` en una celda y `DESCANSOS` en la siguiente.
  _Header? _headerAt(int row) {
    final width = _grid[row].length;
    // Desde la columna B: la A es la del N°.
    for (var c = 1; c < width - 1; c++) {
      final m = _dayHeaderRegex.firstMatch(_at(row, c));
      if (m == null) continue;
      if (_at(row, c + 1).toLowerCase() != 'descansos') continue;
      return _Header(row, c, int.parse(m.group(1)!));
    }
    return null;
  }

  PeriodizedParseResult run() {
    final headers = <_Header>[];
    for (var r = 0; r < _grid.length; r++) {
      final h = _headerAt(r);
      if (h != null) headers.add(h);
    }
    if (headers.isEmpty) {
      _error(
        ImportDiagnosticCode.noDayHeader,
        'No encontramos ningún encabezado "DÍA N" con "DESCANSOS" al lado. '
        'Usá la plantilla nueva del Coach Hub.',
      );
      return PeriodizedParseResult(plan: null, diagnostics: _diags);
    }

    final first = headers.first;
    final exerciseCol = first.exerciseCol;
    final restCol = exerciseCol + 1;
    final numberCol = exerciseCol - 1;
    final weekCols = _weekColumns(first, restCol);
    final numWeeks = weekCols.length;

    // Renglones con nombre antes del primer encabezado: fuera de un bloque.
    for (var r = 0; r < first.rowIndex; r++) {
      final name = _at(r, exerciseCol);
      if (name.isNotEmpty) {
        _error(
          ImportDiagnosticCode.exerciseOutsideBlock,
          'Este renglón está fuera de un bloque DÍA.',
          row: r,
          col: exerciseCol,
          raw: name,
        );
      }
    }

    final days = <PeriodizedDay>[];
    final seenDays = <int>{};
    var namedRows = 0;

    for (var i = 0; i < headers.length; i++) {
      final h = headers[i];
      final end =
          i + 1 < headers.length ? headers[i + 1].rowIndex : _grid.length;
      final cellOfHeader = _at(h.rowIndex, h.exerciseCol);

      if (h.exerciseCol != exerciseCol) {
        _error(
          ImportDiagnosticCode.notTemplate,
          'El encabezado está en otra columna que el del DÍA 1.',
          row: h.rowIndex,
          col: h.exerciseCol,
          raw: cellOfHeader,
        );
      }
      if (h.dayNumber < 1) {
        _error(
          ImportDiagnosticCode.invalidDayNumber,
          'El número de día tiene que ser 1 o más.',
          row: h.rowIndex,
          col: h.exerciseCol,
          raw: cellOfHeader,
        );
      }
      if (!seenDays.add(h.dayNumber)) {
        _error(
          ImportDiagnosticCode.duplicatedDay,
          'El día ${h.dayNumber} está repetido.',
          row: h.rowIndex,
          col: h.exerciseCol,
          raw: cellOfHeader,
        );
      }
      if (i >= kMaxImportDays) {
        _error(
          ImportDiagnosticCode.tooManyDays,
          'Hay más de $kMaxImportDays días.',
          row: h.rowIndex,
          col: h.exerciseCol,
          raw: cellOfHeader,
        );
      }

      final rows = <PeriodizedRow>[];
      var lastNumber = 0;
      for (var r = h.rowIndex + 1; r < end; r++) {
        final name = _at(r, exerciseCol);
        if (name.isEmpty) continue; // sin nombre: se ignora, tenga lo que tenga
        namedRows++;
        final row = _parseRow(
          r,
          h.dayNumber,
          name,
          numberCol: numberCol,
          restCol: restCol,
          weekCols: weekCols,
          lastNumber: lastNumber,
        );
        if (row == null) continue;
        if (row.number != null) lastNumber = row.number!;
        rows.add(row);
      }
      days.add(PeriodizedDay(
        dayNumber: h.dayNumber,
        headerRow: h.rowIndex + 1,
        rows: rows,
      ));
    }

    if (namedRows == 0) {
      _error(
        ImportDiagnosticCode.noExercises,
        'El plan no tiene ningún ejercicio.',
      );
    }

    return PeriodizedParseResult(
      plan: PeriodizedPlan(numWeeks: numWeeks, days: days),
      diagnostics: _diags,
    );
  }

  /// Columnas SEMANA a partir del encabezado del DÍA 1: tienen que ser
  /// contiguas, y llamarse SEMANA 1, 2, 3… sin repetir.
  List<int> _weekColumns(_Header h, int restCol) {
    final width = _grid[h.rowIndex].length;
    final cols = <int>[];
    var c = restCol + 1;
    while (c < width) {
      final label = _at(h.rowIndex, c);
      final m = _weekHeaderRegex.firstMatch(label);
      if (m == null) break;
      final n = int.parse(m.group(1)!);
      if (n != cols.length + 1) {
        final seenBefore = n >= 1 && n <= cols.length;
        _error(
          seenBefore
              ? ImportDiagnosticCode.weekColumnsDuplicated
              : ImportDiagnosticCode.weekColumnsNotContiguous,
          seenBefore
              ? 'La columna "$label" está duplicada.'
              : 'Las semanas tienen que ir en orden: SEMANA ${cols.length + 1} '
                  'iba acá.',
          row: h.rowIndex,
          col: c,
          raw: label,
        );
      }
      cols.add(c);
      c++;
    }
    // Más etiquetas SEMANA después de un hueco: no contiguas (o repetidas).
    for (var k = c; k < width; k++) {
      final label = _at(h.rowIndex, k);
      final m = _weekHeaderRegex.firstMatch(label);
      if (m == null) continue;
      final n = int.parse(m.group(1)!);
      final dup = n >= 1 && n <= cols.length;
      _error(
        dup
            ? ImportDiagnosticCode.weekColumnsDuplicated
            : ImportDiagnosticCode.weekColumnsNotContiguous,
        dup
            ? 'La columna "$label" está duplicada.'
            : 'La columna "$label" no es contigua a las otras semanas.',
        row: h.rowIndex,
        col: k,
        raw: label,
      );
    }
    if (cols.isEmpty) {
      _error(
        ImportDiagnosticCode.notTemplate,
        'No encontramos columnas "SEMANA 1…" en el encabezado del DÍA 1.',
        row: h.rowIndex,
      );
    }
    if (cols.length > kMaxImportWeeks) {
      _error(
        ImportDiagnosticCode.tooManyWeeks,
        'Hay más de $kMaxImportWeeks semanas.',
        row: h.rowIndex,
        col: cols[kMaxImportWeeks],
        raw: _at(h.rowIndex, cols[kMaxImportWeeks]),
      );
    }
    return cols;
  }

  PeriodizedRow? _parseRow(
    int r,
    int dayNumber,
    String name, {
    required int numberCol,
    required int restCol,
    required List<int> weekCols,
    required int lastNumber,
  }) {
    final nameCol = numberCol + 1;
    var ok = true;

    // Nombres de la superserie.
    final names = name.split('+').map((s) => s.trim()).toList();
    if (names.any((n) => n.isEmpty)) {
      _error(
        ImportDiagnosticCode.emptyExerciseComponent,
        'Hay un "+" sin ejercicio de un lado.',
        row: r,
        col: nameCol,
        raw: name,
      );
      ok = false;
    }

    // N°: vacío = calentamiento.
    int? number;
    if (numberCol >= 0) {
      final rawNumber = _at(r, numberCol);
      if (rawNumber.isNotEmpty) {
        final parsed = int.tryParse(rawNumber) ??
            (double.tryParse(rawNumber.replaceAll(',', '.'))?.toInt());
        if (parsed == null || parsed < 1) {
          _error(
            ImportDiagnosticCode.invalidNumber,
            'El N° tiene que ser un entero desde 1, o quedar vacío para un '
            'calentamiento.',
            row: r,
            col: numberCol,
            raw: rawNumber,
          );
          ok = false;
        } else {
          number = parsed;
          if (parsed != lastNumber + 1) {
            _warn(
              ImportDiagnosticCode.numberingGap,
              'Numeración salteada o repetida: venía el ${lastNumber + 1}.',
              row: r,
              col: numberCol,
              raw: rawNumber,
            );
          }
        }
      }
    }
    final warmup = number == null;

    // Descanso.
    final rawRest = _at(r, restCol);
    final rest = parseRest(rawRest);
    if (!rest.isOk) {
      _error(ImportDiagnosticCode.invalidRest, rest.error!,
          row: r, col: restCol, raw: rawRest);
      ok = false;
    }

    if (!ok) {
      // Se siguen leyendo las celdas de semana para juntar TODOS los errores.
      if (names.every((n) => n.isNotEmpty)) {
        _parseWeeks(r, names, weekCols, warmup: number == null);
      }
      return null;
    }

    final weeks = _parseWeeks(r, names, weekCols, warmup: warmup);
    if (weeks == null) return null;

    final exercises = <PeriodizedExercise>[];
    for (var i = 0; i < names.length; i++) {
      final qualifiers = <String>[];
      for (final q in weeks.qualifiers[i]) {
        if (!qualifiers.contains(q)) qualifiers.add(q);
      }
      exercises.add(PeriodizedExercise(
        component: i,
        rawName: names[i],
        weeks: weeks.perComponent[i],
        note: qualifiers.isEmpty ? null : qualifiers.join(', '),
        emptyWeeks: weeks.emptyWeeks,
      ));
      _warnMixedKinds(r, nameCol, names[i], weeks.perComponent[i]);
    }

    return PeriodizedRow(
      excelRow: r + 1,
      number: number,
      restSeconds: rest.seconds!,
      exercises: exercises,
    );
  }

  /// Avisa si un ejercicio mezcla distancia, duración y/o reps entre semanas:
  /// el slot tiene UN solo modo, y las series de otro tipo quedan sin dato.
  void _warnMixedKinds(int r, int nameCol, String name, List<List<SetSpec>> w) {
    final kinds = <String>{};
    for (final week in w) {
      for (final s in week) {
        if ((s.distanceMeters ?? 0) > 0) {
          kinds.add('distancia');
        } else if ((s.durationSeconds ?? 0) > 0) {
          kinds.add('duración');
        } else if (s.reps != null) {
          kinds.add('reps');
        }
      }
    }
    if (kinds.length > 1) {
      _warn(
        ImportDiagnosticCode.mixedSetKinds,
        '"$name" mezcla ${kinds.join(' y ')} entre semanas; un ejercicio '
        'tiene un solo modo y las series del otro tipo quedan sin dato.',
        row: r,
        col: nameCol,
        raw: name,
      );
    }
  }

  _RowWeeks? _parseWeeks(
    int r,
    List<String> names,
    List<int> weekCols, {
    required bool warmup,
  }) {
    final perComponent = List.generate(names.length, (_) => <List<SetSpec>>[]);
    final qualifiers = List.generate(names.length, (_) => <String>[]);
    final emptyWeeks = <int>{};
    var failed = false;

    for (var w = 0; w < weekCols.length; w++) {
      final col = weekCols[w];
      final raw = _at(r, col);
      if (raw.isEmpty) {
        emptyWeeks.add(w);
        for (var i = 0; i < names.length; i++) {
          perComponent[i]
              .add([SetSpec(type: warmup ? SetType.warmup : SetType.normal)]);
        }
        _warn(
          ImportDiagnosticCode.missingReps,
          'Falta cargar reps en SEMANA ${w + 1}; '
          'el ejercicio va igual, sin reps.',
          row: r,
          col: col,
          raw: raw,
        );
        continue;
      }
      final cell = parseWeekCell(raw);
      if (!cell.isOk) {
        _error(ImportDiagnosticCode.unreadableCell, cell.error!,
            row: r, col: col, raw: raw);
        failed = true;
        continue;
      }
      if (cell.atoms.length != names.length) {
        _error(
          ImportDiagnosticCode.atomCountMismatch,
          'El renglón tiene ${names.length} '
          'ejercicio${names.length == 1 ? '' : 's'} y la celda '
          '${cell.atoms.length} '
          'valor${cell.atoms.length == 1 ? '' : 'es'}.',
          row: r,
          col: col,
          raw: raw,
        );
        failed = true;
        continue;
      }
      final expanded = expandAtoms(cell.atoms, warmup: warmup);
      var hadQualifier = false;
      for (var i = 0; i < names.length; i++) {
        perComponent[i].add(expanded[i]);
        final q = cell.atoms[i].qualifier;
        if (q != null) {
          qualifiers[i].add(q);
          hadQualifier = true;
        }
      }
      if (hadQualifier) {
        _warn(
          ImportDiagnosticCode.qualifierSavedAsNote,
          'El calificador se guarda como nota del ejercicio.',
          row: r,
          col: col,
          raw: raw,
        );
      }
    }
    if (failed) return null;
    return _RowWeeks(perComponent, qualifiers, emptyWeeks);
  }
}

class _RowWeeks {
  _RowWeeks(this.perComponent, this.qualifiers, this.emptyWeeks);
  final List<List<List<SetSpec>>> perComponent;
  final List<List<String>> qualifiers;
  final Set<int> emptyWeeks;
}
