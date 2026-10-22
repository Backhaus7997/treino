import '../../workout/domain/set_enums.dart';
import '../../workout/domain/set_limits.dart';
import '../../workout/domain/set_spec.dart';
import 'periodized_plan.dart';

/// Lee el `PdfPlanExtraction` que devuelve el callable `parsePlanPdf` y lo
/// convierte en un [PeriodizedPlan] (contrato: docs/plan-import-pdf.md).
///
/// El servidor ya valida contra los mismos topes, pero el cliente vuelve a
/// validar: lo que llega del LLM no se da por bueno. Ninguna violación tira:
/// cada una es un [ImportDiagnostic], igual que en el parser del Excel. Un
/// renglón con errores queda afuera del plan, y con cualquier error
/// [PeriodizedParseResult.canImport] da false.
///
/// Como el PDF no tiene filas, [PeriodizedRow.position] es el ordinal del
/// renglón en el día (base 1) y la ubicación va en el mensaje
/// (`Día 1, renglón 2, …`); sólo los avisos del extractor traen página.

/// Descanso máximo por renglón, en segundos.
const int kMaxPdfRestSeconds = 600;

/// Descanso cuando el extractor no lo informa: el mismo default que la celda
/// vacía del Excel (`kDefaultRestSeconds` de la gramática).
const int kPdfDefaultRestSeconds = 60;

/// Largo máximo de `sourceText`; lo que sobra se recorta.
const int kMaxSourceTextLength = 300;

PeriodizedParseResult periodizedPlanFromJson(Map<String, Object?> json) =>
    _PlanJsonReader().read(json);

/// Valor leído de un campo: [ok] es false si vino con un tipo que no es el
/// esperado (distinto de venir null).
typedef _Field<T> = ({bool ok, T? value});

class _PlanJsonReader {
  final _diagnostics = <ImportDiagnostic>[];

  int get _errorCount => _diagnostics.where((d) => d.isError).length;

  void _error(ImportDiagnosticCode code, String message, {Object? raw}) =>
      _diagnostics.add(ImportDiagnostic(
        severity: ImportDiagnosticSeverity.error,
        code: code,
        message: message,
        rawValue: raw?.toString(),
      ));

  void _warn(
    ImportDiagnosticCode code,
    String message, {
    int? page,
    Object? raw,
  }) =>
      _diagnostics.add(ImportDiagnostic(
        severity: ImportDiagnosticSeverity.warning,
        code: code,
        message: message,
        page: page,
        rawValue: raw?.toString(),
      ));

  PeriodizedParseResult _result(PeriodizedPlan? plan) =>
      PeriodizedParseResult(plan: plan, diagnostics: _diagnostics);

  PeriodizedParseResult read(Map<String, Object?> json) {
    _readExtractorWarnings(json['warnings']);

    final numWeeks = _int(json['numWeeks']);
    if (!numWeeks.ok || numWeeks.value == null) {
      _error(
          ImportDiagnosticCode.malformedPlan, 'Falta la cantidad de semanas.',
          raw: json['numWeeks']);
      return _result(null);
    }
    final weeks = numWeeks.value!;
    if (weeks < 1 || weeks > kMaxImportWeeks) {
      _error(
        ImportDiagnosticCode.tooManyWeeks,
        'El plan tiene que tener entre 1 y $kMaxImportWeeks semanas.',
        raw: weeks,
      );
      return _result(null);
    }

    final rawDays = json['days'];
    if (rawDays is! List) {
      _error(ImportDiagnosticCode.malformedPlan, 'Faltan los días del plan.');
      return _result(null);
    }
    if (rawDays.length > kMaxImportDays) {
      _error(
        ImportDiagnosticCode.tooManyDays,
        'Hay más de $kMaxImportDays días.',
        raw: rawDays.length,
      );
    }

    final days = <PeriodizedDay>[];
    final seen = <int>{};
    for (var i = 0; i < rawDays.length; i++) {
      final day = _readDay(i, rawDays[i], weeks, seen);
      if (day != null) days.add(day);
    }
    days.sort((a, b) => a.dayNumber.compareTo(b.dayNumber));

    if (_errorCount == 0 && days.every((d) => d.rows.isEmpty)) {
      _error(ImportDiagnosticCode.noExercises, 'No encontramos ejercicios.');
    }
    return _result(PeriodizedPlan(numWeeks: weeks, days: days));
  }

  void _readExtractorWarnings(Object? raw) {
    if (raw == null) return;
    if (raw is! List) {
      _error(
          ImportDiagnosticCode.malformedPlan, 'Los avisos no son una lista.');
      return;
    }
    for (final w in raw) {
      if (w is! Map) continue;
      final message = w['message'];
      if (message is! String || message.trim().isEmpty) continue;
      final page = _int(w['page']);
      _warn(
        ImportDiagnosticCode.extractorWarning,
        message.trim(),
        page: page.ok ? page.value : null,
        raw: w['code'],
      );
    }
  }

  PeriodizedDay? _readDay(int index, Object? raw, int weeks, Set<int> seen) {
    if (raw is! Map) {
      _error(ImportDiagnosticCode.malformedPlan,
          'El día ${index + 1} no tiene la forma esperada.');
      return null;
    }
    final number = _int(raw['dayNumber']);
    if (!number.ok || number.value == null) {
      _error(ImportDiagnosticCode.malformedPlan,
          'Al día ${index + 1} le falta el número.',
          raw: raw['dayNumber']);
      return null;
    }
    final dayNumber = number.value!;
    if (dayNumber < 1 || dayNumber > kMaxImportDays) {
      _error(
        ImportDiagnosticCode.invalidDayNumber,
        'El número de día tiene que estar entre 1 y $kMaxImportDays.',
        raw: dayNumber,
      );
      return null;
    }
    if (!seen.add(dayNumber)) {
      _error(ImportDiagnosticCode.duplicatedDay,
          'El día $dayNumber aparece más de una vez.',
          raw: dayNumber);
      return null;
    }
    final rawRows = raw['rows'];
    if (rawRows is! List) {
      _error(ImportDiagnosticCode.malformedPlan,
          'Al día $dayNumber le faltan los renglones.');
      return null;
    }
    final rows = <PeriodizedRow>[];
    for (var j = 0; j < rawRows.length; j++) {
      final row = _readRow(
          'Día $dayNumber, renglón ${j + 1}', j + 1, rawRows[j], weeks);
      if (row != null) rows.add(row);
    }
    return PeriodizedDay(dayNumber: dayNumber, rows: rows);
  }

  PeriodizedRow? _readRow(String where, int position, Object? raw, int weeks) {
    if (raw is! Map) {
      _error(ImportDiagnosticCode.malformedPlan,
          '$where: no tiene la forma esperada.');
      return null;
    }
    final errorsBefore = _errorCount;

    final number = _int(raw['number']);
    if (!number.ok || (number.value != null && number.value! < 1)) {
      _error(ImportDiagnosticCode.invalidNumber,
          '$where: el N° tiene que ser un entero desde 1, o vacío.',
          raw: raw['number']);
    }

    final rest = _int(raw['restSeconds']);
    if (!rest.ok ||
        (rest.value != null &&
            (rest.value! < 0 || rest.value! > kMaxPdfRestSeconds))) {
      _error(
        ImportDiagnosticCode.invalidRest,
        '$where: el descanso tiene que estar entre 0 y $kMaxPdfRestSeconds s.',
        raw: raw['restSeconds'],
      );
    }

    final rawExercises = raw['exercises'];
    if (rawExercises is! List || rawExercises.isEmpty) {
      _error(
          ImportDiagnosticCode.malformedPlan, '$where: no tiene ejercicios.');
      return null;
    }
    final exercises = <PeriodizedExercise>[];
    for (final e in rawExercises) {
      final ex = _readExercise(where, e, weeks);
      if (ex != null) exercises.add(ex);
    }
    exercises.sort((a, b) => a.component.compareTo(b.component));
    // `component` viene 1..n; el dominio lo usa 0..n-1.
    final components = exercises.map((e) => e.component).toList();
    final expected = [for (var c = 0; c < rawExercises.length; c++) c];
    if (exercises.length == rawExercises.length &&
        components.join(',') != expected.join(',')) {
      _error(
        ImportDiagnosticCode.invalidComponent,
        '$where: los ejercicios de la superserie tienen que ir numerados de 1 '
        'a ${rawExercises.length}.',
        raw: components.map((c) => c + 1).join(', '),
      );
    }

    if (_errorCount > errorsBefore) return null;
    return PeriodizedRow(
      position: position,
      number: number.value,
      restSeconds: rest.value ?? kPdfDefaultRestSeconds,
      exercises: exercises,
    );
  }

  PeriodizedExercise? _readExercise(String row, Object? raw, int weeks) {
    if (raw is! Map) {
      _error(ImportDiagnosticCode.malformedPlan,
          '$row: un ejercicio no tiene la forma esperada.');
      return null;
    }
    final errorsBefore = _errorCount;

    final rawName = raw['rawName'];
    final name = rawName is String ? rawName.trim() : '';
    final where = name.isEmpty ? row : '$row, «$name»';
    if (name.isEmpty) {
      _error(ImportDiagnosticCode.emptyExerciseComponent,
          '$row: un ejercicio no tiene nombre.');
    }

    final component = _int(raw['component']);
    if (!component.ok || component.value == null || component.value! < 1) {
      _error(ImportDiagnosticCode.invalidComponent,
          '$where: falta el orden dentro del renglón.',
          raw: raw['component']);
    }

    final rawWeeks = raw['weeks'];
    final parsedWeeks = <List<SetSpec>>[];
    final emptyWeeks = <int>{};
    if (rawWeeks is! List) {
      _error(ImportDiagnosticCode.malformedPlan, '$where: faltan las semanas.');
    } else if (rawWeeks.length != weeks) {
      _error(
        ImportDiagnosticCode.weekCountMismatch,
        '$where: tiene ${rawWeeks.length} semanas y el plan tiene $weeks.',
        raw: rawWeeks.length,
      );
    } else {
      for (var w = 0; w < rawWeeks.length; w++) {
        final week = rawWeeks[w];
        if (week is! List) {
          _error(ImportDiagnosticCode.malformedPlan,
              '$where, semana ${w + 1}: no es una lista de series.');
          continue;
        }
        // Semana sin carga: como la celda vacía del Excel, una serie sin
        // valores que la vista previa marca en rojo.
        if (week.isEmpty) {
          emptyWeeks.add(w);
          parsedWeeks.add(const [SetSpec()]);
          continue;
        }
        final sets = <SetSpec>[];
        for (var s = 0; s < week.length; s++) {
          final set =
              _readSet('$where, semana ${w + 1}, serie ${s + 1}', week[s]);
          if (set != null) sets.add(set);
        }
        parsedWeeks.add(sets);
      }
    }

    if (_errorCount > errorsBefore) return null;

    final note = raw['note'];
    final candidate = _candidate(
        where, raw['candidateExerciseId'], raw['candidateConfidence']);
    return PeriodizedExercise(
      component: component.value! - 1,
      rawName: name,
      weeks: parsedWeeks,
      note: note is String && note.trim().isNotEmpty ? note.trim() : null,
      emptyWeeks: emptyWeeks,
      sourceText: _sourceText(where, raw['sourceText']),
      candidateExerciseId: candidate.id,
      candidateConfidence: candidate.confidence,
    );
  }

  String? _sourceText(String where, Object? raw) {
    if (raw == null) return null;
    if (raw is! String) {
      _warn(ImportDiagnosticCode.invalidOptionalField,
          '$where: se descartó el texto fuente.');
      return null;
    }
    final text = raw.trim();
    if (text.isEmpty) return null;
    return text.length > kMaxSourceTextLength
        ? text.substring(0, kMaxSourceTextLength)
        : text;
  }

  SetSpec? _readSet(String where, Object? raw) {
    if (raw is! Map) {
      _error(ImportDiagnosticCode.malformedPlan,
          '$where: no tiene la forma esperada.');
      return null;
    }
    final errorsBefore = _errorCount;

    final rawType = raw['type'];
    final type = rawType == null
        ? SetType.normal
        : SetType.values.where((t) => t.name == rawType).firstOrNull;
    if (type == null) {
      _error(
        ImportDiagnosticCode.invalidSetType,
        '$where: el tipo de serie tiene que ser '
        '${SetType.values.map((t) => t.name).join(', ')}.',
        raw: rawType,
      );
    }

    final weight = _num(raw['weightKg']);
    if (!weight.ok ||
        (weight.value != null &&
            (weight.value! < 0 || weight.value! > kMaxWeightKg))) {
      _error(
        ImportDiagnosticCode.invalidWeight,
        '$where: el peso tiene que estar entre 0 y ${kMaxWeightKg.toInt()} kg.',
        raw: raw['weightKg'],
      );
    }

    final reps = _repsField(where, 'reps', raw['reps']);
    final repsMin = _repsField(where, 'el mínimo de reps', raw['repsMin']);
    final repsMax = _repsField(where, 'el máximo de reps', raw['repsMax']);
    final hasRange = repsMin != null || repsMax != null;
    if (reps != null && hasRange) {
      _error(ImportDiagnosticCode.invalidReps,
          '$where: van reps fijas o un rango, no las dos cosas.');
    } else if (hasRange && (repsMin == null || repsMax == null)) {
      _error(ImportDiagnosticCode.invalidReps,
          '$where: el rango necesita mínimo y máximo.');
    } else if (hasRange && repsMin! > repsMax!) {
      _error(ImportDiagnosticCode.invalidReps,
          '$where: el mínimo de reps es mayor que el máximo.',
          raw: '$repsMin-$repsMax');
    }

    final duration = _int(raw['durationSeconds']);
    if (!duration.ok || (duration.value != null && duration.value! <= 0)) {
      _error(ImportDiagnosticCode.invalidNumber,
          '$where: la duración tiene que ser un entero positivo de segundos.',
          raw: raw['durationSeconds']);
    }
    final distance = _num(raw['distanceMeters']);
    if (!distance.ok || (distance.value != null && distance.value! <= 0)) {
      _error(ImportDiagnosticCode.invalidNumber,
          '$where: la distancia tiene que ser positiva.',
          raw: raw['distanceMeters']);
    }

    if (_errorCount > errorsBefore) return null;
    return SetSpec(
      type: type!,
      weightKg: weight.value,
      reps: reps,
      repsMin: repsMin,
      repsMax: repsMax,
      durationSeconds: duration.value,
      distanceMeters: distance.value,
    );
  }

  /// Un campo de reps: null si no vino; error si no es un entero de 1 a
  /// [kMaxReps].
  int? _repsField(String where, String label, Object? raw) {
    final v = _int(raw);
    if (!v.ok || (v.value != null && (v.value! < 1 || v.value! > kMaxReps))) {
      _error(ImportDiagnosticCode.invalidReps,
          '$where: $label tiene que ser un entero de 1 a $kMaxReps.',
          raw: raw);
      return null;
    }
    return v.value;
  }

  /// Candidato del catálogo propuesto por el extractor. Si la confianza no es
  /// un número de 0 a 1 se descarta entero (con aviso): no bloquea el import.
  ({String? id, double? confidence}) _candidate(
    String where,
    Object? id,
    Object? confidence,
  ) {
    const none = (id: null, confidence: null);
    if (id == null) return none;
    final conf = _num(confidence);
    if (id is! String ||
        id.trim().isEmpty ||
        !conf.ok ||
        (conf.value != null && (conf.value! < 0 || conf.value! > 1))) {
      _warn(ImportDiagnosticCode.invalidOptionalField,
          '$where: se descartó el ejercicio sugerido por el lector.',
          raw: id);
      return none;
    }
    return (id: id.trim(), confidence: conf.value);
  }
}

_Field<int> _int(Object? v) {
  if (v == null) return (ok: true, value: null);
  if (v is int) return (ok: true, value: v);
  if (v is double && v.isFinite && v == v.truncateToDouble()) {
    return (ok: true, value: v.toInt());
  }
  return (ok: false, value: null);
}

_Field<double> _num(Object? v) {
  if (v == null) return (ok: true, value: null);
  if (v is num && v.isFinite) return (ok: true, value: v.toDouble());
  return (ok: false, value: null);
}
