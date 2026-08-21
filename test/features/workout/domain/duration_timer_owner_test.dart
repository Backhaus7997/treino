import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/duration_timer_owner.dart';

/// El invariante que evita la duplicación: **una cuenta tiene UN dueño, y el
/// dueño es el lado que la arrancó.**
///
/// Si el teléfono y el reloj marcaran los dos la misma serie al llegar a cero
/// quedarían dos documentos —los dos clientes generan ids distintos, así que el
/// que llega tarde no puede deduplicar— y el atleta la ve repetida en su
/// historial.
void main() {
  final t0 = DateTime.utc(2027, 1, 15, 10);
  final enUnMinuto = t0.add(const Duration(seconds: 60));

  DurationTimerView resolver({
    String exerciseId = 'plancha',
    int setNumber = 2,
    DateTime? localEndsAt,
    String? watchExerciseId,
    int? watchSetNumber,
    DateTime? watchEndsAt,
    DateTime? now,
  }) =>
      DurationTimerOwnership.resolve(
        exerciseId: exerciseId,
        setNumber: setNumber,
        localEndsAt: localEndsAt,
        watchExerciseId: watchExerciseId,
        watchSetNumber: watchSetNumber,
        watchEndsAt: watchEndsAt,
        now: now ?? t0,
      );

  test('sin nada corriendo no hay dueño', () {
    final vista = resolver();
    expect(vista.owner, DurationTimerOwner.nadie);
    expect(vista.endsAt, isNull);
  });

  test('una cuenta arrancada en el teléfono es del teléfono', () {
    final vista = resolver(localEndsAt: enUnMinuto);
    expect(vista.owner, DurationTimerOwner.telefono);
    expect(vista.endsAt, enUnMinuto);
  });

  test('una cuenta del reloj sobre ESTA serie es del reloj', () {
    final vista = resolver(
      watchExerciseId: 'plancha',
      watchSetNumber: 2,
      watchEndsAt: enUnMinuto,
    );
    expect(vista.owner, DurationTimerOwner.reloj);
    expect(vista.endsAt, enUnMinuto);
  });

  test('otra SERIE del mismo ejercicio no es esta', () {
    // Con tres series por tiempo en el mismo ejercicio, ubicar la cuenta solo
    // por el ejercicio la dibujaría en las tres.
    final vista = resolver(
      setNumber: 2,
      watchExerciseId: 'plancha',
      watchSetNumber: 3,
      watchEndsAt: enUnMinuto,
    );
    expect(vista.owner, DurationTimerOwner.nadie);
  });

  test('otro EJERCICIO no es este', () {
    final vista = resolver(
      exerciseId: 'plancha',
      watchExerciseId: 'sentadilla',
      watchSetNumber: 2,
      watchEndsAt: enUnMinuto,
    );
    expect(vista.owner, DurationTimerOwner.nadie);
  });

  test('sin número de serie la cuenta del reloj no se ubica', () {
    // Un payload viejo del reloj —o uno mal formado— no puede hacer que la
    // cuenta caiga en una fila cualquiera.
    final vista = resolver(
      watchExerciseId: 'plancha',
      watchSetNumber: null,
      watchEndsAt: enUnMinuto,
    );
    expect(vista.owner, DurationTimerOwner.nadie);
  });

  test('una cuenta del reloj ya vencida no es de nadie', () {
    // El reloj publica cada ~5 segundos: el último contexto recibido puede
    // describir una cuenta que ya terminó. Mostrarla sería mentir.
    final vista = resolver(
      watchExerciseId: 'plancha',
      watchSetNumber: 2,
      watchEndsAt: enUnMinuto,
      now: enUnMinuto,
    );
    expect(vista.owner, DurationTimerOwner.nadie);
  });

  test('una cuenta propia ya vencida deja de serlo', () {
    final vista = resolver(localEndsAt: enUnMinuto, now: enUnMinuto);
    expect(vista.owner, DurationTimerOwner.nadie);
  });

  test('si las dos corren sobre la misma serie, gana la del teléfono', () {
    // No compiten en la práctica —el reloj solo transmite su cronómetro propio,
    // nunca el espejado— pero el desempate está igual: depender de que el otro
    // lado siga portándose bien no es una garantía.
    //
    // Y el orden importa: el teléfono es quien va a marcar la serie, así que
    // cederle la pantalla al espejo lo dejaría marcando algo que no muestra.
    final vista = resolver(
      localEndsAt: enUnMinuto,
      watchExerciseId: 'plancha',
      watchSetNumber: 2,
      watchEndsAt: t0.add(const Duration(seconds: 30)),
    );
    expect(vista.owner, DurationTimerOwner.telefono);
    expect(vista.endsAt, enUnMinuto);
  });

  test('una cuenta propia VENCIDA no le gana a una viva del reloj', () {
    // El desempate es por cuenta VIVA, no por procedencia. Si la propia ya
    // venció, la fila tiene que poder mostrar la del reloj.
    final vista = resolver(
      localEndsAt: t0.add(const Duration(seconds: 10)),
      watchExerciseId: 'plancha',
      watchSetNumber: 2,
      watchEndsAt: enUnMinuto,
      now: t0.add(const Duration(seconds: 30)),
    );
    expect(vista.owner, DurationTimerOwner.reloj);
    expect(vista.endsAt, enUnMinuto);
  });
}
