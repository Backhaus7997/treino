/// Detección de franjas semanales superpuestas (#1495).
///
/// Dos reglas del mismo día de la semana se superponen cuando sus ventanas
/// `[inicio, fin)` comparten algún minuto. Son semiabiertas a propósito:
/// 09:00–11:00 y 11:00–13:00 NO se superponen (el turno de las 11:00 sólo
/// pertenece a la segunda), que es la forma natural de cargar una mañana en
/// dos tandas.
///
/// Una disponibilidad duplicada no es un matiz: `computeFreeSlots` junta los
/// turnos de todas las reglas del día en un `SplayTreeSet`, así que dos reglas
/// que se pisan publican turnos con la grilla de duración de cada una (30 y 60
/// min mezclados) y el alumno ve turnos que se pisan entre sí. Por eso acá es
/// un bloqueo, no un aviso.
library;

import 'availability_rule.dart';

/// `true` si `[aStart, aEnd)` y `[bStart, bEnd)` (minutos desde las 00:00)
/// comparten algún minuto.
bool minuteRangesOverlap(int aStart, int aEnd, int bStart, int bEnd) =>
    aStart < bEnd && bStart < aEnd;

/// La primera regla de [rules] que se superpone con la ventana
/// `[startMinutes, endMinutes)` del [dayOfWeek] (ISO, 1 = lunes), o `null`.
///
/// [ignoreRuleId] saca de la comparación a la regla que se está EDITANDO: no
/// puede chocar consigo misma.
AvailabilityRule? findOverlappingRule({
  required List<AvailabilityRule> rules,
  required int dayOfWeek,
  required int startMinutes,
  required int endMinutes,
  String? ignoreRuleId,
}) {
  for (final rule in rules) {
    if (rule.id == ignoreRuleId) continue;
    if (rule.dayOfWeek != dayOfWeek) continue;
    final ruleStart = rule.startHour * 60 + rule.startMinute;
    final ruleEnd = rule.endHour * 60 + rule.endMinute;
    if (minuteRangesOverlap(startMinutes, endMinutes, ruleStart, ruleEnd)) {
      return rule;
    }
  }
  return null;
}

/// Una ventana propuesta para una regla nueva.
typedef SuggestedRuleWindow = ({
  int dayOfWeek,
  int startMinutes,
  int endMinutes,
});

/// Largo de la ventana que propone [suggestFreeRuleWindow], en minutos.
const int kSuggestedRuleWindowMin = 120;

// Primera hora de inicio que se propone (09:00) y última (20:00, así la
// ventana de 2 h termina como tarde a las 22:00).
const int _kFirstStartHour = 9;
const int _kLastStartHour = 20;

/// La primera ventana de [kSuggestedRuleWindowMin] minutos que no pisa a
/// ninguna de [rules], recorriendo lunes→domingo y, dentro de cada día, desde
/// las 09:00 en horas en punto. Es el default del formulario "Agregar
/// horario": antes arrancaba siempre en "lunes 09–11", que chocaba apenas
/// había un horario cargado.
///
/// Si la semana no tiene lugar (todas las ventanas pisadas) devuelve el viejo
/// default, lunes 09–11: el formulario igual se abre y el guardado avisa.
SuggestedRuleWindow suggestFreeRuleWindow(List<AvailabilityRule> rules) {
  for (var day = DateTime.monday; day <= DateTime.sunday; day++) {
    for (var hour = _kFirstStartHour; hour <= _kLastStartHour; hour++) {
      final start = hour * 60;
      final end = start + kSuggestedRuleWindowMin;
      if (findOverlappingRule(
            rules: rules,
            dayOfWeek: day,
            startMinutes: start,
            endMinutes: end,
          ) ==
          null) {
        return (dayOfWeek: day, startMinutes: start, endMinutes: end);
      }
    }
  }
  return (
    dayOfWeek: DateTime.monday,
    startMinutes: _kFirstStartHour * 60,
    endMinutes: _kFirstStartHour * 60 + kSuggestedRuleWindowMin,
  );
}
