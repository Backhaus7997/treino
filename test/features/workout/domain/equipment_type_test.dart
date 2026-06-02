import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/equipment_type.dart';

void main() {
  group('EquipmentType', () {
    group('fromJson — known values', () {
      test('returns mancuerna for "mancuerna"', () {
        expect(EquipmentType.fromJson('mancuerna'), EquipmentType.mancuerna);
      });

      test('returns barra for "barra"', () {
        expect(EquipmentType.fromJson('barra'), EquipmentType.barra);
      });

      test('returns maquina for "maquina"', () {
        expect(EquipmentType.fromJson('maquina'), EquipmentType.maquina);
      });

      test('returns cable for "cable"', () {
        expect(EquipmentType.fromJson('cable'), EquipmentType.cable);
      });

      test('returns banda for "banda"', () {
        expect(EquipmentType.fromJson('banda'), EquipmentType.banda);
      });

      test('returns pesoCorporal for "peso_corporal" (snake_case round-trip)',
          () {
        expect(
          EquipmentType.fromJson('peso_corporal'),
          EquipmentType.pesoCorporal,
        );
      });

      test('returns cardio for "cardio"', () {
        expect(EquipmentType.fromJson('cardio'), EquipmentType.cardio);
      });

      test('returns otro for "otro"', () {
        expect(EquipmentType.fromJson('otro'), EquipmentType.otro);
      });

      test('returns ninguno for "ninguno"', () {
        expect(EquipmentType.fromJson('ninguno'), EquipmentType.ninguno);
      });
    });

    group('fromJson — null and unknown', () {
      test('returns null for null input', () {
        expect(EquipmentType.fromJson(null), isNull);
      });

      test('returns null for unknown string (does not throw)', () {
        expect(EquipmentType.fromJson('unknown_string'), isNull);
      });

      test('returns null for empty string', () {
        expect(EquipmentType.fromJson(''), isNull);
      });
    });

    group('jsonValue — snake_case wire format', () {
      test('every value round-trips via jsonValue → fromJson', () {
        for (final v in EquipmentType.values) {
          expect(
            EquipmentType.fromJson(v.jsonValue),
            v,
            reason: '${v.name}.jsonValue = "${v.jsonValue}" should round-trip',
          );
        }
      });

      test('pesoCorporal.jsonValue is "peso_corporal"', () {
        expect(EquipmentType.pesoCorporal.jsonValue, equals('peso_corporal'));
      });
    });

    group('label — Spanish display strings', () {
      test('mancuerna label is "Mancuerna"', () {
        expect(EquipmentType.mancuerna.label, equals('Mancuerna'));
      });

      test('barra label is "Barra"', () {
        expect(EquipmentType.barra.label, equals('Barra'));
      });

      test('maquina label is "Máquina"', () {
        expect(EquipmentType.maquina.label, equals('Máquina'));
      });

      test('cable label is "Cable"', () {
        expect(EquipmentType.cable.label, equals('Cable'));
      });

      test('banda label is "Banda"', () {
        expect(EquipmentType.banda.label, equals('Banda'));
      });

      test('pesoCorporal label is "Peso corporal"', () {
        expect(EquipmentType.pesoCorporal.label, equals('Peso corporal'));
      });

      test('cardio label is "Cardio"', () {
        expect(EquipmentType.cardio.label, equals('Cardio'));
      });

      test('otro label is "Otro"', () {
        expect(EquipmentType.otro.label, equals('Otro'));
      });

      test('ninguno label is "Ninguno"', () {
        expect(EquipmentType.ninguno.label, equals('Ninguno'));
      });
    });
  });
}
