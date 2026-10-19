import 'muscle_group.dart';
import 'routine.dart';
import 'template_preferences.dart';

/// Afinidad entre una plantilla y lo que el atleta respondió en el
/// mini-onboarding de PLANTILLAS (#635 PR#3).
///
/// ## Qué FILTRA y qué sólo ORDENA (#1561)
///
/// Decisión de producto (owner, 2026-10): **días y minutos son filtro duro**;
/// **objetivo y zonas siguen siendo sólo orden**.
///
///   * Días por semana: coincidencia EXACTA con `days.length`. Quien elige 3
///     días no ve una Bro Split de 5: la UI presenta estas respuestas como
///     filtro ("AJUSTAR", "3 días/sem · 75 min") y que no filtraran era un bug.
///   * Minutos por sesión: tolerancia de ±[minutesTolerance]. `75` significa
///     "75 o más" (la última opción del cuestionario), así que no tiene techo.
///   * "Sin dato" NO es desajuste: una plantilla sin `estimatedMinutesPerDay`
///     (comunidad/PF) o sin días cargados nunca se excluye por esa dimensión.
///   * Objetivo y zonas NO excluyen: dan puntaje para ordenar. Cruzar cuatro
///     dimensiones duras vaciaría la grilla; con dos (que el atleta controla y
///     puede levantar) el vacío tiene salida — ver [matchesHardFilters] y el
///     estado vacío "ver todas" de PlantillasTab.
///
/// El filtro lo aplica `filteredUnifiedTemplatesProvider`; lo que sobrevive se
/// ordena con [score].
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

  /// Tolerancia del filtro duro de minutos: ±15.
  static const int minutesTolerance = 15;

  /// True si las preferencias traen algo que FILTRA (días o minutos).
  /// Objetivo y zonas no cuentan: sólo ordenan.
  static bool hasHardFilters(TemplatePreferences preferences) =>
      (preferences.daysPerWeek ?? 0) > 0 ||
      (preferences.minutesPerSession ?? 0) > 0;

  /// Filtro duro (#1561): ¿la plantilla encaja en los días y minutos pedidos?
  ///
  ///   * Días: `days.length == daysPerWeek`. Sin días cargados ⇒ pasa.
  ///   * Minutos: `|estimatedMinutesPerDay − pedidos| ≤` [minutesTolerance];
  ///     con 75 ("75 o más") alcanza `≥ 75 − tolerancia`. Sin minutos
  ///     (null / ≤ 0) ⇒ pasa: desconocido no es desajuste.
  ///   * Preferencia no respondida en esa dimensión ⇒ pasa.
  static bool matchesHardFilters(
    Routine routine,
    TemplatePreferences preferences,
  ) {
    final wantedDays = preferences.daysPerWeek;
    if (wantedDays != null && wantedDays > 0) {
      final days = routine.days.length;
      if (days > 0 && days != wantedDays) return false;
    }
    final wantedMinutes = preferences.minutesPerSession;
    if (wantedMinutes != null && wantedMinutes > 0) {
      final minutes = routine.estimatedMinutesPerDay;
      if (minutes != null && minutes > 0) {
        final diff = minutes - wantedMinutes;
        final openEnded = wantedMinutes >= _minutosOMas;
        if (diff < -minutesTolerance) return false;
        if (!openEnded && diff > minutesTolerance) return false;
      }
    }
    return true;
  }

  /// Valor de la opción "75 MIN O MÁS" del cuestionario.
  static const int _minutosOMas = 75;

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

  /// Objetivo. Multi-valor de los DOS lados: la plantilla sirve a varios
  /// (`Routine.goals`) y, desde 2026-10-09, el atleta también puede elegir
  /// varios (`TemplatePreferences.goals`).
  ///
  ///   * Ninguno en común ⇒ 0, igual que antes.
  ///   * Alguno en común ⇒ [_pisoObjetivo] + el resto proporcional a cuántos
  ///     de los elegidos cubre: `piso + (1 − piso) · |elegidos ∩ plantilla| /
  ///     |elegidos|`.
  ///
  /// El piso es lo que hace que una plantilla que sirve a UNO de dos objetivos
  /// siga rankeando bien: con 0.75, cubrir uno de dos da 0.875 — bastante más
  /// que el [neutral] de una sin objetivos declarados, y un poco menos que
  /// una que cubre los dos. Sin piso (proporción pura) daría 0.5 y empataría
  /// con "no sé", que es justamente lo que no es: le sirve.
  ///
  /// Con UN solo objetivo elegido la fórmula da 1 o 0, idéntico a cuando el
  /// campo era único. Ese es el invariante que cuida el barrido de 300
  /// combinaciones de `explorar_filtros_catalogo_real_test.dart`.
  static double _goalScore(Routine routine, TemplatePreferences preferences) {
    final wanted = preferences.goals.toSet();
    if (wanted.isEmpty) return neutral;
    if (routine.goals.isEmpty) return neutral; // publicada antes de #635
    final enComun = wanted.intersection(routine.goals.toSet()).length;
    if (enComun == 0) return 0;
    return _pisoObjetivo + (1 - _pisoObjetivo) * enComun / wanted.length;
  }

  /// Puntaje mínimo de una plantilla que sirve a AL MENOS uno de los objetivos
  /// elegidos. Ver [_goalScore].
  static const double _pisoObjetivo = 0.75;

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
