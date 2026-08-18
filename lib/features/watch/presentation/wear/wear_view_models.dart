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
    required this.routineId,
    required this.dayName,
    required this.dayNumber,
    required this.routineName,
    required this.exercises,
    required this.weekNumber,
    required this.numWeeks,
  });

  /// La rutina resuelta. No se muestra: es lo que hace falta para CREAR la
  /// sesión al tocar «Empezar», sin volver a leer nada.
  final String routineId;

  final String dayName;

  /// 1-based, igual que `RoutineDay.dayNumber`. Tampoco se muestra.
  ///
  /// Va junto con [weekNumber] a `SessionRepository.create`, y desde ahí la
  /// posición la manda la SESIÓN — nunca se recalcula. Ver
  /// `wearWorkoutPlanFrom`.
  final int dayNumber;

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

/// En qué estado está la pantalla HOY.
///
/// ## Por qué un tipo y no un `WearTodaysWorkout?` con banderas
///
/// Antes eran un nullable más un `failed`, y ese diseño tenía un agujero: `null`
/// significaba las DOS cosas —"todavía cargando" y "resolvió, y no hay entreno
/// para hoy"—. La pantalla no puede distinguirlas, así que elegía la primera y
/// mostraba el spinner **para siempre**.
///
/// No es hipotético: se vio en el reloj, y costó una sesión de diagnóstico
/// porque una espera infinita es indistinguible de un problema de red.
///
/// ⚠️ **Acá el companion de Wear se aparta a propósito del de watchOS.**
/// `TodayPage` de `ContentView.swift` tiene el mismo hueco: si no hay workout y
/// no hay error, cae al `else` con "Cargando tu rutina…". Un atleta sin plan
/// activo se queda mirando girar la ruedita en la muñeca. Es un defecto, no una
/// decisión, y no se replica. Si algún día se arregla del lado Apple, esta es
/// la forma que conviene copiar.
sealed class WearTodayState {
  const WearTodayState();
}

/// Todavía se está resolviendo.
class WearTodayLoading extends WearTodayState {
  const WearTodayLoading();
}

/// No se pudo cargar. Es un error: reintentar tiene sentido.
class WearTodayFailed extends WearTodayState {
  const WearTodayFailed();
}

/// Resolvió bien y NO hay entreno: el atleta no tiene plan activo.
///
/// Es un estado legítimo, no una falla. Pasa cuando hay varias rutinas y
/// ninguna marcada como activa, o cuando no hay ninguna.
class WearTodayEmpty extends WearTodayState {
  const WearTodayEmpty();
}

/// Hay entreno.
class WearTodayReady extends WearTodayState {
  const WearTodayReady(this.workout);

  final WearTodaysWorkout workout;
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
