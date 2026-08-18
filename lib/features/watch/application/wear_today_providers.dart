import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../home/application/todays_routine_provider.dart';
import '../presentation/wear/wear_view_models.dart';

/// El entreno de hoy, listo para dibujar en el reloj.
///
/// ## Acá se cobra el reuso del dominio
///
/// Toda la decisión —qué rutina está activa, qué día toca, en qué semana— la
/// resuelve `todaysRoutineProvider`, el MISMO provider que alimenta la Home del
/// teléfono. No se reimplementó nada: sus reglas de negocio ya viven en
/// funciones puras (`resolveActiveRoutineId`, `nextPlanPosition`) con fixtures
/// de `conformance/` como contrato.
///
/// Ésa es la razón entera de hacer el companion en Flutter en vez de Kotlin: el
/// companion de Apple tuvo que portar estas reglas a Swift, y el hueco entre
/// las dos implementaciones costó cuatro incidentes.
///
/// Lo único que queda acá es TRADUCIR, y eso vive en [wearTodaysWorkoutFrom],
/// que es pura y testeable sin Firestore.
///
/// ## Los cuatro estados son cuatro, no dos
///
/// Devuelve un [WearTodayState] y no un `WearTodaysWorkout?` porque el nullable
/// colapsaba "cargando" con "resolvió y no hay entreno". La pantalla elegía
/// "cargando" y dejaba el spinner girando para siempre — medido en el reloj.
///
/// `todaysRoutineProvider` devuelve null de forma LEGÍTIMA: cuando el atleta
/// tiene varias rutinas y ninguna marcada como activa, o cuando no tiene
/// ninguna. Eso no es una demora ni una falla, y merece su propio cartel.
final wearTodayStateProvider = Provider.autoDispose<WearTodayState>((ref) {
  return ref.watch(todaysRoutineProvider).when(
        loading: () => const WearTodayLoading(),
        error: (_, __) => const WearTodayFailed(),
        data: (todays) => todays == null
            ? const WearTodayEmpty()
            : WearTodayReady(wearTodaysWorkoutFrom(todays)),
      );
});

/// Traduce el entreno resuelto por el dominio a la vista previa del reloj.
///
/// Pura a propósito: es la parte que se puede equivocar sin que ningún test de
/// Firestore se entere.
///
/// ## Las dos reglas de periodización que se aplican acá
///
/// Un plan periodizado NO es el mismo entreno todas las semanas, y las dos
/// diferencias viven en el slot:
///
///   1. **`isPresentInWeek`** — un ejercicio puede no existir en cierta semana.
///      Listarlo igual mostraría en la muñeca un ejercicio que el atleta no
///      tiene que hacer.
///   2. **`effectiveSetsForWeek`** — la cantidad de series cambia por semana, e
///      incluye el caso de una semana autorizada como vacía (descarga). Usar
///      `targetSets` daría el número de la semana 1 siempre.
///
/// Las dos son las reglas que `conformance/set_resolution.json` cubre con 13
/// casos — los que, según el HANDOFF, **nunca corrieron en un reloj**. Ahora
/// corren acá.
///
/// El nombre sale de `slot.exerciseName`, que está denormalizado en la rutina
/// (ADR-2). Por eso el reloj NO necesita el catálogo de ejercicios para dibujar
/// esta pantalla: cero lecturas extra de Firestore.
WearTodaysWorkout wearTodaysWorkoutFrom(TodaysRoutine todays) {
  final week = todays.weekNumber;

  return WearTodaysWorkout(
    routineId: todays.routine.id,
    dayName: todays.day.name,
    dayNumber: todays.dayNumber,
    routineName: todays.routine.name,
    // 0-based de punta a punta: `TodaysRoutine.weekNumber` y
    // `WearTodaysWorkout.weekNumber` significan lo mismo, y el +1 lo hace
    // recién la pantalla. Convertir acá lo mostraría corrido una semana.
    weekNumber: week,
    numWeeks: todays.routine.numWeeks,
    exercises: [
      for (final slot in todays.day.slots)
        if (slot.isPresentInWeek(week))
          WearExercisePreview(
            name: slot.exerciseName,
            setCount: slot.effectiveSetsForWeek(week).length,
          ),
    ],
  );
}
