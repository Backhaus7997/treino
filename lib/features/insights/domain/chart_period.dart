import 'package:freezed_annotation/freezed_annotation.dart';

part 'chart_period.freezed.dart';

/// [AD7] The current + previous comparison window for a given
/// [ChartPeriod], expressed as calendar-day boundaries (time-of-day always
/// zeroed — see [ChartPeriod.windowFor] doc for the DST-safety rationale).
///
/// All 4 fields are INCLUSIVE start/end calendar days — callers filtering
/// sessions by `startedAt` should treat [currentEnd]/[previousEnd] as the
/// last valid calendar day (i.e. compare against the END of that day, or
/// simply `!isAfter(end)` when `start`/`end` are truncated to midnight and
/// the compared value may carry a time-of-day component).
@freezed
class ChartPeriodWindow with _$ChartPeriodWindow {
  const factory ChartPeriodWindow({
    required DateTime currentStart,
    required DateTime currentEnd,
    required DateTime previousStart,
    required DateTime previousEnd,
  }) = _ChartPeriodWindow;
}

/// [AD7] Selects the aggregation window for progression/radar charts.
///
/// - [last30d]: rolling 30-day window ending "today" — the DEFAULT for
///   exercise progression and muscle radar charts (not calendar-aligned).
/// - [thisWeek]: the calendar week (Monday..Sunday) containing "now".
/// - [month]: the calendar month containing "now".
/// - [last3m]: rolling 3 calendar months ending "today".
/// - [last1y]: rolling 12 calendar months ending "today".
///
/// ## Por qué NO hay un "todo el historial"
///
/// Porque hoy sería mentira. `sessionsByUidProvider` lee como mucho
/// `kSessionHistoryFetchLimit` (365) sesiones, así que un período "todo"
/// mostraría el último año largo y lo etiquetaría como la historia completa.
/// El propio `session_providers.dart` deja anotado que cargar historial más
/// viejo detrás de un cursor es un follow-up; hasta que exista, [last1y] es el
/// período más largo que se puede ofrecer sin afirmar algo que no se sabe.
///
/// ## Orden de las variantes
///
/// Las nuevas van al FINAL y no intercaladas por duración: el selector
/// renderiza `ChartPeriod.values` en orden, y reordenar movería de lugar las
/// pills que el usuario ya tiene aprendidas.
///
/// All window arithmetic uses `DateTime(year, month, day)` CALENDAR
/// CONSTRUCTOR math, never `.add(Duration(days: n))` — the latter can drift
/// across a DST transition (a local day is not always exactly 24h in zones
/// that observe DST). Argentina has not observed DST since 2009, but the
/// chart period selector is shared UI, so the arithmetic must be correct in
/// any timezone the app may run in.
enum ChartPeriod {
  last30d,
  thisWeek,
  month,
  last3m,
  last1y;

  /// The default period for exercise progression + muscle radar charts.
  static const ChartPeriod defaultPeriod = ChartPeriod.last30d;

  /// Derives the current+previous window quad for this period, anchored at
  /// [now]. Time-of-day components of [now] are ignored — only the calendar
  /// day is used.
  ChartPeriodWindow windowFor(DateTime now) {
    switch (this) {
      case ChartPeriod.last30d:
        return _last30dWindow(now);
      case ChartPeriod.thisWeek:
        return _thisWeekWindow(now);
      case ChartPeriod.month:
        return _monthWindow(now);
      case ChartPeriod.last3m:
        return _rollingMonthsWindow(now, 3);
      case ChartPeriod.last1y:
        return _rollingMonthsWindow(now, 12);
    }
  }
}

/// Rolling 30-day window: `[today - 29 days, today]` (30 calendar days
/// inclusive), previous window is the 30 days immediately preceding it
/// (non-overlapping — `previousEnd` is the day BEFORE `currentStart`, same
/// non-overlapping convention as [_thisWeekWindow]/[_monthWindow]).
ChartPeriodWindow _last30dWindow(DateTime now) {
  final today = DateTime.utc(now.year, now.month, now.day);
  final currentStart = DateTime.utc(today.year, today.month, today.day - 29);
  final previousEnd =
      DateTime.utc(currentStart.year, currentStart.month, currentStart.day - 1);
  final previousStart =
      DateTime.utc(previousEnd.year, previousEnd.month, previousEnd.day - 29);

  return ChartPeriodWindow(
    currentStart: currentStart,
    currentEnd: today,
    previousStart: previousStart,
    previousEnd: previousEnd,
  );
}

/// Ventana rodante de [months] meses calendario terminando HOY:
/// `[hoy - months meses + 1 día, hoy]`. La previa son los [months] meses
/// inmediatamente anteriores, sin solaparse (`previousEnd` es el día ANTERIOR
/// a `currentStart`), misma convención que las otras tres.
///
/// Se cuenta en MESES y no en días (90 / 365) a propósito: "3 meses" para el
/// usuario significa "de julio a septiembre", no "los últimos 90 días". La
/// aritmética con el constructor de calendario resuelve sola los meses de
/// distinto largo y el salto de año — `DateTime.utc(2026, 1 - 3, 15)` da
/// octubre de 2025.
///
/// El `+ 1 día` en `currentStart` hace la ventana INCLUSIVA de los dos lados:
/// sin él, un rango de 3 meses cubriría 3 meses y un día.
ChartPeriodWindow _rollingMonthsWindow(DateTime now, int months) {
  final today = DateTime.utc(now.year, now.month, now.day);
  final currentStart =
      DateTime.utc(today.year, today.month - months, today.day + 1);
  final previousEnd =
      DateTime.utc(currentStart.year, currentStart.month, currentStart.day - 1);
  final previousStart = DateTime.utc(
    previousEnd.year,
    previousEnd.month - months,
    previousEnd.day + 1,
  );

  return ChartPeriodWindow(
    currentStart: currentStart,
    currentEnd: today,
    previousStart: previousStart,
    previousEnd: previousEnd,
  );
}

/// Calendar week (Monday..Sunday) containing [now], previous window is the
/// preceding Monday..Sunday week.
ChartPeriodWindow _thisWeekWindow(DateTime now) {
  final today = DateTime.utc(now.year, now.month, now.day);
  final daysFromMonday = today.weekday - DateTime.monday;
  final currentStart =
      DateTime.utc(today.year, today.month, today.day - daysFromMonday);
  final currentEnd =
      DateTime.utc(currentStart.year, currentStart.month, currentStart.day + 6);
  final previousStart =
      DateTime.utc(currentStart.year, currentStart.month, currentStart.day - 7);
  final previousEnd =
      DateTime.utc(currentStart.year, currentStart.month, currentStart.day - 1);

  return ChartPeriodWindow(
    currentStart: currentStart,
    currentEnd: currentEnd,
    previousStart: previousStart,
    previousEnd: previousEnd,
  );
}

/// Calendar month containing [now], previous window is the immediately
/// preceding calendar month. Handles all month lengths (28/29/30/31 days)
/// and year rollover (January → previous December) via calendar-constructor
/// arithmetic: `DateTime(y, m+1, 0)` yields the last day of month `m`.
ChartPeriodWindow _monthWindow(DateTime now) {
  final currentStart = DateTime.utc(now.year, now.month, 1);
  // Day 0 of next month == last day of this month.
  final currentEnd = DateTime.utc(now.year, now.month + 1, 0);

  final previousStart = DateTime.utc(now.year, now.month - 1, 1);
  final previousEnd = DateTime.utc(now.year, now.month, 0);

  return ChartPeriodWindow(
    currentStart: currentStart,
    currentEnd: currentEnd,
    previousStart: previousStart,
    previousEnd: previousEnd,
  );
}
