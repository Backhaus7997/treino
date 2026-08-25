/// Cómo se agrupan los ejercicios de un día en BLOQUES.
///
/// Un bloque es o un ejercicio suelto, o una superserie: varios slots contiguos
/// que comparten `RoutineSlot.supersetGroup`.
///
/// ## Por qué la regla vive acá y no en la pantalla
///
/// Nació dentro de `session_player_screen.dart`, o sea en PRESENTACIÓN del
/// teléfono, y ahí quedó invisible para todo el resto. El companion de Wear no
/// la vio nunca: aplanaba `day.slots` en una lista lineal, así que trataba una
/// superserie A/B/C como tres ejercicios independientes. En la muñeca eso se
/// veía como que después de la serie 1 de A venía la 2 de A, y las series 1 de
/// B y de C no había forma de marcarlas.
///
/// Agrupar es una regla de DOMINIO —define qué es un bloque de entrenamiento—,
/// no una decisión de dibujo. Con una sola definición, los dos lados no pueden
/// volver a divergir.
///
/// Opera sobre `List<int?>` y no sobre `RoutineSlot` a propósito: el dominio del
/// reloj tiene su propio tipo de ejercicio planificado y no debe arrastrar el
/// modelo entero de la rutina para preguntar por un agrupamiento.
library;

/// Las POSICIONES de cada bloque, en orden, sobre una lista de grupos.
///
/// `groups[i]` es el `supersetGroup` del ejercicio en la posición `i`, o null
/// si no pertenece a ninguna superserie.
///
/// Reglas, iguales a las que ya aplicaba el teléfono:
///
/// Sólo agrupa posiciones **contiguas** con el mismo grupo: dos bloques con el
/// mismo número separados por otro ejercicio son dos bloques distintos. Sin esa
/// condición, un número reusado más adelante en el día se tragaría el ejercicio
/// del medio.
///
/// Ejemplo: `[null, 1, 1, 1, null]` → `[[0], [1,2,3], [4]]`.
///
/// Un grupo con un solo miembro devuelve un bloque de uno, igual que un
/// ejercicio sin grupo. **Decidir si eso "es" una superserie no es asunto de
/// esta función**: la partición es idéntica en los dos casos, y quien necesita
/// la distinción —el teléfono, que dibuja distinto un bloque de superserie— la
/// saca de `length >= 2` sobre el resultado. Tenerlo acá adentro era una rama
/// que no cambiaba ninguna salida; se descubrió mutándola y viendo que TODOS
/// los tests seguían verdes.
List<List<int>> supersetBlockIndices(List<int?> groups) {
  final bloques = <List<int>>[];
  var i = 0;
  while (i < groups.length) {
    final grupo = groups[i];
    final miembros = <int>[i];
    if (grupo != null) {
      var scan = i + 1;
      while (scan < groups.length && groups[scan] == grupo) {
        miembros.add(scan);
        scan++;
      }
    }
    bloques.add(miembros);
    i += miembros.length;
  }
  return bloques;
}
