/// Etiquetas cortas de fecha (abreviaturas de mes, iniciales de día) derivadas
/// de los datos CLDR de `package:intl`, en vez de arrays hardcodeados por
/// feature. Reemplaza a los viejos `_monthsEs` / `_kMonths` / `_dayLabels`.
///
/// ## Por qué el output de intl se normaliza
///
/// El CLDR de es-AR no coincide con el diseño de TREINO en dos puntos. Ambos
/// están verificados contra `intl` 0.20, no asumidos:
///
/// - `DateFormat('MMM', 'es_AR')` devuelve `sept` (4 chars) para septiembre;
///   el resto de los meses da 3. El diseño asume 3 en ejes de charts y
///   headers, así que [monthAbbrev] trunca a 3.
/// - `DateFormat('EEEEE', 'es_AR')` devuelve `X` para miércoles, porque es-AR
///   hereda los narrow weekdays de España. El diseño usa la convención
///   latinoamericana `M`, así que [weekdayInitials] deriva la inicial del
///   nombre completo (`miércoles` → `M`) en lugar de usar el narrow.
///
/// `DateFormat('EEEEE', 'es_419')` sí devuelve `M`, pero NO es una salida
/// válida: en runtime sólo quedan registrados los símbolos del locale del
/// `MaterialApp`, y pedir `es_419` cae a un fallback silencioso que devuelve
/// minúsculas en vez de tirar error.
///
/// ## Contrato
///
/// Todas las funciones reciben `localeName` por parámetro y nunca leen
/// `AppL10n`, para que los widgets AppL10n-free (R3 — `DayStripNavigator`,
/// `WorkoutDaysCalendar`, `MonthlyReportChart`) puedan consumirlas vía sus
/// label bags. Pasar `AppL10n.of(context).localeName`.
///
/// Requieren que los símbolos del locale estén inicializados: alcanza con
/// tener `GlobalMaterialLocalizations` en el `MaterialApp` (registra el locale
/// activo). Sin eso `DateFormat` tira `LocaleDataException` — a tener en
/// cuenta en widget tests, que deben montar los delegates o inyectar las
/// etiquetas a mano.
library;

import 'package:intl/intl.dart' as intl;

/// 2024-01-01 fue lunes. Ancla arbitraria: sólo sirve para pedirle a intl los
/// 7 nombres de día en orden lunes→domingo. Se usa aritmética de calendario
/// (`DateTime(y, m, d + i)`) y no `add(Duration(days: i))` para no correrse
/// con los saltos de DST.
DateTime _referenceMonday(int offset) => DateTime(2024, 1, 1 + offset);

List<String> _fullWeekdayNames(String localeName) {
  final format = intl.DateFormat('EEEE', localeName);
  return [for (var i = 0; i < 7; i++) format.format(_referenceMonday(i))];
}

final _initialsCache = <String, List<String>>{};

/// Iniciales de día, lunes→domingo. En es-AR: `['L','M','M','J','V','S','D']`.
///
/// Indexar con `date.weekday - DateTime.monday`.
///
/// Martes y miércoles comparten `M` a propósito — es la convención del
/// diseño. Si necesitás distinguirlos, usá [weekdayDistinctAbbrevs].
List<String> weekdayInitials(String localeName) => _initialsCache.putIfAbsent(
      localeName,
      () => List<String>.unmodifiable([
        for (final name in _fullWeekdayNames(localeName))
          name.substring(0, 1).toUpperCase(),
      ]),
    );

final _distinctCache = <String, List<String>>{};

/// Abreviaturas de día sin colisión dentro de la semana, lunes→domingo.
/// En es-AR: `['L','Ma','Mi','J','V','S','D']`.
///
/// Cada día usa el prefijo más corto que no comparta con ningún otro día, así
/// que martes/miércoles se estiran a 2 letras y el resto queda en 1. Es la
/// versión legible del heatmap de adherencia, donde las 7 filas se leen en
/// vertical y dos `M` seguidas serían ambiguas.
List<String> weekdayDistinctAbbrevs(String localeName) =>
    _distinctCache.putIfAbsent(localeName, () {
      final names = _fullWeekdayNames(localeName);
      return List<String>.unmodifiable(
        [for (final name in names) _shortestDistinctPrefix(name, names)],
      );
    });

String _shortestDistinctPrefix(String name, List<String> all) {
  for (var length = 1; length < name.length; length++) {
    final prefix = name.substring(0, length).toLowerCase();
    final shared = all.where(
      (other) =>
          other.length >= length &&
          other.substring(0, length).toLowerCase() == prefix,
    );
    if (shared.length == 1) return _capitalize(name.substring(0, length));
  }
  return _capitalize(name);
}

String _capitalize(String value) =>
    value.substring(0, 1).toUpperCase() + value.substring(1);

final _monthsCache = <String, List<String>>{};

List<String> _monthAbbrevs(String localeName) => _monthsCache.putIfAbsent(
      localeName,
      () {
        final format = intl.DateFormat('MMM', localeName);
        return List<String>.unmodifiable([
          for (var month = 1; month <= 12; month++)
            _truncate(format.format(DateTime(2024, month))),
        ]);
      },
    );

String _truncate(String value) =>
    value.length > 3 ? value.substring(0, 3) : value;

/// Abreviatura de mes de 3 letras en el casing natural del locale (es-AR →
/// `abr`), o en mayúsculas con [upperCase] (`ABR`), como pide el diseño para
/// headings y ejes.
String monthAbbrev(
  DateTime date,
  String localeName, {
  bool upperCase = false,
}) {
  final abbrev = _monthAbbrevs(localeName)[date.month - 1];
  return upperCase ? abbrev.toUpperCase() : abbrev;
}
