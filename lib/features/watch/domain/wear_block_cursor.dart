import '../../workout/domain/superset_blocks.dart';

/// En qué ejercicio tiene que estar parado el RELOJ, respetando superseries.
///
/// ## Por qué no alcanza `firstUnfinishedExerciseIndex`
///
/// Aquél recorre los ejercicios de a uno y devuelve el primero incompleto, así
/// que en una superserie A/B/C termina las tres series de A antes de ofrecer B.
/// El orden correcto de una superserie es round-robin —1a, 1b, 1c, 2a, 2b, 2c,
/// 3a, 3b, 3c— y el teléfono ya lo entiende así: muestra el bloque entero con
/// navegación libre. El reloj muestra UN ejercicio por vez, así que el orden no
/// lo puede elegir el atleta; lo tiene que poner el cursor.
///
/// El síntoma medido en la muñeca: marcabas 1a y el reloj te ofrecía 2a. Las
/// series 1b y 1c no había manera de marcarlas.
///
/// **`firstUnfinishedExerciseIndex` no se toca**: está bajo el contrato de
/// `conformance/exercise_cursor.json`, compartido con `ExerciseCursor.swift`.
/// Ésta es una función NUEVA que lo generaliza — sin superseries devuelve
/// exactamente lo mismo, porque cada ejercicio queda en un bloque de a uno.
///
/// ## Siempre absoluto, nunca un delta
///
/// Misma regla que el resto del dominio del reloj: se recalcula del estado
/// entero en cada consulta. Por eso puede RETROCEDER cuando el teléfono borra
/// una serie, que con un `+= 1` era inexpresable.
///
/// - [plannedSets]: cuántas series pide el plan por ejercicio, en orden.
/// - [loggedSets]: cuántas hay marcadas, en el MISMO orden. Puede venir más
///   corta: lo que falte se asume en 0.
/// - [supersetGroups]: el `supersetGroup` de cada ejercicio, o null. Idem.
///
/// Devuelve el índice del ejercicio que toca. Con todo completo devuelve el
/// ÚLTIMO, para que el atleta vea que terminó en vez de una pantalla vacía.
/// Con el plan vacío devuelve 0: un índice negativo reventaría al indexar.
int wearCurrentExerciseIndex({
  required List<int> plannedSets,
  required List<int> loggedSets,
  required List<int?> supersetGroups,
}) {
  if (plannedSets.isEmpty) return 0;

  int marcadas(int i) => i < loggedSets.length ? loggedSets[i] : 0;

  // `>=` y no `==`: series de más —agregadas desde el teléfono más allá del
  // plan— cuentan como completo. Con `==` trabarían el cursor para siempre.
  // Es la misma decisión que documenta `firstUnfinishedExerciseIndex`.
  bool completo(int i) => marcadas(i) >= plannedSets[i];

  // Normalizado a la longitud del plan: una lista de grupos más corta no puede
  // desalinear los bloques respecto de las series.
  final grupos = [
    for (var i = 0; i < plannedSets.length; i++)
      i < supersetGroups.length ? supersetGroups[i] : null,
  ];

  for (final bloque in supersetBlockIndices(grupos)) {
    final pendientes = bloque.where((i) => !completo(i)).toList();
    if (pendientes.isEmpty) continue;

    // Dentro del bloque manda quien MENOS series lleva: eso es exactamente el
    // round-robin. A igualdad gana el de menor posición, que es el orden en que
    // el entrenador escribió la superserie.
    //
    // Mirar sólo los PENDIENTES es lo que hace bien el caso de miembros con
    // distinta cantidad de series: en A(3)+B(2), cuando B ya cerró sus dos, la
    // tercera de A se ofrece igual en vez de trabar el bloque.
    var elegido = pendientes.first;
    for (final i in pendientes) {
      if (marcadas(i) < marcadas(elegido)) elegido = i;
    }
    return elegido;
  }

  return plannedSets.length - 1;
}
