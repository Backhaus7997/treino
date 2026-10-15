import '../../workout/domain/set_enums.dart';
import '../../workout/domain/set_spec.dart';

/// Gramática de la celda de semana y del descanso del Excel periodizado
/// (spec: docs/plan-import-excel-periodizado.md, "Celda de semana" y
/// "Descanso"). Funciones puras: no saben de hojas ni de filas.

/// Tope de renglones del producto, sólo para validar series razonables.
const int kMaxSeriesPerAtom = 99;

enum AtomKind { reps, failure, duration, distance }

/// Un átomo ya leído: `[series x] objetivo [calificador]`.
class WeekAtom {
  const WeekAtom({
    required this.kind,
    required this.value,
    this.series,
    this.qualifier,
  });

  final AtomKind kind;

  /// reps (entero), minutos o metros según [kind]; 0 para `max`.
  final double value;

  /// Series declaradas en el átomo; null si no trae `NxR`.
  final int? series;

  /// `c/pierna`, `c/brazo` o `c/lado`.
  final String? qualifier;
}

/// Resultado de leer una celda: átomos o el motivo del fallo.
class WeekCellParse {
  const WeekCellParse.ok(this.atoms) : error = null;
  const WeekCellParse.fail(this.error) : atoms = const [];

  final List<WeekAtom> atoms;
  final String? error;
  bool get isOk => error == null;
}

/// Sin espacios, en minúscula y con las comillas tipográficas unificadas.
String normalizeGrammar(String raw) => raw
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), '')
    .replaceAll(RegExp('[’‘´`′]'), "'")
    .replaceAll('"', "''")
    .replaceAll('″', "''")
    .replaceAll('×', 'x');

final RegExp _atomRegex = RegExp(
  r"^(?:(\d+)x)?(?:(max)|(\d+(?:[.,]\d+)?)m|(\d+(?:[.,]\d+)?)'|(\d+))"
  r'(c/(?:pierna|brazo|lado))?$',
);

double _num(String s) => double.parse(s.replaceAll(',', '.'));

/// Lee una celda de semana NO vacía en una lista de átomos.
WeekCellParse parseWeekCell(String raw) {
  final normalized = normalizeGrammar(raw);
  if (normalized.isEmpty) {
    return const WeekCellParse.fail('La celda está vacía.');
  }
  final atoms = <WeekAtom>[];
  for (final part in normalized.split('+')) {
    if (part.isEmpty) {
      return const WeekCellParse.fail('Hay un "+" sin nada de un lado.');
    }
    final m = _atomRegex.firstMatch(part);
    if (m == null) {
      return WeekCellParse.fail('No se entiende "$part".');
    }
    final series = m.group(1) == null ? null : int.parse(m.group(1)!);
    if (series != null && (series < 1 || series > kMaxSeriesPerAtom)) {
      return WeekCellParse.fail(
        'Las series tienen que estar entre 1 y $kMaxSeriesPerAtom '
        '(en "$part").',
      );
    }
    final qualifier = m.group(6);
    if (m.group(2) != null) {
      atoms.add(WeekAtom(
        kind: AtomKind.failure,
        value: 0,
        series: series,
        qualifier: qualifier,
      ));
    } else if (m.group(3) != null) {
      final v = _num(m.group(3)!);
      if (v <= 0) {
        return WeekCellParse.fail('Los metros deben ser > 0 ("$part").');
      }
      atoms.add(WeekAtom(
        kind: AtomKind.distance,
        value: v,
        series: series,
        qualifier: qualifier,
      ));
    } else if (m.group(4) != null) {
      final v = _num(m.group(4)!);
      if (v <= 0) {
        return WeekCellParse.fail('Los minutos deben ser > 0 ("$part").');
      }
      atoms.add(WeekAtom(
        kind: AtomKind.duration,
        value: v,
        series: series,
        qualifier: qualifier,
      ));
    } else {
      final v = int.parse(m.group(5)!);
      if (v < 1) {
        return WeekCellParse.fail('Las reps deben ser >= 1 ("$part").');
      }
      atoms.add(WeekAtom(
        kind: AtomKind.reps,
        value: v.toDouble(),
        series: series,
        qualifier: qualifier,
      ));
    }
  }
  return WeekCellParse.ok(atoms);
}

/// Convierte los átomos de UNA celda en las series de cada componente
/// (`result[i]` = series del ejercicio i). Las series del PRIMER átomo se
/// propagan a los átomos que no traen las suyas; si tampoco las trae, un
/// tiempo, una distancia o unas reps sueltas son 1 serie. [warmup] fuerza
/// `SetType.warmup` en todas.
List<List<SetSpec>> expandAtoms(List<WeekAtom> atoms, {required bool warmup}) {
  final inherited = atoms.first.series;
  return [
    for (final atom in atoms)
      List<SetSpec>.generate(
        atom.series ?? inherited ?? 1,
        (_) => _specFor(atom, warmup: warmup),
        growable: false,
      ),
  ];
}

SetSpec _specFor(WeekAtom atom, {required bool warmup}) {
  final type = warmup
      ? SetType.warmup
      : (atom.kind == AtomKind.failure ? SetType.failure : SetType.normal);
  return switch (atom.kind) {
    AtomKind.reps => SetSpec(type: type, reps: atom.value.round()),
    AtomKind.failure => SetSpec(type: type),
    AtomKind.duration =>
      SetSpec(type: type, durationSeconds: (atom.value * 60).round()),
    AtomKind.distance => SetSpec(type: type, distanceMeters: atom.value),
  };
}

/// Resultado de leer la columna DESCANSOS.
class RestParse {
  const RestParse.ok(this.seconds) : error = null;
  const RestParse.fail(this.error) : seconds = null;
  final int? seconds;
  final String? error;
  bool get isOk => error == null;
}

/// Descanso por defecto cuando la celda viene vacía.
const int kDefaultRestSeconds = 60;

final RegExp _restSeconds = RegExp(r"^(\d+)(?:'')?$");
final RegExp _restMinutes = RegExp(r"^(\d+)'$");
final RegExp _restMinSec = RegExp(r"^(\d+)'(\d{1,2})(?:'')?$");

/// `90` = 90 s; `1'` = 60 s; `1'30` o `1'30''` = 90 s; `90''` = 90 s;
/// vacío = 60 s.
RestParse parseRest(String raw) {
  final s = normalizeGrammar(raw);
  if (s.isEmpty) return const RestParse.ok(kDefaultRestSeconds);
  var m = _restSeconds.firstMatch(s);
  if (m != null) return RestParse.ok(int.parse(m.group(1)!));
  m = _restMinutes.firstMatch(s);
  if (m != null) return RestParse.ok(int.parse(m.group(1)!) * 60);
  m = _restMinSec.firstMatch(s);
  if (m != null) {
    final secs = int.parse(m.group(2)!);
    if (secs < 60) return RestParse.ok(int.parse(m.group(1)!) * 60 + secs);
  }
  return const RestParse.fail(
    'Descanso ilegible. Usá segundos (90), minutos (1\') o 1\'30.',
  );
}
