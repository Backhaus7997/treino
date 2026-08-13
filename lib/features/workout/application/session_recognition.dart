import '../../../core/utils/argentina_time.dart';
import '../../insights/application/insights_providers.dart' show mondayOfWeek;
import '../domain/session.dart';

/// Tipo de reconocimiento data-driven del resumen post-entreno: UNA frase de
/// celebración elegida por reglas simples sobre datos que ya están en memoria
/// (récords recién calculados + lista de sesiones ya fetcheada). Sin nuevas
/// lecturas de Firestore.
enum SessionRecognitionKind {
  /// La sesión logró ≥1 récord personal (ver `aggregateSessionHighlights`).
  records,

  /// Primera sesión completada de la historia del atleta.
  firstWorkout,

  /// Mayor `totalVolumeKg` del mes calendario (ART) hasta esta sesión.
  bestMonthVolume,

  /// 2ª+ sesión de la semana calendario (ART, lunes a domingo).
  nthSessionOfWeek,

  /// Nada para destacar — la pantalla no muestra banner.
  none,
}

/// [count] solo es significativo para [SessionRecognitionKind.records]
/// (cantidad de récords) y [SessionRecognitionKind.nthSessionOfWeek] (número
/// ordinal de la sesión en la semana). Para el resto queda en 0.
typedef SessionRecognition = ({SessionRecognitionKind kind, int count});

const SessionRecognition noRecognition = (
  kind: SessionRecognitionKind.none,
  count: 0,
);

/// Deriva el reconocimiento de la sesión — pure fn, sin Riverpod, testeable.
///
/// Prioridad: récords > primer entreno > mejor volumen del mes > Nª sesión de
/// la semana > nada. Una sola frase, no una pila: el resumen celebra LO más
/// notable, no todo a la vez.
///
/// Reglas de honestidad (pedido explícito: "sin números inventados"):
/// - Una sesión que no cuenta como entreno (#372: abandonada/en curso) no
///   celebra nada.
/// - Solo compara contra sesiones ANTERIORES a esta (`startedAt` no
///   posterior, excluyéndose por id): ver el resumen de una sesión vieja
///   describe lo que era cierto AL completarla, no el presente.
/// - "Mejor volumen del mes" exige ≥1 sesión previa ese mes y superarlas
///   ESTRICTAMENTE (empatar tu marca no es batirla) — mes calendario ART,
///   mismo criterio de bucket que el resto de Insights.
/// - "Nª sesión de la semana" recién aparece con n ≥ 2 (celebrar la "1ª" es
///   ruido) — semana lunes-domingo ART vía [mondayOfWeek].
///
/// [sessionsDesc] es la historia fetcheada (puede incluir a [session]; se
/// filtra por id). El fetch upstream está acotado (`kSessionHistoryFetchLimit`),
/// así que las reglas de mes/semana siempre ven la ventana que necesitan.
SessionRecognition deriveSessionRecognition({
  required Session session,
  required List<Session> sessionsDesc,
  required int recordCount,
}) {
  if (!session.countsAsWorkout) return noRecognition;

  if (recordCount > 0) {
    return (kind: SessionRecognitionKind.records, count: recordCount);
  }

  final prior = sessionsDesc
      .where((s) =>
          s.id != session.id &&
          s.countsAsWorkout &&
          !s.startedAt.isAfter(session.startedAt))
      .toList();
  if (prior.isEmpty) {
    return (kind: SessionRecognitionKind.firstWorkout, count: 0);
  }

  final art = toArgentina(session.startedAt);

  final priorInMonth = prior.where((s) {
    final a = toArgentina(s.startedAt);
    return a.year == art.year && a.month == art.month;
  }).toList();
  if (priorInMonth.isNotEmpty &&
      session.totalVolumeKg > 0 &&
      priorInMonth.every((s) => s.totalVolumeKg < session.totalVolumeKg)) {
    return (kind: SessionRecognitionKind.bestMonthVolume, count: 0);
  }

  final weekStart = mondayOfWeek(art);
  final nthOfWeek = 1 +
      prior
          .where((s) => mondayOfWeek(toArgentina(s.startedAt))
              .isAtSameMomentAs(weekStart))
          .length;
  if (nthOfWeek >= 2) {
    return (kind: SessionRecognitionKind.nthSessionOfWeek, count: nthOfWeek);
  }

  return noRecognition;
}
