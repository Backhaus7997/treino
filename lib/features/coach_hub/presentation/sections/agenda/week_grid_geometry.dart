// NOTE: el Scaffold y el SafeArea los provee CoachHubScaffold (el shell).
// NO los agregues acá (ADR-CHW-005).
//
// PR-A — Geometría pura de la grilla semanal de la Agenda web.
// Sin `package:flutter` acá a propósito: sólo dart:math + el modelo Appointment,
// para que la matemática (que es donde viven los bugs reales) se pueda testear
// con `test()` plano y no sólo a través de un WidgetTester con viewport forzado.
// Todas las strings están en español hardcodeado + comentario // i18n.
// NO se usa AppL10n en este archivo (constraint C-6).

import 'dart:math' as math;

import '../../../../coach/domain/appointment.dart';

// ── Constantes de layout ──────────────────────────────────────────────────────
// Espejan day_timeline.dart:17-21 para que mobile y web sean un solo sistema.

/// Alto de una hora completa, en px.
const double kWeekHourHeight = 64.0;

/// Px por minuto derivado de [kWeekHourHeight].
const double kWeekPxPerMin = kWeekHourHeight / 60.0;

/// Ancho de la canaleta izquierda con las etiquetas horarias.
const double kWeekGutter = 52.0;

/// Alto mínimo de un bloque para que el contenido siga siendo legible.
const double kWeekMinBlockH = 30.0;

/// Margen horizontal interno de cada columna-día.
const double kWeekColInset = 3.0;

/// Separación entre carriles (lanes) de sesiones superpuestas.
const double kWeekLaneGap = 2.0;

/// Granularidad del snapping al tocar una celda vacía, en minutos.
const int kWeekSnapMin = 15;

/// Último minuto del día al que se puede snappear: 23:45.
///
/// Sin este tope, un tap cerca del fondo de la grilla (p. ej. minuto 1435)
/// redondea a 1440 y produce un `TimeOfDay(hour: 24)` inválido, que revienta
/// al construir el diálogo de nueva sesión. Ojo: 1432 → 1425 NO ejercita el
/// tope; el caso real es ≥ 1432.5.
const int kWeekMaxSnapMin = 24 * 60 - kWeekSnapMin;

// ── Geometría ─────────────────────────────────────────────────────────────────

/// Conversión inmutable entre minutos del día y píxeles verticales de la
/// grilla semanal, más el ancho de columna ya resuelto por el `LayoutBuilder`.
///
/// [startHour] / [endHour] se calculan UNA sola vez para las siete columnas
/// (ver [weekHourRange]): rangos por día darían siete escalas verticales
/// distintas y las filas no alinearían.
class WeekGridGeometry {
  const WeekGridGeometry({
    required this.startHour,
    required this.endHour,
    required this.colWidth,
  });

  /// Primera hora visible de la grilla (0-23).
  final int startHour;

  /// Última hora visible de la grilla (1-24), exclusiva.
  final int endHour;

  /// Ancho de una columna-día, ya descontada la canaleta.
  final double colWidth;

  /// Alto total del lienzo scrolleable.
  double get contentHeight => (endHour - startHour) * 60 * kWeekPxPerMin;

  /// Offset vertical, en px, del minuto del día [minuteOfDay].
  double yForMinute(int minuteOfDay) =>
      (minuteOfDay - startHour * 60) * kWeekPxPerMin;

  /// Inverso de [yForMinute]: minuto del día en el offset vertical [y].
  double minuteAtY(double y) => startHour * 60 + y / kWeekPxPerMin;

  /// Redondea [minuteOfDay] al múltiplo de [kWeekSnapMin] más cercano y lo
  /// acota a `[0, kWeekMaxSnapMin]`.
  ///
  /// El snapping garantiza la precisión de minuto que asertea
  /// `Appointment.create` (ADR-7); el tope superior evita el
  /// `TimeOfDay(hour: 24)` inválido descrito en [kWeekMaxSnapMin].
  int snap(double minuteOfDay) {
    final rounded = (minuteOfDay / kWeekSnapMin).round() * kWeekSnapMin;
    return math.min(math.max(rounded, 0), kWeekMaxSnapMin);
  }
}

// ── Rango horario de la semana ────────────────────────────────────────────────

/// Rango horario que cubre las siete columnas de la semana.
///
/// Espeja day_timeline.dart:117-128 pero unificando los siete días: semilla
/// 07:00–22:00, se ensancha hacia arriba con la sesión más temprana y hacia
/// abajo con la que termina más tarde.
///
/// ADR-7: lee `startsAt.hour` / `.minute` en CRUDO (son wall-clock de
/// Argentina); un `.toLocal()` correría todo 3 horas.
({int startHour, int endHour}) weekHourRange(
  List<Appointment> weekAppointments,
) {
  int startHour = 7;
  int endHour = 22;

  for (final a in weekAppointments) {
    startHour = math.min(startHour, a.startsAt.hour);
    final endM = a.startsAt.hour * 60 + a.startsAt.minute + a.durationMin;
    endHour = math.max(endHour, (endM / 60).ceil());
  }

  startHour = startHour.clamp(0, 23);
  endHour = endHour.clamp(1, 24);
  // Defensivo: con la semilla 7..22 es inalcanzable, pero mantiene el
  // invariante endHour > startHour si alguna vez cambian las semillas.
  if (endHour <= startHour) endHour = startHour + 1;

  return (startHour: startHour, endHour: endHour);
}

// ── Inicio de semana ──────────────────────────────────────────────────────────

/// Lunes de la semana que contiene [anchor], a medianoche.
///
/// Arranca en lunes para coincidir con `spanishWeekdays`
/// (agenda_web_helpers.dart:28-36).
///
/// Siempre devuelve un [DateTime] UTC: el `operator==` de Dart incluye
/// `isUtc`, así que mezclar local y UTC rompe las comparaciones de día.
DateTime weekStartFor(DateTime anchor) {
  final d = DateTime.utc(anchor.year, anchor.month, anchor.day);
  return d.subtract(Duration(days: d.weekday - 1));
}
