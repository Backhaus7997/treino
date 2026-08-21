/// Quién manda en la cuenta de una serie por tiempo.
///
/// ── Por qué esto es una regla y no un `if` en el widget ──────────────────
///
/// El cronómetro puede arrancar en el teléfono o en el reloj, y **el lado que
/// arranca es el dueño de la serie: es el único que la marca al llegar a
/// cero.** El otro la muestra y no la toca. Si los dos la marcaran quedarían
/// dos documentos para la misma serie —los dos clientes generan ids distintos,
/// así que el que llega tarde no puede deduplicar— y el atleta la ve repetida.
///
/// Ese invariante es la única cosa que evita la duplicación, así que vive acá,
/// pura y con test, en vez de repartido en condiciones de `build()`.
///
/// La aritmética de la cuenta es la compartida con el reloj
/// ([DurationTimerRules], contrato en `conformance/duration_timer.json`); esto
/// decide de QUIÉN es la cuenta, no cuánto falta.
library;

import 'duration_timer.dart';

enum DurationTimerOwner {
  /// No hay cuenta corriendo. La fila ofrece arrancar.
  nadie,

  /// La arrancó ESTE teléfono. Al llegar a cero él marca la serie.
  telefono,

  /// La arrancó el RELOJ. El teléfono la muestra y NO la marca: la marca el
  /// reloj, que es su dueño.
  reloj,
}

/// Qué cuenta le toca mostrar a una fila, y de quién es.
typedef DurationTimerView = ({DurationTimerOwner owner, DateTime? endsAt});

abstract final class DurationTimerOwnership {
  /// Resuelve la cuenta de la serie [setNumber] del ejercicio [exerciseId].
  ///
  /// [localEndsAt] es la cuenta arrancada en este teléfono, si hay.
  /// [watchExerciseId] / [watchSetNumber] / [watchEndsAt] describen la que
  /// corre en el reloj, si hay — se piden los tres porque con cualquiera
  /// ausente la cuenta no se puede ubicar, y dibujarla en la fila equivocada es
  /// peor que no dibujarla.
  static DurationTimerView resolve({
    required String exerciseId,
    required int setNumber,
    required DateTime? localEndsAt,
    required String? watchExerciseId,
    required int? watchSetNumber,
    required DateTime? watchEndsAt,
    required DateTime now,
  }) {
    // La cuenta propia gana. No es arbitrario: si este teléfono la arrancó, es
    // él quien va a marcar la serie, y cederle la pantalla a un espejo lo
    // dejaría marcando algo que no muestra.
    //
    // En la práctica no compiten: el reloj solo transmite su cronómetro PROPIO,
    // nunca el espejado del teléfono, así que un cronómetro del teléfono no
    // vuelve rebotado. El desempate está igual, porque depender de que el otro
    // lado siga portándose bien no es una garantía.
    if (localEndsAt != null &&
        !DurationTimerRules.isFinished(endsAt: localEndsAt, now: now)) {
      return (owner: DurationTimerOwner.telefono, endsAt: localEndsAt);
    }

    if (watchEndsAt != null &&
        watchExerciseId == exerciseId &&
        watchSetNumber == setNumber &&
        !DurationTimerRules.isFinished(endsAt: watchEndsAt, now: now)) {
      return (owner: DurationTimerOwner.reloj, endsAt: watchEndsAt);
    }

    return (owner: DurationTimerOwner.nadie, endsAt: null);
  }
}
