import 'routine_day.dart';
import 'routine_day_duration.dart';
import 'routine_slot.dart';

/// Cómo terminó [planSessionTimeFit].
enum SessionTimeFitOutcome {
  /// El día no tiene nada medible (sin slots, o todos dan cero segundos).
  /// No hay nada que ofrecer: la UI no debe mostrar el ajuste.
  notMeasurable,

  /// La sesión completa ya entra en el tiempo declarado. No se saca nada.
  alreadyFits,

  /// Sacando `dropExerciseIds` la sesión entra en el tiempo declarado.
  trimSuggested,

  /// Ni sacando todo lo que se puede sacar entra. `dropExerciseIds` trae el
  /// recorte MÁS PROFUNDO alcanzable y `projectedMinutes` lo que quedaría —
  /// la UI lo muestra tal cual ("lo más corto posible son ~X min") y deja que
  /// el atleta decida si lo aplica igual. Puede venir vacío cuando no hay
  /// nada recortable (un día de un solo ejercicio, o el que sigue ya tiene
  /// series hechas).
  cannotFit,
}

/// La propuesta de recorte para la sesión de HOY.
///
/// [dropExerciseIds] va en orden del día (los últimos del día primero en
/// salir, pero la lista se lee de arriba hacia abajo como se ven en pantalla).
typedef SessionTimeFitPlan = ({
  SessionTimeFitOutcome outcome,
  int? currentMinutes,
  int? projectedMinutes,
  List<String> dropExerciseIds,
});

/// Propone qué ejercicios sacar de la sesión de HOY para que [day] entre en
/// [availableMinutes] (#645).
///
/// ── El criterio de recorte ──────────────────────────────────────────────
///
/// **Los últimos del día, en bloque, y nada más.** La función recorre los
/// slots desde el final hacia el principio y va sacando de a uno hasta que la
/// estimación entra. No hay criterio de entrenamiento acá —nada de "sacá los
/// accesorios y dejá los compuestos"— porque eso es PRESCRIBIR, y la app no
/// prescribe. Un criterio mecánico y explicable en una línea es lo único que
/// el atleta puede auditar de un vistazo; uno "inteligente" que no puede ver
/// alimenta exactamente la sospecha de que la app hace cualquier cosa.
///
/// Tres reglas acotan ese recorrido:
///
/// 1. **El corte nunca parte una superserie.** Una superserie es UNA unidad de
///    trabajo: hacer la mitad no es hacer media superserie, es hacer otra
///    cosa. Si el borde cae adentro de un grupo, el grupo entero sale o
///    entero queda.
/// 2. **Nunca se saca algo que ya tiene series hechas** ([lockedExerciseIds]).
///    Y el recorrido FRENA en el primer ejercicio trabado: el recorte es una
///    cola contigua al final del día, no una selección salteada. Sacar algo
///    de la mitad y dejar lo de después convierte "los últimos N" en una
///    regla que ya no se puede explicar.
/// 3. **Siempre queda trabajo.** Un recorte que deja la sesión en cero no es
///    un recorte, es abandonar — y con `isFullyCompleted` mirando un
///    denominador cero sería además una racha regalada en dos taps.
///
/// Un slot ausente esta semana ([RoutineSlot.isPresentInWeek]) no es parte de
/// la sesión de hoy: no suma minutos, no traba el recorrido y no se reporta
/// como sacado. Aparece en `day.slots` sólo cuando el llamador no filtró por
/// presencia — el player sí lo hace al armar el estado (REQ-WPRES-021).
///
/// ── Por qué ignora `day.estimatedMinutes` ───────────────────────────────
///
/// Los dos números —el de antes y el de después— salen SIEMPRE de la cascada
/// calculada, con [RoutineDay.estimatedMinutes] en `null`. Un valor autorado
/// describe el día tal como fue escrito y no tiene desglose por ejercicio, así
/// que no puede contestar "¿cuánto bajo si saco éste?". Mezclar un "antes"
/// autorado con un "después" calculado permite que un recorte muestre MÁS
/// minutos que la sesión entera, que es la única forma de que este feature
/// mienta de verdad. Misma base de los dos lados: cada ejercicio que sale baja
/// el número, siempre.
///
/// Función pura — sin imports de Flutter, sin providers. Reusa
/// [estimateRoutineDayMinutes] (#639) sobre el día completo y sobre cada
/// recorte candidato.
SessionTimeFitPlan planSessionTimeFit({
  required RoutineDay day,
  required int availableMinutes,
  int week = 0,
  Set<String> lockedExerciseIds = const {},
}) {
  // Base calculada para los DOS números. Ver el dartdoc de arriba.
  final basis = day.copyWith(estimatedMinutes: null);
  final slots = basis.slots;
  final current = estimateSessionMinutes(basis, week: week);

  if (current == null) {
    return (
      outcome: SessionTimeFitOutcome.notMeasurable,
      currentMinutes: null,
      projectedMinutes: null,
      dropExerciseIds: const <String>[],
    );
  }
  if (current <= availableMinutes) {
    return (
      outcome: SessionTimeFitOutcome.alreadyFits,
      currentMinutes: current,
      projectedMinutes: current,
      dropExerciseIds: const <String>[],
    );
  }

  // Lo sacado hasta acá, en orden del día (insert(0) porque caminamos al revés).
  final dropped = <String>[];
  // El recorte válido más profundo alcanzado. Sólo se actualiza en un borde de
  // corte legal, así que nunca queda a mitad de una superserie.
  var deepestDrops = const <String>[];
  int? deepestMinutes;

  for (var keep = slots.length - 1; keep >= 1; keep--) {
    final slot = slots[keep];

    // Ausente esta semana: no está en la sesión de hoy. Ni traba ni se reporta.
    if (!slot.isPresentInWeek(week)) continue;

    // Cola contigua: el recorrido termina en lo primero que ya se trabajó.
    if (lockedExerciseIds.contains(slot.exerciseId)) break;

    dropped.insert(0, slot.exerciseId);

    // Borde adentro de una superserie: el slot sale igual, pero recién se
    // evalúa cuando el borde caiga entre bloques.
    if (_cutSplitsSuperset(slots, keep)) continue;

    final trimmed = basis.copyWith(slots: slots.sublist(0, keep));
    final projected = estimateSessionMinutes(trimmed, week: week);
    // Lo que queda ya no es una sesión. Nos quedamos con el último recorte
    // válido y cortamos el recorrido.
    if (projected == null) break;

    deepestDrops = List<String>.unmodifiable(dropped);
    deepestMinutes = projected;

    if (projected <= availableMinutes) {
      return (
        outcome: SessionTimeFitOutcome.trimSuggested,
        currentMinutes: current,
        projectedMinutes: projected,
        dropExerciseIds: deepestDrops,
      );
    }
  }

  return (
    outcome: SessionTimeFitOutcome.cannotFit,
    currentMinutes: current,
    projectedMinutes: deepestMinutes,
    dropExerciseIds: deepestDrops,
  );
}

/// Minutos estimados de lo que la sesión de HOY tiene por delante, con
/// [droppedExerciseIds] ya sacado (#645).
///
/// Es la MISMA base que usa [planSessionTimeFit] —`estimatedMinutes` en null,
/// todo calculado desde los slots— y por eso es la única forma correcta de
/// pedir el número de una sesión recortada. Pedirlo por
/// [estimateRoutineDayMinutes] sobre el día crudo devolvería el valor autorado
/// del plan, que ya no describe lo que se va a hacer hoy.
///
/// `null` cuando no queda nada medible.
int? estimateSessionMinutes(
  RoutineDay day, {
  int week = 0,
  Set<String> droppedExerciseIds = const {},
}) {
  final slots = droppedExerciseIds.isEmpty
      ? day.slots
      : [
          for (final s in day.slots)
            if (!droppedExerciseIds.contains(s.exerciseId)) s
        ];
  return estimateRoutineDayMinutes(
    day.copyWith(slots: slots, estimatedMinutes: null),
    week: week,
  ).minutes;
}

/// `true` cuando cortar dejando `slots[0..keep-1]` partiría una superserie al
/// medio — o sea, cuando el slot del borde comparte grupo con el anterior.
///
/// Un slot con `supersetGroup` cuyo vecino tiene otro grupo (o ninguno) es un
/// grupo de uno: `buildBlocks` lo degrada a standalone y acá también es un
/// borde legal.
bool _cutSplitsSuperset(List<RoutineSlot> slots, int keep) {
  final group = slots[keep].supersetGroup;
  if (group == null) return false;
  return slots[keep - 1].supersetGroup == group;
}
