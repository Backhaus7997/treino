// El parser de entrada rápida (#870, ampliado en la revisión del 31/08).
//
// Es puro y no depende de widgets a propósito: la parte que puede equivocarse
// —qué es un número, qué es un nombre, qué pasa con "4 X 10", dónde termina
// una lista y empieza la otra— se prueba sin montar una pantalla.
//
// **La gramática en una frase: la COMA encadena la misma lista, el ESPACIO
// abre la siguiente.** Y la coma pide un espacio detrás, porque también es el
// separador decimal de es-AR.
//
// Regla de oro: **nunca falla**. Una línea que no entiende devuelve la línea
// entera como búsqueda y la prescripción por defecto. El picker completo sigue
// estando, así que este atajo puede darse el lujo de ser tolerante.
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/set_limits.dart';
import 'package:treino/features/workout/presentation/widgets/quick_entry_parser.dart';

void main() {
  group('la forma simple', () {
    test('4x10 60 — sets, reps y peso', () {
      final r = parseQuickEntry('banca 4x10 60');
      expect(r.query, 'banca');
      expect(r.sets, 4);
      expect(r.reps, [10]);
      expect(r.weights, [60]);
    });

    test('un solo valor se repite en todos los sets', () {
      final r = parseQuickEntry('banca 4x10 60');
      for (var i = 0; i < 4; i++) {
        expect(r.repsDeSet(i), 10, reason: 'set ${i + 1}');
        expect(r.pesoDeSet(i), 60, reason: 'set ${i + 1}');
      }
    });

    test('acepta espacios, X mayúscula y la × del teclado de iOS', () {
      expect(parseQuickEntry('banca 4 X 10 60').reps, [10]);
      expect(parseQuickEntry('banca 4×10').sets, 4);
    });

    test('el nombre puede ir antes o después del patrón', () {
      expect(parseQuickEntry('4x10 press banca').query, 'press banca');
      expect(parseQuickEntry('press 4x10 banca').query, 'press banca');
    });
  });

  group('pirámide de repeticiones — "4x10, 8, 6, 4"', () {
    test('cada set lleva las suyas', () {
      final r = parseQuickEntry('sentadilla 4x10,8,6,4');
      expect(r.query, 'sentadilla');
      expect(r.sets, 4);
      expect(r.reps, [10, 8, 6, 4]);
      expect(r.repsDeSet(0), 10);
      expect(r.repsDeSet(3), 4);
    });

    test('la lista manda sobre el número declarado', () {
      // Quien escribe `3x10, 8, 6, 4` pide cuatro series aunque haya tecleado
      // un 3: la lista es más específica que el número.
      final r = parseQuickEntry('sentadilla 3x10, 8, 6, 4');
      expect(r.sets, 4);
    });

    test('una lista más corta repite su último valor', () {
      final r = parseQuickEntry('sentadilla 4x10, 8');
      expect(r.sets, 4);
      expect(r.repsDeSet(0), 10);
      expect(r.repsDeSet(1), 8);
      expect(r.repsDeSet(2), 8, reason: 'sin valor propio, repite el último');
      expect(r.repsDeSet(3), 8);
    });
  });

  group('descarga de peso — "4x10 55, 45, 35, 25"', () {
    test('cada set lleva el suyo', () {
      final r = parseQuickEntry('sentadilla 4x10 55,45,35,25');
      expect(r.query, 'sentadilla');
      expect(r.sets, 4);
      expect(r.reps, [10]);
      expect(r.weights, [55, 45, 35, 25]);
      expect(r.pesoDeSet(0), 55);
      expect(r.pesoDeSet(3), 25);
    });

    test('las reps siguen siendo las mismas en todos', () {
      final r = parseQuickEntry('sentadilla 4x10 55, 45, 35, 25');
      for (var i = 0; i < 4; i++) {
        expect(r.repsDeSet(i), 10);
      }
    });
  });

  group('las dos listas juntas', () {
    test('reps y pesos por set, cada uno con su lista', () {
      final r = parseQuickEntry('sentadilla 4x10,8,6,4 55,45,35,25');
      expect(r.query, 'sentadilla');
      expect(r.sets, 4);
      expect(r.reps, [10, 8, 6, 4]);
      expect(r.weights, [55, 45, 35, 25]);
    });

    test('listas de largo distinto: cada una repite el suyo', () {
      final r = parseQuickEntry('sentadilla 4x10, 8, 6, 4 55, 45');
      expect(r.repsDeSet(2), 6);
      expect(r.pesoDeSet(2), 45, reason: 'la lista de pesos se quedó en dos');
      expect(r.pesoDeSet(3), 45);
    });

    test('el nombre sobrevive a las dos listas', () {
      final r = parseQuickEntry('press militar 3x12, 10, 8 40, 35, 30');
      expect(r.query, 'press militar');
    });
  });

  group('la coma SIEMPRE separa; el decimal es el punto', () {
    // La primera versión pedía un espacio detrás de la coma para poder
    // distinguirla del decimal de es-AR. Esa regla se rompió en device apenas
    // se probó: escribir `55,45,35,25` de un tirón es lo natural en un
    // teléfono, y el parser lo leía como un único peso de 55,45.
    test('sin espacios: la forma en que se escribe de verdad', () {
      final r = parseQuickEntry('banca 4x10 55,45,35,25');
      expect(r.weights, [55, 45, 35, 25], reason: 'este es EL caso que rompía');
    });

    test('con espacios da lo mismo', () {
      expect(parseQuickEntry('banca 4x10 55, 45, 35, 25').weights,
          [55, 45, 35, 25]);
    });

    test('la pirámide tampoco necesita espacios', () {
      final r = parseQuickEntry('banca 4x10,8,6,4');
      expect(r.reps, [10, 8, 6, 4],
          reason: 'antes devolvía [10] y perdía el resto en silencio');
    });

    test('el decimal va con PUNTO', () {
      expect(parseQuickEntry('banca 4x10 62.5').weights, [62.5]);
    });

    test('y una coma en su lugar abre lista, no decimal', () {
      // El intercambio, explícito: una descarga por set se escribe seguido, un
      // peso fraccionario casi nunca. La celda de la tabla sigue aceptando
      // coma cuando se edita a mano.
      expect(parseQuickEntry('banca 2x10 62,5').weights, [62, 5]);
    });
  });

  group('lo que no dice, lo pone por defecto', () {
    test('un nombre solo entra con 3 sets vacíos', () {
      final r = parseQuickEntry('banca');
      expect(r.query, 'banca');
      expect(r.sets, QuickEntry.kDefaultSets);
      expect(r.reps, isEmpty);
      expect(r.weights, isEmpty);
      expect(r.tienePrescripcion, isFalse);
      expect(r.repsDeSet(0), isNull);
    });

    test('sin peso, los sets quedan sin peso — estado legítimo', () {
      final r = parseQuickEntry('dominadas 4x8');
      expect(r.weights, isEmpty);
      expect(r.pesoDeSet(0), isNull,
          reason: 'peso corporal se prescribe justamente así');
      expect(r.tienePrescripcion, isTrue);
    });

    test('un número suelto NO es una prescripción', () {
      final r = parseQuickEntry('10');
      expect(r.query, '10');
      expect(r.reps, isEmpty);
    });

    test('string vacío y espacios no rompen', () {
      expect(parseQuickEntry('').query, '');
      expect(parseQuickEntry('   ').query, '');
      expect(parseQuickEntry('').sets, QuickEntry.kDefaultSets);
    });
  });

  group('los topes del dominio se respetan', () {
    test('las reps se recortan en vez de rechazarse', () {
      expect(parseQuickEntry('banca 4x99999').reps, [kMaxReps]);
    });

    test('el peso se recorta', () {
      expect(parseQuickEntry('banca 4x10 99999').weights, [kMaxWeightKg]);
    });

    test('una lista larga no arma cien filas', () {
      final r = parseQuickEntry('banca 999x10');
      expect(r.sets, kMaxSetsEntradaRapida);
    });

    test('0x10 sube a 1 set — cero sets no es un ejercicio', () {
      expect(parseQuickEntry('banca 0x10').sets, 1);
    });

    test('un peso de 0 es "sin peso", no un 0 kg prescripto', () {
      expect(parseQuickEntry('banca 4x10 0').weights, isEmpty);
    });
  });

  group('por tiempo — "3x30s" y "3x1:30"', () {
    test('segundos sueltos', () {
      final r = parseQuickEntry('plancha 3x30s');
      expect(r.query, 'plancha');
      expect(r.sets, 3);
      expect(r.esDuracion, isTrue);
      expect(r.durations, [30]);
      expect(r.reps, isEmpty, reason: 'es tiempo, no repeticiones');
      expect(r.duracionDeSet(2), 30);
    });

    test('formato m:ss', () {
      expect(parseQuickEntry('plancha 3x1:30').durations, [90]);
      expect(parseQuickEntry('plancha 3x0:45').durations, [45]);
    });

    test('sin la marca de tiempo son repeticiones — el caso normal', () {
      final r = parseQuickEntry('banca 3x30');
      expect(r.esDuracion, isFalse);
      expect(r.reps, [30]);
      expect(r.durations, isEmpty,
          reason: 'un número suelto no puede pedir sintaxis extra para ser '
              'lo que es el 95% de las veces');
    });

    test('una pirámide de tiempo', () {
      final r = parseQuickEntry('plancha 3x45s,30s,20s');
      expect(r.durations, [45, 30, 20]);
      expect(r.sets, 3);
    });

    test('con lastre: el peso sigue funcionando', () {
      final r = parseQuickEntry('plancha 3x30s 10');
      expect(r.durations, [30]);
      expect(r.weights, [10]);
      expect(r.query, 'plancha');
    });

    test('la S mayúscula también', () {
      expect(parseQuickEntry('plancha 3x30S').durations, [30]);
    });

    test('se acota a una hora', () {
      expect(parseQuickEntry('plancha 3x99999s').durations, [3600]);
    });
  });

  group('igualdad', () {
    test('dos lecturas de la misma línea son iguales', () {
      expect(parseQuickEntry('banca 4x10, 8 60, 55'),
          equals(parseQuickEntry('banca 4x10, 8 60, 55')));
    });

    test('y distintas si cambia cualquier lista', () {
      expect(parseQuickEntry('banca 4x10, 8'),
          isNot(equals(parseQuickEntry('banca 4x10, 6'))));
    });
  });
}
