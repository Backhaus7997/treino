/// El orden en que se recorre una superserie.
///
/// ── Por qué esto existe como regla pura ─────────────────────────────────
///
/// La regla vivía DENTRO del `build()` de `_SupersetSection`, en
/// `session_player_screen.dart`. Ahí era imposible de portar y de testear sin
/// levantar un widget — y el reloj, que reimplementa la lógica en Swift, ni
/// siquiera sabía que la superserie existía: aplanaba el bloque y recorría
/// ejercicio por ejercicio.
///
/// El resultado medido en hardware: con tres ejercicios A, B, C de tres series,
/// el atleta veía sólo A en la muñeca, y después de marcar 1a lo único que
/// podía marcar era 2a. El dato quedaba válido —misma identidad lógica que usa
/// el teléfono— pero producido en el orden equivocado. Y una superserie hecha
/// como tres ejercicios seguidos **es otro estímulo de entrenamiento**: no es
/// un problema cosmético.
///
/// El contrato compartido vive en `conformance/superset_order.json`.
library;

/// Un miembro del bloque, con lo único que la regla necesita saber.
typedef SupersetMember = ({
  String exerciseId,
  int plannedSets,
  int loggedSets,
});

/// La celda que toca AHORA: qué ejercicio y qué serie.
///
/// [round] es la vuelta, y coincide con [setNumber] por construcción: en la
/// vuelta N de una superserie se hace la serie N de cada miembro.
typedef SupersetCell = ({String exerciseId, int setNumber, int round});

abstract final class SupersetOrder {
  /// Vueltas totales del bloque: las del miembro más largo.
  ///
  /// Un miembro con menos series simplemente se saltea en las vueltas finales;
  /// no acorta el bloque.
  static int totalRounds(List<SupersetMember> members) {
    var maximo = 0;
    for (final m in members) {
      if (m.plannedSets > maximo) maximo = m.plannedSets;
    }
    return maximo;
  }

  /// La primera celda sin hacer, recorriendo VUELTA por vuelta.
  ///
  /// Devuelve null cuando el bloque está completo.
  ///
  /// El anidamiento es lo que define la regla y es lo que el reloj tenía al
  /// revés: la vuelta va AFUERA y el ejercicio ADENTRO. Eso produce
  /// 1a, 1b, 1c, 2a, 2b, 2c… y no 1a, 2a, 3a, 1b…
  static SupersetCell? nextCell(List<SupersetMember> members) {
    final vueltas = totalRounds(members);
    for (var vuelta = 1; vuelta <= vueltas; vuelta++) {
      for (final m in members) {
        // Un miembro más corto no participa de las vueltas que le sobran.
        if (vuelta > m.plannedSets) continue;
        if (m.loggedSets < vuelta) {
          return (exerciseId: m.exerciseId, setNumber: vuelta, round: vuelta);
        }
      }
    }
    return null;
  }
}
