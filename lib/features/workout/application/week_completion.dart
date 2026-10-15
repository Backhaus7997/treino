import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/app_clock.dart';
import '../../../core/utils/argentina_time.dart';
import '../../../core/utils/weekly_streak_calculator.dart';
import '../../home/application/todays_routine_provider.dart';
import '../domain/session.dart';
import 'session_providers.dart';

/// La sesión del resumen fue la que cumplió el objetivo de la semana en curso.
///
/// [streak] es la racha semanal que queda DESPUÉS de esta sesión (>= 1): la
/// semana que acaba de cumplirse más las semanas consecutivas cumplidas hacia
/// atrás. Con 1 es la primera semana cumplida de una corrida.
typedef WeekCompletion = ({int streak});

/// Decide si el resumen post-entreno de [session] felicita con "Semana
/// cumplida" — pure fn, sin Riverpod, testeable.
///
/// Devuelve `null` (no se felicita) salvo que se cumplan las TRES a la vez:
///
/// 1. La sesión cuenta como entreno ([Session.countsAsWorkout], #372): una
///    abandonada o en curso no cumple nada.
/// 2. Es la sesión que hace que las que cuentan de SU semana ART
///    (lunes-domingo, vía [mondayOfWeekArt]) lleguen EXACTAMENTE a
///    [weeklyTarget]. Las extra, después de cumplido el objetivo, tienen que
///    contar más y no igual, así que no felicitan de nuevo. Y una sesión que
///    queda por debajo todavía no cumplió nada.
/// 3. Su semana es la semana EN CURSO. El botón de la tarjeta abre Insights, que
///    siempre arranca en la semana actual (no hay forma de pedirle otra), así
///    que felicitar una semana vieja mandaría a ver los datos de otra: la
///    tarjeta diría "cumpliste esta semana" y el botón mostraría una semana
///    distinta. Lo que no se puede mostrar de forma coherente no se muestra.
///
/// Reglas de honestidad — las mismas de [deriveSessionRecognition]:
/// - Solo cuenta sesiones ANTERIORES o iguales a esta (`startedAt` no
///   posterior), excluyéndose por id: ver el resumen de una sesión vieja
///   describe lo que era cierto AL completarla, no el presente.
/// - [sessionsDesc] puede incluir o no a [session]: el fetch upstream se hace
///   al abrir el resumen y puede llegar antes de que la sesión recién cerrada
///   esté en la lista. Por eso [session] se cuenta aparte y se filtra por id,
///   y la racha se calcula con ella agregada explícitamente.
/// - El borde de semana es ART, NO la timezone del dispositivo ni UTC: una
///   sesión del domingo 23:30 ART es lunes en UTC.
///
/// [weeklyTarget] es el objetivo de la rutina activa (ver
/// [weeklyTargetFromRoutine]). Un valor <= 0 cae en
/// [weeklyStreakFallbackTarget], igual que [weeklyStreakOf]: con cero toda
/// sesión "cumpliría" la semana.
///
/// [now] es un instante REAL (cualquier flag) — NO le pases `argentinaNow()`.
/// Omitirlo cae en [AppClock.now], mismo contrato que [weeklyStreakOf].
WeekCompletion? deriveWeekCompletion({
  required Session session,
  required List<Session> sessionsDesc,
  required int weeklyTarget,
  DateTime? now,
}) {
  if (!session.countsAsWorkout) return null;

  final target = weeklyTarget > 0 ? weeklyTarget : weeklyStreakFallbackTarget;
  final instant = (now ?? AppClock.now()).toUtc();

  final sessionWeek = mondayOfWeekArt(toArgentina(session.startedAt.toUtc()));
  final currentWeek = mondayOfWeekArt(toArgentina(instant));
  if (!sessionWeek.isAtSameMomentAs(currentWeek)) return null;

  // Esta sesión + las anteriores que cuentan de la misma semana.
  final upToThisSession = 1 +
      sessionsDesc
          .where((s) =>
              s.id != session.id &&
              s.countsAsWorkout &&
              !s.startedAt.isAfter(session.startedAt) &&
              mondayOfWeekArt(toArgentina(s.startedAt.toUtc()))
                  .isAtSameMomentAs(sessionWeek))
          .length;
  if (upToThisSession != target) return null;

  // La racha incluye a esta sesión aunque la lista todavía no la traiga: sin
  // eso, un fetch que llegó antes del cierre contaría una semana de menos y la
  // tarjeta diría una racha más corta que la de Home.
  final streak = weeklyStreakOf(
    sessions: [
      session,
      for (final s in sessionsDesc)
        if (s.id != session.id) s,
    ],
    weeklyTarget: target,
    now: instant,
  ).streak;

  return (streak: streak);
}

/// La felicitación "Semana cumplida" de la sesión del resumen, o `null`.
///
/// Reusa lo que el resumen ya tiene en memoria — el mismo [sessionSummaryProvider]
/// y el mismo [sessionsByUidProvider] que [sessionHighlightsProvider], con la
/// misma key — y el objetivo semanal de la rutina activa. Cero lecturas nuevas
/// de Firestore. Best-effort, como los demás slots async de la pantalla: si algo
/// falla o todavía carga, no hay tarjeta; nunca bloquea ni rompe el resumen.
///
/// El objetivo se espera de [todaysRoutineProvider] y NO se lee de
/// `weeklyStreakTargetProvider`: ese devuelve [weeklyStreakFallbackTarget] (1)
/// MIENTRAS la rutina carga — razonable para una racha que "se corrige sola",
/// pero acá es una trampa. El provider de la rutina es autoDispose, así que en
/// el resumen puede arrancar frío: un atleta de 3 días que cierra su primera
/// sesión de la semana vería un instante "¡Semana cumplida!" contra un objetivo
/// de 1 que después se corrige a 3. Una felicitación falsa, aunque dure un
/// frame, es peor que ninguna.
final sessionWeekCompletionProvider = FutureProvider.autoDispose
    .family<WeekCompletion?, ({String uid, String sessionId})>(
        (ref, key) async {
  if (key.uid.isEmpty) return null;

  // Los tres watch antes de cualquier await (un `ref` usado tras un async gap
  // es inseguro si el provider se recomputa a mitad de vuelo), y en paralelo.
  final summaryFuture = ref.watch(sessionSummaryProvider(key).future);
  final sessionsFuture = ref.watch(sessionsByUidProvider(key.uid).future);
  final routineFuture = ref.watch(todaysRoutineProvider.future);
  final (summary, sessions, todaysRoutine) =
      await (summaryFuture, sessionsFuture, routineFuture).wait;

  final session = summary.session;
  if (session == null) return null;

  return deriveWeekCompletion(
    session: session,
    sessionsDesc: sessions,
    weeklyTarget: weeklyTargetFromRoutine(todaysRoutine?.routine),
  );
});
