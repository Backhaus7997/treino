import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/utils/chart_point_index.dart';
import '../../../../core/utils/date_labels.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../checkins/domain/check_in.dart';
import '../../../checkins/presentation/wellbeing_check_in_sheet.dart'
    show feelingLabel;
import '../../domain/wellbeing_trend.dart';

/// La curva de "cómo me sentí" en el tiempo.
///
/// El eje Y es la escala de 5 niveles, no una magnitud: va fijo de 0 a 4 y
/// rotula con las MISMAS etiquetas del sheet de captura. Un eje autoescalado
/// mentiría —haría ver una montaña donde el usuario se movió entre "bien" y
/// "muy bien"— que es exactamente el tipo de énfasis que este feature no puede
/// permitirse sobre dato de salud.
///
/// Los días con dolor se marcan con un punto distinto sobre la misma curva.
/// Es una MARCA, no un juicio: dice qué días el usuario reportó dolor, y nada
/// más. No hay color de alarma, ni umbral, ni línea de referencia.
///
/// El caller garantiza [kWellbeingTrendMinPoints] puntos: con uno solo no hay
/// tendencia que dibujar y el mensaje correcto es otro.
class WellbeingTrendChart extends StatelessWidget {
  const WellbeingTrendChart({super.key, required this.points});

  final List<WellbeingTrendPoint> points;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final localeName = l10n.localeName;

    final spots = <FlSpot>[
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].feelingLevel),
    ];
    final labelIndices = _labelIndices(points.length);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.border),
      ),
      child: SizedBox(
        height: 180,
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: (points.length - 1).toDouble(),
            // Escala fija 0..4 con medio nivel de aire arriba y abajo, para que
            // un punto en el extremo no quede pisando el borde del cuadro.
            minY: -0.5,
            maxY: 4.5,
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                color: palette.accent,
                barWidth: 2.5,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, bar, index) {
                    final hadPain = points[index].hadPain;
                    // Días con dolor: punto hueco y más grande. Se distingue
                    // por FORMA y no sólo por color — la diferencia tiene que
                    // sobrevivir a un daltonismo y a una captura en gris.
                    return FlDotCirclePainter(
                      radius: hadPain ? 5 : 3.5,
                      color: hadPain ? palette.bgCard : palette.accent,
                      strokeWidth: hadPain ? 2 : 0,
                      strokeColor: palette.accent,
                    );
                  },
                ),
                belowBarData: BarAreaData(
                  show: true,
                  color: palette.accent.withValues(alpha: 0.12),
                ),
              ),
            ],
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  // El eje X es índice-de-punto: sin interval fijo, fl_chart
                  // samplea Xs fraccionarias y value.round() duplica o saltea
                  // etiquetas de fecha (#554, #383).
                  interval: 1,
                  getTitlesWidget: (value, meta) {
                    final idx = exactPointIndex(value);
                    if (idx == null || !labelIndices.contains(idx)) {
                      return const SizedBox.shrink();
                    }
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(
                        _shortDate(points[idx].date, localeName),
                        style: GoogleFonts.barlowCondensed(
                          fontSize: 10,
                          color: palette.textMuted,
                        ),
                      ),
                    );
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 62,
                  interval: 1,
                  getTitlesWidget: (value, meta) {
                    final level = value.round();
                    if (level < 0 ||
                        level >= CheckInFeeling.displayOrder.length ||
                        (value - level).abs() > 0.01) {
                      return const SizedBox.shrink();
                    }
                    // Sólo los extremos: rotular los 5 niveles llena el eje de
                    // texto y tapa la curva en pantalla chica.
                    if (level != 0 &&
                        level != CheckInFeeling.displayOrder.length - 1) {
                      return const SizedBox.shrink();
                    }
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(
                        feelingLabel(
                          l10n,
                          CheckInFeeling.displayOrder[level],
                        ),
                        style: GoogleFonts.barlowCondensed(
                          fontSize: 10,
                          color: palette.textMuted,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            gridData: FlGridData(
              show: true,
              drawHorizontalLine: true,
              drawVerticalLine: false,
              horizontalInterval: 1,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: palette.border, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            lineTouchData: LineTouchData(
              handleBuiltInTouches: true,
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => palette.bgCard,
                tooltipBorder: BorderSide(color: palette.border),
                tooltipBorderRadius: BorderRadius.circular(8),
                getTooltipItems: (spots) => [
                  for (final s in spots)
                    LineTooltipItem(
                      _tooltipText(l10n, points[s.spotIndex], localeName),
                      GoogleFonts.barlow(
                        fontSize: 12,
                        color: palette.textPrimary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Etiqueta del tooltip: fecha + nivel más cercano, y la marca de dolor si la
/// hubo. Enuncia lo registrado; no agrega ninguna lectura.
String _tooltipText(
  AppL10n l10n,
  WellbeingTrendPoint point,
  String localeName,
) {
  final level = point.feelingLevel
      .round()
      .clamp(0, CheckInFeeling.displayOrder.length - 1);
  final label = feelingLabel(l10n, CheckInFeeling.displayOrder[level]);
  final date = _shortDate(point.date, localeName);
  return point.hadPain
      ? '$date · $label · ${l10n.wellbeingTrendPainMark}'
      : '$date · $label';
}

/// `YYYY-MM-DD` → "18 may". La clave de fecha ya está en el día del usuario:
/// se parsea como fecha local y no se vuelve a convertir de zona.
String _shortDate(String dateKey, String localeName) {
  final parts = dateKey.split('-');
  if (parts.length != 3) return dateKey;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return dateKey;
  final date = DateTime(y, m, d);
  return '${date.day} ${monthAbbrev(date, localeName)}';
}

/// Como mucho 5 etiquetas en el eje X, repartidas parejo. Con 30 días, rotular
/// todos deja una tira ilegible.
Set<int> _labelIndices(int length) {
  if (length <= 5) return {for (var i = 0; i < length; i++) i};
  const wanted = 5;
  final step = (length - 1) / (wanted - 1);
  return {for (var i = 0; i < wanted; i++) (i * step).round()};
}
