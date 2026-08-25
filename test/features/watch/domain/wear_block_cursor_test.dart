import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/exercise_cursor.dart';
import 'package:treino/features/workout/domain/superset_blocks.dart';
import 'package:treino/features/watch/domain/wear_block_cursor.dart';

void main() {
  int cursor(List<int> planned, List<int> logged, List<int?> groups) =>
      wearCurrentExerciseIndex(
        plannedSets: planned,
        loggedSets: logged,
        supersetGroups: groups,
      );

  group('superserie A/B/C — el caso reportado en la muñeca', () {
    // Tres ejercicios, tres series cada uno, todos en la misma superserie.
    // El orden correcto es 1a 1b 1c 2a 2b 2c 3a 3b 3c: el reloj muestra UN
    // ejercicio por vez, así que si el cursor no rota, las series 1b y 1c no
    // hay forma de marcarlas.
    const planned = [3, 3, 3];
    const grupos = <int?>[1, 1, 1];

    test('recorre el bloque en round-robin, no ejercicio por ejercicio', () {
      // Se simula el entreno entero marcando de a una serie y anotando en qué
      // ejercicio queda parado el reloj después de cada toque.
      final logged = [0, 0, 0];
      final recorrido = <int>[];

      for (var toque = 0; toque < 9; toque++) {
        final indice = cursor(planned, logged, grupos);
        recorrido.add(indice);
        logged[indice]++;
      }

      // a b c  a b c  a b c
      expect(recorrido, [0, 1, 2, 0, 1, 2, 0, 1, 2]);
    });

    test('después de marcar 1a ofrece 1b, NO 2a', () {
      // El síntoma exacto que se vio en el reloj.
      expect(cursor(planned, [1, 0, 0], grupos), 1);
    });

    test('recién vuelve a A cuando B y C cerraron la ronda', () {
      expect(cursor(planned, [1, 1, 0], grupos), 2);
      expect(cursor(planned, [1, 1, 1], grupos), 0);
    });
  });

  group('bloques de miembros desparejos', () {
    test('cuando el más corto termina, el otro sigue solo', () {
      // A pide 3 series y B pide 2: la ronda 3 es sólo de A. Mirar únicamente
      // los pendientes es lo que evita que el bloque se trabe acá.
      const planned = [3, 2];
      const grupos = <int?>[7, 7];

      expect(cursor(planned, [0, 0], grupos), 0); // 1a
      expect(cursor(planned, [1, 0], grupos), 1); // 1b
      expect(cursor(planned, [1, 1], grupos), 0); // 2a
      expect(cursor(planned, [2, 1], grupos), 1); // 2b
      expect(cursor(planned, [2, 2], grupos), 0); // 3a — B ya cerró
    });
  });

  group('qué NO es una superserie', () {
    test('un grupo con un solo miembro avanza como ejercicio suelto', () {
      // Pasa al borrar ejercicios de una superserie de dos. Para el CURSOR da
      // igual: un round-robin de uno es un ejercicio normal. La distinción sólo
      // le importa al teléfono, que lo dibuja distinto.
      expect(cursor([3, 3], [0, 0], const [5, null]), 0);
      expect(cursor([3, 3], [1, 0], const [5, null]), 0);
      expect(cursor([3, 3], [3, 0], const [5, null]), 1);
    });

    test('mismo número de grupo pero NO contiguos son dos bloques', () {
      // El agrupamiento es por contigüidad. Si no, un número reusado más
      // adelante en el día se tragaría un ejercicio del medio.
      const grupos = <int?>[2, null, 2];
      expect(cursor([1, 1, 1], [0, 0, 0], grupos), 0);
      expect(cursor([1, 1, 1], [1, 0, 0], grupos), 1);
      expect(cursor([1, 1, 1], [1, 1, 0], grupos), 2);
    });
  });

  group('sin superseries es exactamente el cursor de siempre', () {
    test('coincide con firstUnfinishedExerciseIndex en todos los estados', () {
      // La garantía de que esto es una GENERALIZACIÓN y no un cambio de
      // conducta: con todos los grupos en null, la respuesta tiene que ser la
      // misma que la de la función bajo contrato de conformance.
      const planned = [3, 2, 4];
      const sinGrupos = <int?>[null, null, null];

      for (var a = 0; a <= 4; a++) {
        for (var b = 0; b <= 3; b++) {
          for (var c = 0; c <= 5; c++) {
            final logged = [a, b, c];
            expect(
              cursor(planned, logged, sinGrupos),
              firstUnfinishedExerciseIndex(
                plannedSets: planned,
                loggedSets: logged,
              ),
              reason: 'divergen en $logged',
            );
          }
        }
      }
    });
  });

  group('bordes', () {
    test('un plan vacío da 0 y no un índice negativo', () {
      expect(cursor(const [], const [], const []), 0);
    });

    test('todo completo se queda en el último, no en una pantalla vacía', () {
      expect(cursor([2, 2], [2, 2], const [1, 1]), 1);
    });

    test('series de MÁS no traban el cursor', () {
      // El teléfono puede agregar series más allá del plan. Con `==` en vez de
      // `>=` el bloque quedaría pendiente para siempre.
      expect(cursor([2, 2], [5, 2], const [1, 1]), 1);
      expect(cursor([2, 2], [5, 5], const [1, 1]), 1);
    });

    test('retrocede si el teléfono borra una serie del bloque', () {
      // «Siempre absoluto»: el cursor se recalcula, así que puede volver.
      expect(cursor([2, 2], [2, 2], const [1, 1]), 1);
      expect(cursor([2, 2], [1, 2], const [1, 1]), 0);
    });

    test('una lista de grupos más corta que el plan no desalinea nada', () {
      expect(cursor([1, 1, 1], [0, 0, 0], const [null]), 0);
      expect(cursor([1, 1, 1], [1, 0, 0], const [null]), 1);
    });

    test('loggedSets más corta que el plan asume ceros', () {
      expect(cursor([1, 1, 1], const [], const [null, null, null]), 0);
    });
  });

  group('supersetBlockIndices', () {
    test('agrupa contiguos y deja sueltos los demás', () {
      expect(
        supersetBlockIndices(const [null, 1, 1, 1, null]),
        [
          [0],
          [1, 2, 3],
          [4],
        ],
      );
    });

    test('dos superseries seguidas con números distintos no se mezclan', () {
      expect(
        supersetBlockIndices(const [1, 1, 2, 2]),
        [
          [0, 1],
          [2, 3],
        ],
      );
    });

    test('lista vacía da lista vacía', () {
      expect(supersetBlockIndices(const []), isEmpty);
    });

    test('un grupo solitario da un bloque de uno, igual que sin grupo', () {
      // La partición NO distingue: quien necesita saber si es superserie usa
      // `length >= 2` sobre esto.
      expect(supersetBlockIndices(const [5, null]), [
        [0],
        [1],
      ]);
      expect(supersetBlockIndices(const [5, 6]), [
        [0],
        [1],
      ]);
    });
  });
}
