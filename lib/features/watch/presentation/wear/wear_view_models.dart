/// Modelos de presentación del companion de Wear OS.
///
/// Espejan lo que las vistas de `ios/TreinoWatch Watch App/` leen de sus
/// coordinators. Son tipos de PRESENTACIÓN a propósito, sin Firestore ni
/// providers adentro: así las pantallas se arman y se miran antes de que exista
/// la carga real, y después se testean sin levantar red.
library;

/// Estado del emparejamiento con el teléfono.
///
/// Réplica de `CredentialCoordinator.state` en watchOS. El reloj no puede hablar
/// con Firestore hasta que el teléfono le mintee una credencial, así que esta
/// máquina manda sobre toda la app.
enum WearPairingState {
  /// Todavía no llegó nada del teléfono.
  waitingForPairing,

  /// Llegó el token y se está canjeando.
  exchanging,

  /// Hay credencial: la app funciona.
  ready,

  /// El canje falló.
  failed,
}

/// El entreno de hoy, antes de arrancarlo.
///
/// Réplica de `TodaysWorkout` de watchOS, con lo que la vista previa necesita.
class WearTodaysWorkout {
  const WearTodaysWorkout({
    required this.dayName,
    required this.routineName,
    required this.exercises,
    required this.weekNumber,
    required this.numWeeks,
  });

  final String dayName;
  final String routineName;
  final List<WearExercisePreview> exercises;

  /// 0-based, como en Firestore. Se muestra +1.
  final int weekNumber;
  final int numWeeks;

  int get exerciseCount => exercises.length;

  /// Si mostrar "Sem X/Y".
  ///
  /// Sólo en planes periodizados: en uno de una sola semana el dato es ruido.
  /// Misma regla que watchOS.
  bool get showsWeek => numWeeks > 1;
}

/// Un ejercicio en la vista previa. Sólo lectura: marcar se hace entrenando.
class WearExercisePreview {
  const WearExercisePreview({required this.name, required this.setCount});

  final String name;
  final int setCount;

  /// Singular a mano, igual que en watchOS: "1 días" se lee descuidado en una
  /// pantalla donde entran cuatro palabras.
  String get setsLabel => setCount == 1 ? '1 serie' : '$setCount series';
}

/// Cuál de las dos listas laterales.
enum WearRoutineListKind {
  /// Planes a nombre del atleta: los del PF y los que se armó él.
  plans,

  /// Plantillas para arrancar sin que sean un plan suyo.
  templates,
}

/// Una rutina en las listas laterales.
class WearRoutineSummary {
  const WearRoutineSummary({
    required this.id,
    required this.name,
    required this.dayCount,
    required this.numWeeks,
    this.badge,
  });

  final String id;
  final String name;
  final int dayCount;
  final int numWeeks;

  /// Chapita de origen ("PF", "MÍA"), o null.
  final String? badge;

  /// "3 días" o "3 días · 4 sem". Singular a mano, igual que watchOS.
  String get subtitle {
    final days = dayCount == 1 ? '1 día' : '$dayCount días';
    if (numWeeks <= 1) return days;
    return '$days · $numWeeks sem';
  }
}
