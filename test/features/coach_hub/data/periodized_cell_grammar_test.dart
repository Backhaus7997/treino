import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/data/periodized_cell_grammar.dart';
import 'package:treino/features/workout/domain/set_enums.dart';
import 'package:treino/features/workout/domain/set_spec.dart';

List<List<SetSpec>> _expand(String raw, {bool warmup = false}) {
  final p = parseWeekCell(raw);
  expect(p.isOk, isTrue, reason: '${p.error}');
  return expandAtoms(p.atoms, warmup: warmup);
}

void main() {
  group('parseWeekCell — tokens', () {
    test('NxR: N series de R reps', () {
      final s = _expand('3x8').single;
      expect(s, List.filled(3, const SetSpec(reps: 8)));
    });

    test('N solo: 1 serie de N reps', () {
      expect(_expand('12').single, [const SetSpec(reps: 12)]);
    });

    test('NxMax: N series al fallo, sin reps', () {
      expect(
        _expand('3xMAX').single,
        List.filled(3, const SetSpec(type: SetType.failure)),
      );
    });

    test('max solo: 1 serie al fallo', () {
      expect(_expand('max').single, [const SetSpec(type: SetType.failure)]);
    });

    test("N': minutos como 1 serie de duración", () {
      expect(_expand("8'").single, [const SetSpec(durationSeconds: 480)]);
    });

    test("NxM': N series de M minutos", () {
      expect(
        _expand("2x5'").single,
        List.filled(2, const SetSpec(durationSeconds: 300)),
      );
    });

    test('Nm: 1 serie de N metros', () {
      expect(_expand('6m').single, [const SetSpec(distanceMeters: 6)]);
    });

    test('NxNm: N series de metros, con coma decimal', () {
      expect(
        _expand('4x2,5m').single,
        List.filled(4, const SetSpec(distanceMeters: 2.5)),
      );
    });

    test('sin distinguir mayúsculas, espacios ni × tipográfica', () {
      expect(_expand(' 3 X 8 ').single, List.filled(3, const SetSpec(reps: 8)));
      expect(_expand('3×8').single, List.filled(3, const SetSpec(reps: 8)));
      expect(_expand('8’').single, [const SetSpec(durationSeconds: 480)]);
    });

    test('calificadores c/pierna, c/brazo, c/lado', () {
      for (final q in ['c/pierna', 'c/brazo', 'c/lado']) {
        final p = parseWeekCell('3x10 $q');
        expect(p.isOk, isTrue);
        expect(p.atoms.single.qualifier, q);
        expect(p.atoms.single.series, 3);
      }
      expect(parseWeekCell('10').atoms.single.qualifier, isNull);
    });
  });

  group('expandAtoms — series y átomos', () {
    test('propaga las series del primer átomo a todos los componentes', () {
      final r = _expand('3x4+2+6m');
      expect(r[0], List.filled(3, const SetSpec(reps: 4)));
      expect(r[1], List.filled(3, const SetSpec(reps: 2)));
      expect(r[2], List.filled(3, const SetSpec(distanceMeters: 6)));
    });

    test('un átomo posterior con su propio conteo lo conserva', () {
      final r = _expand("8'+3x20");
      expect(r[0], [const SetSpec(durationSeconds: 480)]);
      expect(r[1], List.filled(3, const SetSpec(reps: 20)));
    });

    test('conteos propios por átomo', () {
      final r = _expand('3x10+4x12');
      expect(r[0], hasLength(3));
      expect(r[1], hasLength(4));
    });

    test('tiempo o distancia sin conteo son 1 serie cuando nadie trae series',
        () {
      final r = _expand("5'+20m");
      expect(r[0], hasLength(1));
      expect(r[1], hasLength(1));
    });

    test('warmup fuerza SetType.warmup en todas las series', () {
      final r = _expand('2x10+max', warmup: true);
      expect(r.expand((e) => e).every((s) => s.type == SetType.warmup), isTrue);
    });
  });

  group('parseWeekCell — ilegibles', () {
    for (final bad in [
      'abc',
      '3x',
      'x8',
      '3x8+',
      '+3x8',
      '3x8++2',
      '0x8',
      '3x0',
      '0m',
      "0'",
      '3x8 c/cabeza',
      '3x8c/',
      '1.5',
      '3-4',
      '100x5',
    ]) {
      test('"$bad" falla con mensaje', () {
        final p = parseWeekCell(bad);
        expect(p.isOk, isFalse);
        expect(p.error, isNotEmpty);
      });
    }
  });

  group('parseRest', () {
    final cases = <String, int>{
      '90': 90,
      "1'": 60,
      "1'30": 90,
      "1'30''": 90,
      "90''": 90,
      '90"': 90,
      "2'": 120,
      "1' 30": 90,
      '': 60,
      '   ': 60,
    };
    cases.forEach((raw, secs) {
      test('"$raw" = $secs s', () {
        final r = parseRest(raw);
        expect(r.isOk, isTrue);
        expect(r.seconds, secs);
      });
    });

    for (final bad in ['abc', "1'75", '1,5', '-5', "1'30'''x"]) {
      test('"$bad" es inválido', () {
        expect(parseRest(bad).isOk, isFalse);
      });
    }
  });
}
