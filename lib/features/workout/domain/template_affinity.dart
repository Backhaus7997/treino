import 'muscle_group.dart';
import 'routine.dart';
import 'template_preferences.dart';

/// Afinidad entre una plantilla y lo que el atleta respondió en el
/// mini-onboarding de PLANTILLAS (#635 PR#3).
///
/// ## Ordena, NUNCA excluye
///
/// El catálogo del sistema son 7 plantillas. Cruzar cuatro dimensiones sobre 7
/// ítems da vacío en la mayoría de las combinaciones: *2 días · 30 min ·
/// deporte · tren superior* no matchea ninguna, porque el mínimo del catálogo
/// son 3 días y 45 minutos. Un filtro duro dejaría la grilla en cero y el
/// atleta sin saber por qué.
///
/// Por eso esto devuelve un puntaje para ORDENAR. Toda plantilla sigue
/// visible; lo que cambia es cuál se ve primero.
///
/// ## "Sin dato" es NEUTRO, y esa es la decisión central
///
/// Cada dimensión devuelve `[0, 1]`, y la ausencia de dato —de cualquiera de
/// los dos lados— vale [neutral] = `0.5`. No es un promedio caprichoso: es lo
/// que define el orden entre tres casos que hay que distinguir.
///
///   1.0  la plantilla dice "estética" y el atleta busca estética
///   0.5  la plantilla no declara objetivo
///   0.0  la plantilla dice "deporte" y el atleta busca estética
///
/// Un match real gana. Un desajuste real pierde. Y lo que no tiene dato queda
/// en el medio: no se premia, pero tampoco se hunde debajo de algo que
/// activamente no le sirve.
///
/// Esto no es cosmético. `communityTemplatesProvider` trae todo lo que
/// publicó cualquier PF, y **toda plantilla publicada antes de #635 llega sin
/// `goals`**. Si "sin dato" valiera 0, el catálogo entero de la comunidad se
/// hundiría al fondo de la grilla el día del deploy. Con 0.5 convive.
///
/// Lo mismo con `estimatedMinutesPerDay`, que es nullable: las 7 sembradas lo
/// tienen cargado, pero nada obliga a las de PF.
///
/// ## Las cuatro dimensiones pesan igual
///
/// Deliberado, y revisable: no hay evidencia todavía de que una importe más.
/// Las 5 entrevistas que originaron el issue dicen que la gente elige por
/// "cuánto puede darle y para qué", lo que sugiere que días y objetivo pesan
/// más que zonas — pero sugerir no es medir. Cuando haya datos de uso, los
/// pesos van acá y en un solo lugar.
abstract final class TemplateAffinity {
  /// Puntaje de una dimensión sin dato suficiente para opinar.
  static const double neutral = 0.5;

  /// Afinidad total en `[0, 1]`. Más alto = se muestra antes.
  ///
  /// Con preferencias vacías todas las plantillas dan [neutral], así que el
  /// orden queda como venía: un atleta que saltó el cuestionario ve la grilla
  /// sin tocar.
  static double score(Routine routine, TemplatePreferences preferences) {
    if (preferences.isEmpty) return neutral;
    final parts = <double>[
      _daysScore(routine, preferences.daysPerWeek),
      _minutesScore(routine, preferences.minutesPerSession),
      _goalScore(routine, preferences),
      _zonesScore(routine, preferences.priorityGroups),
    ];
    return parts.reduce((a, b) => a + b) / parts.length;
  }

  /// Días por semana. Se deriva de `days.length`, que siempre está.
  ///
  /// Decae con la distancia en vez de ser todo-o-nada: para quien pide 3 días,
  /// una de 4 es mucho mejor candidata que una de 6, y un booleano las
  /// empataría. Un día de diferencia conserva 2/3 del puntaje; a partir de
  /// tres, cero.
  static double _daysScore(Routine routine, int? wanted) {
    if (wanted == null || wanted <= 0) return neutral;
    final days = routine.days.length;
    if (days == 0) return neutral; // rutina sin días: nada que comparar
    final gap = (days - wanted).abs();
    return gap >= 3 ? 0 : 1 - (gap / 3);
  }

  /// Minutos por sesión. Nullable en el modelo, así que la ausencia es
  /// esperable y neutra.
  ///
  /// La tolerancia asimétrica es a propósito: **pasarse de tiempo penaliza más
  /// que sobrar**. Quien dice "tengo 30 minutos" tiene 30; una sesión de 60 no
  /// le entra. Al revés, quien tiene 60 y encuentra una de 45 simplemente
  /// termina antes.
  static double _minutesScore(Routine routine, int? wanted) {
    if (wanted == null || wanted <= 0) return neutral;
    final minutes = routine.estimatedMinutesPerDay;
    if (minutes == null || minutes <= 0) return neutral;
    final diff = minutes - wanted;
    // 20 min de margen cuando la sesión es más corta, 10 cuando es más larga.
    final tolerance = diff <= 0 ? 20 : 10;
    final gap = diff.abs() / tolerance;
    return gap >= 1 ? 0 : 1 - gap;
  }

  /// Objetivo. Multi-valor del lado de la plantilla: alcanza con que UNO
  /// coincida, porque una Full Body que sirve a salud y a estética le sirve
  /// entera a quien busca cualquiera de las dos.
  static double _goalScore(Routine routine, TemplatePreferences preferences) {
    final wanted = preferences.goal;
    if (wanted == null) return neutral;
    if (routine.goals.isEmpty) return neutral; // publicada antes de #635
    return routine.goals.contains(wanted) ? 1 : 0;
  }

  /// Zonas priorizadas, contra las que la plantilla DERIVA de sus slots
  /// (#635 PR#1). Nunca es null, pero puede venir vacía.
  ///
  /// Mitad COBERTURA, mitad ÉNFASIS:
  ///
  ///   * Cobertura: de las zonas pedidas, cuántas trabaja la plantilla. Pedir
  ///     "glúteos" y que la plantilla los toque cuenta, aunque además trabaje
  ///     otras seis cosas — castigar la amplitud hundiría a las Full Body.
  ///   * Énfasis: qué parte de sus ejercicios va a lo pedido. Sin esto, con un
  ///     catálogo donde casi todo toca piernas, una PPL con una sentadilla y una
  ///     plantilla de glúteos empataban para quien pidió glúteos. Se satura en
  ///     [_enfasisPleno]: si la mitad de los ejercicios van a lo pedido, la
  ///     plantilla ya lo prioriza y no hace falta que sea monotemática.
  ///
  /// `cuerpoCompleto` vale MEDIO en las dos. Antes un solo ejercicio global
  /// —un peso muerto, un swing— le daba 1 a la plantilla para cualquier zona
  /// pedida, y como 40 de las 50 del catálogo tienen al menos uno, las zonas
  /// no discriminaban nada. Medio es lo que es: el ejercicio trabaja la zona,
  /// pero no la prioriza.
  static double _zonesScore(Routine routine, List<MuscleGroup> wanted) {
    if (wanted.isEmpty) return neutral;
    final counts = <MuscleGroup, int>{};
    var total = 0;
    for (final day in routine.days) {
      for (final slot in day.slots) {
        final group = MuscleGroup.fromKey(slot.muscleGroup);
        if (group == null) continue;
        counts[group] = (counts[group] ?? 0) + 1;
        total++;
      }
    }
    if (total == 0) return neutral; // rutina sin slots
    final pedidas = wanted.toSet();
    final global = pedidas.contains(MuscleGroup.cuerpoCompleto)
        ? 0
        : counts[MuscleGroup.cuerpoCompleto] ?? 0;

    final cobertura = pedidas
            .map((z) => (counts[z] ?? 0) > 0 ? 1.0 : (global > 0 ? 0.5 : 0.0))
            .reduce((a, b) => a + b) /
        pedidas.length;
    final aLoPedido =
        pedidas.map((z) => counts[z] ?? 0).reduce((a, b) => a + b) +
            global * 0.5;
    final enfasis = (aLoPedido / total / _enfasisPleno).clamp(0.0, 1.0);
    return (cobertura + enfasis) / 2;
  }

  /// Proporción de ejercicios dedicados a las zonas pedidas a partir de la
  /// cual el énfasis ya vale 1.
  static const double _enfasisPleno = 0.5;
}
