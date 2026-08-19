import 'wear_block_cursor.dart';
import 'wear_workout_plan.dart';

/// Una serie ya cargada, con lo mínimo que el reloj necesita saber de ella.
///
/// No se usa `SetLog` a propósito: ese tipo importa `cloud_firestore` (por el
/// `Timestamp` de `completedAt`), y con él todo este dominio dejaría de poder
/// razonarse y testearse sin Firebase. La traducción la hace la capa de datos,
/// que es donde ese acoplamiento ya vive.
class WearLoggedSet {
  const WearLoggedSet({
    required this.docId,
    required this.exerciseId,
    required this.setNumber,
    required this.reps,
    required this.weightKg,
  });

  /// El documento que la contiene.
  ///
  /// Se guarda porque `resolveSetLogWriteTarget` lo necesita: sin él no se
  /// puede detectar que la ruta determinística quedó ocupada por OTRA serie
  /// —el caso que evita destruir un dato del atleta— y todo el contrato se
  /// vuelve inaplicable desde acá.
  final String docId;

  final String exerciseId;
  final int setNumber;
  final int reps;
  final double weightKg;

  /// La identidad LÓGICA de la serie: el par ejercicio + número.
  ///
  /// No es el id del documento, aunque se escriban igual. Un mismo par lógico
  /// puede vivir en documentos distintos —el teléfono usa ids autogenerados— y
  /// justamente por eso el conteo se hace sobre ESTO y no sobre documentos.
  String get logicalId => '${exerciseId}__$setNumber';
}

/// El entreno en curso, tal como lo ve el reloj.
///
/// ## Todo se recalcula, nada se acumula
///
/// [logged] es ABSOLUTO: es lo último que dijo el listener de Firestore, y pisa
/// entero. Nunca se hace merge ni se aplica un incremento.
///
/// Es la lección del §4.5 del HANDOFF, que ya mordió cuatro veces —`logSet`,
/// `removeSet`, el cursor de watchOS y el snapshot de esta misma pantalla—:
/// no preguntarse cuánto se movió el mundo, **recalcular**. Con valores
/// absolutos da igual el orden en que lleguen las cosas, y el reloj puede
/// RETROCEDER cuando el teléfono borra una serie, que con un delta era
/// inexpresable.
class WearWorkoutSession {
  const WearWorkoutSession({
    required this.sessionId,
    required this.startedAt,
    required this.plan,
    required this.logged,
    this.pending = const {},
  });

  final String sessionId;
  final DateTime startedAt;
  final WearWorkoutPlan plan;

  /// Lo que dice el historial AHORA. Absoluto.
  final List<WearLoggedSet> logged;

  /// Identidades lógicas con una escritura EN VUELO.
  ///
  /// Cuentan como marcadas para que el círculo se llene en el toque y no
  /// después del viaje a la red. Si la escritura falla, la identidad sale de acá
  /// y el círculo se vacía — que es honesto.
  ///
  /// **Sólo sirve para eso.** No hay cartel de «sin subir»: se sacó, porque en
  /// Wear no existe una cola offline propia. Firestore la maneja solo, y el
  /// cartel se limpiaba cuando la escritura era visible LOCALMENTE, no cuando el
  /// servidor la confirmaba — o sea que decía «subido» estando encolada, que es
  /// el único caso donde el dato habría importado. En watchOS el cartel sí tiene
  /// sentido: allá la cola está escrita a mano.
  final Set<String> pending;

  /// Las series marcadas, por identidad lógica.
  ///
  /// ⚠️ Un `Set` de identidades, NO un conteo de documentos. Si el teléfono y el
  /// reloj llegaron a dejar dos documentos de la misma serie, contarlos
  /// sobrecontaría y el cursor saltearía un ejercicio entero. Es el mismo
  /// invariante que `_dedupedLogs` del notifier del teléfono.
  Set<String> get identities => {
        for (final l in logged) l.logicalId,
        ...pending,
      };

  /// Cuántas series marcadas tiene cada ejercicio, en el orden del plan.
  List<int> get loggedSets {
    final marcadas = identities;
    return [
      for (final e in plan.exercises)
        marcadas.where((id) => id.startsWith('${e.exerciseId}__')).length,
    ];
  }

  /// En qué ejercicio está parado el reloj.
  ///
  /// Generaliza `firstUnfinishedExerciseIndex` —la regla compartida con el
  /// companion de Apple, bajo el contrato de `conformance/exercise_cursor.json`—
  /// para que una superserie avance en round-robin. Sin superseries devuelve
  /// exactamente lo mismo que aquélla. Ver [wearCurrentExerciseIndex].
  int get currentExerciseIndex => wearCurrentExerciseIndex(
        plannedSets: plan.plannedSets,
        loggedSets: loggedSets,
        supersetGroups: plan.supersetGroups,
      );

  /// Si están TODAS las series de TODOS los ejercicios.
  ///
  /// Es la condición de «Terminar», pedido del dueño: tenerlo a la vista antes
  /// invita a cerrar el entreno de más.
  ///
  /// Un plan sin series planificadas devuelve false. Sin ese guard, un entreno
  /// vacío nacería "completo" y contaría para la racha — el mismo agujero que
  /// `SessionState.isFullyCompleted` cierra del lado del teléfono.
  bool get isFullyCompleted {
    final planificadas = plan.plannedSets;
    if (planificadas.isEmpty) return false;

    var total = 0;
    for (final n in planificadas) {
      total += n;
    }
    if (total == 0) return false;

    final marcadas = loggedSets;
    for (var i = 0; i < planificadas.length; i++) {
      if (marcadas[i] < planificadas[i]) return false;
    }
    return true;
  }

  /// El volumen del entreno, para `SessionRepository.finish`.
  ///
  /// Sobre las series REALES, no sobre [identities]: una escritura en vuelo
  /// todavía no tiene reps ni peso confirmados.
  double get totalVolumeKg {
    var total = 0.0;
    for (final l in logged) {
      total += l.reps * l.weightKg;
    }
    return total;
  }

  WearWorkoutSession copyWith({
    List<WearLoggedSet>? logged,
    Set<String>? pending,
  }) =>
      WearWorkoutSession(
        sessionId: sessionId,
        startedAt: startedAt,
        plan: plan,
        logged: logged ?? this.logged,
        pending: pending ?? this.pending,
      );
}
