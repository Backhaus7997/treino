import '../../../core/utils/argentina_time.dart';

/// Decay en lectura para la `rachaSemanas` denormalizada de
/// `userPublicProfiles` (#552, migrado a semanas 2026-09-02).
///
/// SEMÁNTICA: en todos lados donde la app muestra una "racha" quiere decir la
/// racha ACTUAL de hoy — el mismo valor que devuelve `computeWeeklyStreak`. El
/// campo guardado es una foto tomada la última vez que el atleta terminó un
/// entrenamiento: es exacto mientras la racha está viva, pero no decae solo.
/// Un atleta que dejó de entrenar se queda con su último valor para siempre, y
/// así fue como PERFIL (cálculo en vivo → 0) y RANKINGS (guardado, viejo → 1)
/// llegaron a contradecirse.
///
/// EL CAMBIO A SEMANAS MUEVE LA TOLERANCIA. Con la racha por día la ventana
/// era {hoy, ayer}: `computeStreak` tenía día de gracia, así que un valor
/// escrito ayer todavía era correcto hoy. Con la racha por semana la
/// contraparte exacta es {semana en curso, semana anterior}, porque
/// `computeWeeklyStreak` no deja que la semana en curso corte la racha:
///
/// - Sello de ESTA semana → el valor es de esta semana. Correcto.
/// - Sello de la semana PASADA → el atleta todavía no entrenó esta semana,
///   pero la semana en curso no rompe nada. El valor sigue siendo el correcto.
/// - Sello de 2+ semanas atrás → hubo al menos UNA semana completa cerrada sin
///   una sola sesión. Ninguna rutina tiene objetivo 0, así que esa semana no
///   se cumplió y la racha está muerta: 0.
///
/// Mantener la ventana en días acá habría puesto en cero, cada martes, la
/// racha de todo el que entrena lunes y jueves — el número correcto es el que
/// sobrevive el fin de semana.
///
/// [rachaSemanasUpdatedAt] es el instante en que se recalculó
/// [rachaSemanas], estampado por `UserPublicProfileRepository.updateCounters`
/// al terminar la sesión. Un sello `null` es un doc que nunca escribió el
/// campo nuevo: devolvemos 0, NO el valor crudo. Acá el default cambió a
/// propósito respecto de la versión por días — un `racha` viejo son DÍAS, y
/// dejarlo pasar como si fueran semanas pondría un 23 donde corresponde un 3.
/// Preferimos un cero honesto que se corrige solo la próxima vez que el
/// atleta entrena, antes que un número inflado en un board público. AGENTS.md
/// §11.1: una advertencia falsa es peor que ninguna.
///
/// NO hay backfill, y es a propósito. Recalcular esto server-side exige el
/// objetivo semanal del atleta, y ese sale de resolver cuál es su rutina
/// activa — una cadena de prioridad que ya vive dos veces (Dart y Swift,
/// fijada por `conformance/routine_selection.json`). Una tercera copia en un
/// script de Node, corriendo contra producción y escribiendo a un board
/// público, es más riesgo del que compra: el board converge solo dentro de la
/// semana para todo el que entrena, que es exactamente quién debería estar en
/// un board de rachas. Quien dejó de entrenar muestra 0, que bajo esta
/// semántica ES su valor correcto.
///
/// [now] es un instante REAL (cualquier flag) — se normaliza con `.toUtc()`
/// adentro, mismo contrato que `computeWeeklyStreak`. NO le pases
/// `argentinaNow()`.
int effectiveRachaSemanas({
  required int? rachaSemanas,
  required DateTime? rachaSemanasUpdatedAt,
  required DateTime now,
}) {
  if (rachaSemanas == null || rachaSemanasUpdatedAt == null) return 0;

  final currentWeek = mondayOfWeekArt(toArgentina(now.toUtc()));
  final stampWeek = mondayOfWeekArt(toArgentina(rachaSemanasUpdatedAt.toUtc()));

  final weeksOld = currentWeek.difference(stampWeek).inDays ~/ 7;
  // 0 = sellado esta semana, 1 = la semana pasada (la de gracia). Negativo =
  // el sello lee como "futuro" (el reloj del dispositivo atrasado respecto del
  // server timestamp que lo escribió) — se acaba de escribir, así que es
  // fresco por construcción.
  return weeksOld <= 1 ? rachaSemanas : 0;
}
