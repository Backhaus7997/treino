/// En qué ejercicio tiene que estar parado el cliente durante un entreno.
///
/// Portada desde `ios/TreinoWatch Watch App/ExerciseCursor.swift`, donde nació.
/// Los fixtures compartidos de `conformance/exercise_cursor.json` son el
/// contrato entre las dos implementaciones: si una cambia y la otra no, CI se
/// pone en rojo antes de que el atleta vea la muñeca clavada.
///
/// ## SIEMPRE ABSOLUTO, NUNCA UN DELTA
///
/// Ésta es la regla, y está escrita con sangre. El cursor se movía con
/// `currentExerciseIndex += 1` y avanzaba un solo paso aunque en un mismo sync
/// entraran tres ejercicios enteros cargados desde el teléfono. El atleta
/// entrenaba un rato en el celular, miraba el reloj, y lo encontraba clavado en
/// un ejercicio ya terminado: sin fila tocable —todas sus series estaban
/// hechas— y sin botón de Terminar.
///
/// Es la misma trampa del §4.5 del HANDOFF que ya mordió a `logSet`, a
/// `removeSet` y al cursor de watchOS. La lección, con cuatro casos: no
/// preguntarse cuánto se movió el mundo, **recalcular**.
///
/// Y por eso tiene que poder RETROCEDER: si el teléfono borró una serie del
/// ejercicio en curso, ese ejercicio dejó de estar completo y hay que volver a
/// ofrecerlo. Con un delta eso era directamente inexpresable.
///
/// - [plannedSets]: cuántas series pide el plan por ejercicio, en orden.
/// - [loggedSets]: cuántas hay cargadas por ejercicio, en el MISMO orden. Puede
///   ser más corta que [plannedSets]: las que falten se asumen en 0.
///
/// Devuelve el índice del primer ejercicio incompleto. Si están todos
/// completos devuelve el ÚLTIMO, para que el atleta vea que terminó en vez de
/// una pantalla vacía. Con la lista vacía devuelve 0: un índice negativo se
/// usaría para indexar y reventaría.
int firstUnfinishedExerciseIndex({
  required List<int> plannedSets,
  required List<int> loggedSets,
}) {
  if (plannedSets.isEmpty) return 0;

  for (var index = 0; index < plannedSets.length; index++) {
    final logged = index < loggedSets.length ? loggedSets[index] : 0;
    // `<` y no `!=`: series de más —agregadas desde el teléfono más allá del
    // plan— cuentan como completo. Con `!=` trabarían el cursor para siempre.
    if (logged < plannedSets[index]) return index;
  }

  return plannedSets.length - 1;
}
