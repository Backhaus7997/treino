// Rangos de levantamiento: el mapeo entero → LiftRank, qué rango lee cada
// dimensión del perfil, y que cada rango tenga su insignia declarada.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/gym_rankings/domain/lift_rank.dart';
import 'package:treino/features/gym_rankings/domain/ranking_dimension.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';

void main() {
  group('LiftRank.fromValue', () {
    test('0..8 mapea en orden a none … olympian', () {
      const esperado = [
        LiftRank.none,
        LiftRank.bronze,
        LiftRank.silver,
        LiftRank.gold,
        LiftRank.platinum,
        LiftRank.diamond,
        LiftRank.champion,
        LiftRank.titan,
        LiftRank.olympian,
      ];
      for (var i = 0; i < esperado.length; i++) {
        expect(LiftRank.fromValue(i), esperado[i], reason: 'valor $i');
      }
    });

    test('el orden del enum ES el entero que guarda la Cloud Function', () {
      // Si alguien reordena el enum, los docs ya escritos cambian de rango en
      // silencio: este test es el que lo frena.
      expect(LiftRank.none.index, 0);
      expect(LiftRank.bronze.index, 1);
      expect(LiftRank.olympian.index, 8);
      expect(LiftRank.values.length, 9);
    });

    test('null y todo lo fuera de 0..8 es "sin dato", no "sin rango"', () {
      expect(LiftRank.fromValue(null), isNull);
      expect(LiftRank.fromValue(-1), isNull);
      expect(LiftRank.fromValue(9), isNull);
      expect(LiftRank.fromValue(99), isNull);
    });
  });

  group('LiftRank — insignia', () {
    test('los discos por lado son el rango mismo', () {
      expect(LiftRank.none.plates, 0);
      expect(LiftRank.bronze.plates, 1);
      expect(LiftRank.olympian.plates, 8);
    });

    test('none usa unranked y el resto su propio nombre', () {
      expect(LiftRank.none.assetName, 'unranked');
      expect(LiftRank.bronze.assetName, 'bronze');
      expect(LiftRank.olympian.assetPath, 'assets/ranking_ranks/olympian.svg');
    });

    test('cada rango tiene su SVG en el repo', () {
      for (final rank in LiftRank.values) {
        expect(File(rank.assetPath).existsSync(), isTrue,
            reason: '${rank.assetPath} no existe — '
                'corré `dart run tool/build_lift_rank_badges.dart`');
      }
    });

    test('pubspec declara la carpeta de insignias', () {
      // Los directorios de assets no son recursivos: sin esta línea las
      // insignias están en el repo pero no en el APK, y SvgPicture.asset falla
      // recién en runtime.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('- assets/ranking_ranks/'));
    });
  });

  group('liftRankFor', () {
    const perfil = UserPublicProfile(
      uid: 'u1',
      squatRank: 5,
      benchRank: 0,
      deadliftRank: 8,
    );

    test('cada levantamiento lee su propio campo', () {
      expect(liftRankFor(RankingDimension.squat, perfil), LiftRank.diamond);
      expect(liftRankFor(RankingDimension.bench, perfil), LiftRank.none);
      expect(liftRankFor(RankingDimension.deadlift, perfil), LiftRank.olympian);
    });

    test('rachas y volumen no tienen rango', () {
      expect(liftRankFor(RankingDimension.streak, perfil), isNull);
      expect(liftRankFor(RankingDimension.volume, perfil), isNull);
    });

    test('un perfil sin rangos escritos devuelve null en los tres', () {
      const sinRangos = UserPublicProfile(uid: 'u2');
      for (final d in [
        RankingDimension.squat,
        RankingDimension.bench,
        RankingDimension.deadlift,
      ]) {
        expect(liftRankFor(d, sinRangos), isNull);
      }
    });

    test('un valor corrupto en el doc no inventa un rango', () {
      const corrupto = UserPublicProfile(uid: 'u3', squatRank: 42);
      expect(liftRankFor(RankingDimension.squat, corrupto), isNull);
    });

    test('dimensionHasLiftRank es true sólo para los tres levantamientos', () {
      expect(dimensionHasLiftRank(RankingDimension.squat), isTrue);
      expect(dimensionHasLiftRank(RankingDimension.bench), isTrue);
      expect(dimensionHasLiftRank(RankingDimension.deadlift), isTrue);
      expect(dimensionHasLiftRank(RankingDimension.streak), isFalse);
      expect(dimensionHasLiftRank(RankingDimension.volume), isFalse);
    });
  });

  group('UserPublicProfile — rangos en el JSON', () {
    test('los lee del doc de Firestore', () {
      final p = UserPublicProfile.fromJson({
        'uid': 'u1',
        'squatRank': 3,
        'benchRank': null,
        'deadliftRank': 8,
      });
      expect(p.squatRank, 3);
      expect(p.benchRank, isNull);
      expect(p.deadliftRank, 8);
    });

    test('un doc viejo, sin los campos, sigue decodificando', () {
      final p = UserPublicProfile.fromJson({'uid': 'u1', 'bestSquatKg': 100});
      expect(p.squatRank, isNull);
      expect(p.benchRank, isNull);
      expect(p.deadliftRank, isNull);
    });
  });
}
