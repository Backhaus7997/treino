import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/duration_timer.dart';
import 'package:treino/features/workout/domain/duration_timer_owner.dart';
import 'package:treino/features/workout/domain/duration_timer_state.dart';

/// El shape ÚNICO del cronómetro de una serie por tiempo.
///
/// Lo que se prueba acá no es aritmética —esa está bajo contrato en
/// `conformance/duration_timer.json`— sino que este tipo la DELEGUE en vez de
/// reimplementarla, que es exactamente el problema que vino a cerrar: había dos
/// funciones para una sola regla y daban el mismo número hasta que dejaron de
/// darlo.
void main() {
  /// Un instante cualquiera, fijo. No se usa el reloj real: un test que
  /// dependa de la fecha de hoy caduca.
  final arranque = DateTime.utc(2031, 3, 4, 18, 30);

  DurationTimerState arrancada({
    String exerciseId = 'plancha',
    int setNumber = 2,
    int totalSeconds = 60,
    DurationTimerOwner owner = DurationTimerOwner.telefono,
  }) =>
      DurationTimerState.startedAt(
        exerciseId: exerciseId,
        setNumber: setNumber,
        totalSeconds: totalSeconds,
        start: arranque,
        owner: owner,
      );

  group('el instante de fin sale de la MISMA regla que después lo lee', () {
    test('arrancar en T por N segundos termina donde dice DurationTimerRules',
        () {
      final t = arrancada(totalSeconds: 45);

      expect(
        t.endsAt,
        DurationTimerRules.endsAt(start: arranque, totalSeconds: 45),
      );
    });

    test('lo que falta lo resuelve DurationTimerRules, no una cuenta propia',
        () {
      final t = arrancada(totalSeconds: 60);

      // El caso que motiva el contrato entero: pasaron 70 segundos de reloj de
      // pared sobre una plancha de 60. Una cuenta por ticks perdidos diría que
      // faltan 10; contra el reloj de pared no falta nada.
      expect(t.remainingAt(arranque.add(const Duration(seconds: 70))), 0);
      expect(t.isFinishedAt(arranque.add(const Duration(seconds: 70))), isTrue);
    });

    test('con una fracción de segundo todavía falta 1, no 0', () {
      final t = arrancada(totalSeconds: 60);
      final casi = arranque.add(const Duration(milliseconds: 59600));

      // Redondeo hacia ARRIBA: mostrar 0 con tiempo restante invita a cortar
      // antes, y en un ejercicio por tiempo cortar antes es hacer otra serie.
      expect(t.remainingAt(casi), 1);
      expect(t.isFinishedAt(casi), isFalse);
    });
  });

  group('el dueño viaja explícito porque el canal ya no lo dice', () {
    test('quien arranca queda como dueño', () {
      expect(arrancada().owner, DurationTimerOwner.telefono);
      expect(
        arrancada(owner: DurationTimerOwner.reloj).owner,
        DurationTimerOwner.reloj,
      );
    });
  });

  group('la identidad ubica la cuenta en UNA fila', () {
    test('aplica sólo a su ejercicio y su serie', () {
      final t = arrancada(exerciseId: 'plancha', setNumber: 2);

      expect(t.aplicaA(exerciseId: 'plancha', setNumber: 2), isTrue);
      expect(t.aplicaA(exerciseId: 'plancha', setNumber: 3), isFalse);
      expect(t.aplicaA(exerciseId: 'hollow', setNumber: 2), isFalse);
    });
  });

  group('fromWatch exige los CUATRO datos', () {
    // Una cuenta sin identidad no se puede ubicar, y dibujarla en la fila
    // equivocada le mata al atleta una serie que estaba aguantando. Ante
    // cualquier faltante, nada.
    final fin = arranque.add(const Duration(seconds: 30));

    test('con todo presente arma el espejo del reloj', () {
      final t = DurationTimerState.fromWatch(
        exerciseId: 'plancha',
        setNumber: 2,
        totalSeconds: 30,
        endsAt: fin,
      );

      expect(t, isNotNull);
      expect(t!.owner, DurationTimerOwner.reloj);
      expect(t.endsAt, fin);
      expect(t.totalSeconds, 30);
    });

    test('sin ejercicio no hay espejo', () {
      expect(
        DurationTimerState.fromWatch(
          exerciseId: null,
          setNumber: 2,
          totalSeconds: 30,
          endsAt: fin,
        ),
        isNull,
      );
      expect(
        DurationTimerState.fromWatch(
          exerciseId: '',
          setNumber: 2,
          totalSeconds: 30,
          endsAt: fin,
        ),
        isNull,
      );
    });

    test('sin número de serie no hay espejo', () {
      expect(
        DurationTimerState.fromWatch(
          exerciseId: 'plancha',
          setNumber: null,
          totalSeconds: 30,
          endsAt: fin,
        ),
        isNull,
      );
      // Cero no es un número de serie: las series empiezan en 1.
      expect(
        DurationTimerState.fromWatch(
          exerciseId: 'plancha',
          setNumber: 0,
          totalSeconds: 30,
          endsAt: fin,
        ),
        isNull,
      );
    });

    test('sin instante de fin no hay espejo', () {
      expect(
        DurationTimerState.fromWatch(
          exerciseId: 'plancha',
          setNumber: 2,
          totalSeconds: 30,
          endsAt: null,
        ),
        isNull,
      );
    });

    test('sin duración total no hay espejo: el anillo no se puede dibujar', () {
      expect(
        DurationTimerState.fromWatch(
          exerciseId: 'plancha',
          setNumber: 2,
          totalSeconds: null,
          endsAt: fin,
        ),
        isNull,
      );
    });
  });
}
