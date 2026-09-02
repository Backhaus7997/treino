/// Argentina wall-clock helpers.
///
/// Argentina (America/Argentina/Buenos_Aires) has observed UTC-3 year-round
/// with NO daylight saving since 2009, so a constant offset is correct and the
/// Dart client stays byte-identical with the Cloud Functions.
///
/// CALENDAR concepts — payment period keys, "today"/day buckets, month/week
/// boundaries — MUST be derived in ART, not UTC: between 21:00–23:59 ART the
/// UTC day is already tomorrow, so UTC-day math mis-buckets (a session finished
/// at 23:00 ART lands on "today", though in UTC it is already tomorrow).
/// INSTANTS (createdAt, paidAt, "has it ended yet") stay in true UTC — only the
/// calendar identity shifts.
library;

import 'package:treino/core/utils/app_clock.dart';

/// Argentina's fixed UTC offset (UTC-3, no DST).
const argentinaUtcOffset = Duration(hours: 3);

/// Shifts a UTC instant into Argentina wall-clock: the returned [DateTime] is
/// still UTC-flagged, but its calendar fields (year/month/day/weekday) read as
/// ART. Pass a UTC instant (e.g. `x.toUtc()`).
DateTime toArgentina(DateTime utc) => utc.subtract(argentinaUtcOffset);

/// "Now" in Argentina wall-clock. Derive period keys and day buckets from this,
/// never `DateTime.now().toUtc()`.
///
/// Reads the clock through [AppClock] so a test can freeze it — see
/// `lib/core/utils/app_clock.dart`. In production it is `DateTime.now()`.
DateTime argentinaNow() => toArgentina(AppClock.now().toUtc());

/// Lunes 00:00 del frame ART de la semana que contiene [now].
///
/// [now] ya debe estar en wall-clock argentino (típicamente `argentinaNow()` o
/// `toArgentina(instante)`) — esta función NO convierte, sólo trunca al borde
/// de semana. El resultado queda UTC-flagged para vivir en el mismo frame que
/// [toArgentina], igual que el resto de los buckets de calendario.
///
/// Semana lunes-domingo: es el borde que ya usan el selector de semana de
/// Insights, `session_recognition` y la racha semanal. La resta de días va por
/// el constructor de calendario (no `subtract`) para normalizar el borde a
/// medianoche sin arrastrar la hora del día.
///
/// Canónica acá y no en `insights_providers.dart` porque `core/utils` no puede
/// depender de una feature: `computeWeeklyStreak` la necesita. El
/// `mondayOfWeek` de Insights delega en ésta y sigue siendo el punto de import
/// de todo lo que ya lo usaba.
DateTime mondayOfWeekArt(DateTime now) {
  final daysFromMonday = now.weekday - DateTime.monday;
  return DateTime.utc(now.year, now.month, now.day - daysFromMonday);
}
