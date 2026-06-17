import 'package:treino/features/measurements/domain/measurement.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';

/// ¿La sesión cuenta como entrenamiento real?
///
/// Una sesión ABANDONADA se persiste con `status == finished` pero
/// `wasFullyCompleted == false`. Todas las superficies que muestran o cuentan
/// sesiones (historial del atleta, contadores públicos, este resumen y el tab
/// Entrenamientos) deben aplicar el mismo filtro para no divergir.
bool isCompletedSession(Session s) =>
    s.status == SessionStatus.finished && s.wasFullyCompleted;

/// Métricas del tab «Resumen» del detalle de alumno (Fase W2 PR4).
///
/// Cálculo PURO y testeable: no toca Flutter ni providers, recibe `now`
/// inyectable para tests deterministas. Sólo deriva de data ya
/// trainer-readable (`sessionsByUidProvider`, `measurementsForAthleteProvider`
/// y los días del plan activo). Las piezas que dependen de `setLogs`
/// (owner-only en firestore.rules), datos personales privados, notas o
/// scheduling se difieren a PRs siguientes.
class ResumenMetrics {
  const ResumenMetrics({
    required this.adherencia30dPct,
    required this.adherenciaDeltaPts,
    required this.sesionesPorSemana,
    required this.weeklyTarget,
    required this.volumenSemanaActualKg,
    required this.volumenDeltaPct,
    required this.pesoActualKg,
    required this.pesoDelta30dKg,
    required this.heatmap,
  });

  /// Adherencia de los últimos 30 días (0..∞ %, sin tope). `null` si no hay
  /// plan activo (sin objetivo semanal no hay denominador).
  final double? adherencia30dPct;

  /// Variación en puntos porcentuales vs los 30 días previos. `null` sin plan.
  final double? adherenciaDeltaPts;

  /// Promedio de sesiones/semana sobre las últimas 4 semanas.
  final double sesionesPorSemana;

  /// Sesiones/semana que prescribe el plan activo (= días de la rutina).
  /// `0` cuando no hay plan activo.
  final int weeklyTarget;

  /// Volumen (kg) sumado en los últimos 7 días.
  final double volumenSemanaActualKg;

  /// Variación porcentual del volumen vs la semana previa. `null` si la semana
  /// previa fue 0 (no se puede dividir).
  final double? volumenDeltaPct;

  /// Peso corporal más reciente (kg). `null` si no hay mediciones con peso.
  final double? pesoActualKg;

  /// Variación de peso (kg) en ~30 días. `null` si no hay dos mediciones
  /// comparables.
  final double? pesoDelta30dKg;

  /// Grilla 12 semanas × 7 días (lunes→domingo) con nivel de intensidad 0..4
  /// según la cantidad de sesiones COMPLETADAS ese día (adherencia = presencia,
  /// no volumen: una sesión sin carga igual cuenta como "entrenó"). Semana 0 =
  /// la más vieja; semana 11 = la actual. Día 0 = lunes.
  final List<List<int>> heatmap;

  factory ResumenMetrics.compute({
    required List<Session> sessions,
    required List<Measurement> measurements,
    required int weeklyTarget,
    required DateTime now,
  }) {
    final completed = sessions.where(isCompletedSession).toList();

    // ── Adherencia: ventanas de 30 días, actual vs previa ──────────────────
    final d30 = now.subtract(const Duration(days: 30));
    final d60 = now.subtract(const Duration(days: 60));
    final c30 = _countInWindow(completed, from: d30, to: now);
    final cPrev = _countInWindow(completed, from: d60, to: d30);

    double? adherencia;
    double? adherenciaDelta;
    if (weeklyTarget > 0) {
      final planned = weeklyTarget * 30 / 7;
      adherencia = c30 / planned * 100;
      adherenciaDelta = adherencia - (cPrev / planned * 100);
    }

    // ── Sesiones/semana: promedio sobre 4 semanas ──────────────────────────
    const weeksWindow = 4;
    final cWindow = _countInWindow(
      completed,
      from: now.subtract(const Duration(days: 7 * weeksWindow)),
      to: now,
    );
    final sesionesPorSemana = cWindow / weeksWindow;

    // ── Volumen: semana actual vs previa ───────────────────────────────────
    final w1 = now.subtract(const Duration(days: 7));
    final w2 = now.subtract(const Duration(days: 14));
    final volNow = _volumeInWindow(completed, from: w1, to: now);
    final volPrev = _volumeInWindow(completed, from: w2, to: w1);
    final volumenDelta =
        volPrev > 0 ? (volNow - volPrev) / volPrev * 100 : null;

    return ResumenMetrics(
      adherencia30dPct: adherencia,
      adherenciaDeltaPts: adherenciaDelta,
      sesionesPorSemana: sesionesPorSemana,
      weeklyTarget: weeklyTarget,
      volumenSemanaActualKg: volNow,
      volumenDeltaPct: volumenDelta,
      pesoActualKg: _lastWeight(measurements),
      pesoDelta30dKg: _weightDelta30d(measurements, now: now),
      heatmap: _buildHeatmap(completed, now: now),
    );
  }
}

// ── Helpers puros ────────────────────────────────────────────────────────────

/// Sesiones cuyo `finishedAt` cae en `[from, to)`.
int _countInWindow(
  List<Session> completed, {
  required DateTime from,
  required DateTime to,
}) =>
    completed.where((s) {
      final d = s.finishedAt;
      return d != null && !d.isBefore(from) && d.isBefore(to);
    }).length;

double _volumeInWindow(
  List<Session> completed, {
  required DateTime from,
  required DateTime to,
}) =>
    completed.where((s) {
      final d = s.finishedAt;
      return d != null && !d.isBefore(from) && d.isBefore(to);
    }).fold(0.0, (sum, s) => sum + s.totalVolumeKg);

/// Último peso no-null. `measurements` viene ascendente (recordedAt).
double? _lastWeight(List<Measurement> measurements) {
  for (final m in measurements.reversed) {
    if (m.weightKg != null) return m.weightKg;
  }
  return null;
}

/// Delta de peso (kg) en ~30 días: peso actual menos la medición de referencia
/// (la última registrada ≤ now-30d; si todas son más nuevas, la más vieja).
double? _weightDelta30d(List<Measurement> measurements,
    {required DateTime now}) {
  final withWeight =
      measurements.where((m) => m.weightKg != null).toList(); // ascendente
  if (withWeight.length < 2) return null;

  final latest = withWeight.last;
  final cutoff = now.subtract(const Duration(days: 30));
  Measurement? ref;
  for (final m in withWeight) {
    if (!m.recordedAt.isAfter(cutoff)) ref = m; // última ≤ cutoff
  }
  ref ??= withWeight.first; // todas dentro de 30d → la más vieja
  if (identical(ref, latest)) return null;
  return latest.weightKg! - ref.weightKg!;
}

/// 12×7 niveles 0..4 por cantidad de sesiones del día, normalizados al máximo
/// de la grilla (presencia/adherencia, no volumen).
List<List<int>> _buildHeatmap(List<Session> completed,
    {required DateTime now}) {
  // `now` puede llegar en hora LOCAL (DateTime.now() en producción) mientras
  // que `finishedAt` siempre es UTC. Normalizamos ambos a fecha-UTC: si no, en
  // es-AR (UTC-3) una sesión de la tarde cae al día UTC siguiente y se correría
  // de columna (o se descartaría en el borde de la grilla). Trabajar siempre en
  // UTC hace el bucketing independiente del huso, para cualquier caller.
  final nowUtc = now.toUtc();
  final today = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
  final mondayThisWeek = today.subtract(Duration(days: today.weekday - 1));
  final gridStart = mondayThisWeek.subtract(const Duration(days: 7 * 11));
  final gridEnd = mondayThisWeek.add(const Duration(days: 7)); // exclusivo

  final counts = List.generate(12, (_) => List<int>.filled(7, 0));
  for (final s in completed) {
    final d = s.finishedAt;
    if (d == null) continue;
    final day = DateTime.utc(d.year, d.month, d.day);
    if (day.isBefore(gridStart) || !day.isBefore(gridEnd)) continue;
    final diff = day.difference(gridStart).inDays;
    final week = diff ~/ 7;
    final dow = diff % 7; // gridStart es lunes → 0 = lunes
    if (week < 0 || week > 11) continue;
    counts[week][dow] += 1;
  }

  var maxCount = 0;
  for (final week in counts) {
    for (final c in week) {
      if (c > maxCount) maxCount = c;
    }
  }

  return [
    for (final week in counts)
      [
        for (final c in week)
          if (c <= 0)
            0
          else if (maxCount <= 0)
            1
          else
            (c / maxCount * 4).ceil().clamp(1, 4),
      ],
  ];
}
