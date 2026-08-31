// El parser de entrada rápida (#870): `banca 4x10 60`.
//
// Es puro y no depende de widgets a propósito: la parte que puede equivocarse
// —qué es un número, qué es un nombre, qué pasa con "4 X 10"— se prueba sin
// montar una pantalla.
//
// Regla de oro: **nunca falla**. Una línea que no entiende devuelve la línea
// entera como búsqueda y la prescripción por defecto. El picker completo sigue
// estando, así que este atajo puede darse el lujo de ser tolerante.
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/set_limits.dart';
import 'package:treino/features/workout/presentation/widgets/quick_entry_parser.dart';

void main() {
  group('el patrón sets × reps', () {
    test('4x10 60 — la forma canónica', () {
      final r = parseQuickEntry('banca 4x10 60');
      expect(r.query, 'banca');
      expect(r.sets, 4);
      expect(r.reps, 10);
      expect(r.weightKg, 60);
    });

    test('acepta espacios y la X mayúscula', () {
      final r = parseQuickEntry('banca 4 X 10 60');
      expect(r.sets, 4);
      expect(r.reps, 10);
      expect(r.weightKg, 60);
    });

    test('acepta la × tipográfica que ofrece el teclado de iOS', () {
      final r = parseQuickEntry('banca 4×10');
      expect(r.sets, 4);
      expect(r.reps, 10);
      expect(r.weightKg, isNull);
    });

    test('coma decimal — el teclado es-AR ofrece coma, no punto', () {
      expect(parseQuickEntry('banca 4x10 60,5').weightKg, 60.5);
      expect(parseQuickEntry('banca 4x10 60.5').weightKg, 60.5);
    });

    test('el nombre puede ir antes o después del patrón', () {
      expect(parseQuickEntry('4x10 press banca').query, 'press banca');
      expect(parseQuickEntry('press 4x10 banca').query, 'press banca',
          reason: 'lo que rodea al patrón se une con un espacio');
    });
  });

  group('lo que no dice, lo pone por defecto', () {
    test('un nombre solo entra con 3 sets vacíos', () {
      final r = parseQuickEntry('banca');
      expect(r.query, 'banca');
      expect(r.sets, QuickEntry.kDefaultSets);
      expect(r.reps, isNull, reason: 'los sets se completan después');
      expect(r.weightKg, isNull);
      expect(r.tienePrescripcion, isFalse);
    });

    test('sin peso, los sets quedan sin peso — que es un estado legítimo', () {
      final r = parseQuickEntry('dominadas 4x8');
      expect(r.sets, 4);
      expect(r.reps, 8);
      expect(r.weightKg, isNull,
          reason: 'peso corporal se prescribe justamente así');
      expect(r.tienePrescripcion, isTrue);
    });

    test('un número suelto NO es una prescripción', () {
      final r = parseQuickEntry('10');
      expect(r.query, '10', reason: 'sin la x no hay patrón: es búsqueda');
      expect(r.sets, QuickEntry.kDefaultSets);
      expect(r.reps, isNull);
    });

    test('string vacío no rompe', () {
      final r = parseQuickEntry('');
      expect(r.query, '');
      expect(r.sets, QuickEntry.kDefaultSets);
    });

    test('sólo espacios tampoco', () {
      expect(parseQuickEntry('   ').query, '');
    });
  });

  group('los topes del dominio se respetan', () {
    test('las reps se recortan a kMaxReps en vez de rechazarse', () {
      final r = parseQuickEntry('banca 4x99999');
      expect(r.reps, kMaxReps,
          reason: 'mismo criterio que BoundedNumberFormatter al tipear: '
              'recorta, no rechaza');
    });

    test('el peso se recorta a kMaxWeightKg', () {
      expect(parseQuickEntry('banca 4x10 99999').weightKg, kMaxWeightKg);
    });

    test('un 999x10 no arma novecientas filas', () {
      final r = parseQuickEntry('banca 999x10');
      expect(r.sets, lessThanOrEqualTo(20));
      expect(r.reps, 10, reason: 'las reps no se tocan por acotar los sets');
    });

    test('0x10 sube a 1 set — cero sets no es un ejercicio', () {
      expect(parseQuickEntry('banca 0x10').sets, 1);
    });

    test('un peso de 0 es "sin peso", no un 0 kg prescripto', () {
      expect(parseQuickEntry('banca 4x10 0').weightKg, isNull);
    });
  });

  group('igualdad', () {
    test('dos lecturas de la misma línea son iguales', () {
      expect(parseQuickEntry('banca 4x10 60'),
          equals(parseQuickEntry('banca 4x10 60')));
    });

    test('y distintas si cambia cualquier campo', () {
      expect(parseQuickEntry('banca 4x10'),
          isNot(equals(parseQuickEntry('banca 4x11'))));
    });
  });
}
