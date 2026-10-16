/// Hora de arranque que propone el formulario "Nueva sesión" (#1490).
///
/// Antes el default era "hoy a las 9:00" a ciegas: pasadas las 9, el PF abría el
/// formulario con una hora que el propio submit rechaza ("No podés registrar una
/// sesión en el pasado"). Esta función devuelve una propuesta que NUNCA cae en el
/// pasado:
///
///  * si las 9:00 de [day] todavía no pasaron (o [day] es un día futuro), se
///    conserva el default de siempre;
///  * si ya pasaron, se propone la próxima hora en punto;
///  * si esa hora ya cae al día siguiente (23:xx), se propone mañana a las 9:00.
///
/// Todo es wall-clock ADR-7 (ver `wall_clock.dart`): [nowWall] y el resultado
/// son `DateTime.utc` con los campos del calendario local, sin conversión.
library;

/// Hora default del formulario cuando todavía no pasó.
const int kDefaultSessionHour = 9;

/// Devuelve `(fecha, hora, minuto)` propuestos para una sesión nueva en [day].
///
/// [day] se toma sólo por su día de calendario (se ignora la hora).
/// [nowWall] es "ahora" en wall-clock (`nowWall()` de `wall_clock.dart`).
({DateTime date, int hour, int minute}) defaultSessionStart({
  required DateTime day,
  required DateTime nowWall,
}) {
  final date = DateTime.utc(day.year, day.month, day.day);
  final nine =
      DateTime.utc(date.year, date.month, date.day, kDefaultSessionHour);
  if (nine.isAfter(nowWall)) {
    return (date: date, hour: kDefaultSessionHour, minute: 0);
  }

  // Las 9:00 ya pasaron, así que [day] es hoy (el 9:00 de un día futuro siempre
  // es posterior a ahora; uno anterior el date picker no deja elegirlo).
  final today = DateTime.utc(nowWall.year, nowWall.month, nowWall.day);
  final nextHour = nowWall.hour + 1;
  if (nextHour < 24) {
    return (date: today, hour: nextHour, minute: 0);
  }

  // 23:xx → la próxima hora en punto ya es mañana: mañana a las 9:00.
  return (
    date: today.add(const Duration(days: 1)),
    hour: kDefaultSessionHour,
    minute: 0,
  );
}
