import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/assessment/domain/anthropometry/anthropometric_indices.dart';
import 'package:treino/features/assessment/domain/anthropometry/anthropometric_profile.dart';

void main() {
  // ─── BSA ────────────────────────────────────────────────────────────────────
  group('bsaDuBois (Du Bois 1916)', () {
    // SCENARIO-410: Known BSA value
    // W=70kg, H=170cm
    // BSA = 0.007184 * 170^0.725 * 70^0.425
    //     = 0.007184 * 45.376 * 10.778
    //     = 0.007184 * 489.03 ≈ 3.5143 × 0.543... let's be precise:
    // 170^0.725: ln(170)=5.1358 → 0.725*5.1358=3.7235 → e^3.7235=41.434
    // 70^0.425:  ln(70)=4.2485 → 0.425*4.2485=1.8056 → e^1.8056=6.083
    // BSA = 0.007184 * 41.434 * 6.083 = 0.007184 * 252.0 ≈ 1.811
    test('SCENARIO-410: W=70kg H=170cm → BSA ≈ 1.81 m²', () {
      expect(bsaDuBois(70.0, 170.0), closeTo(1.81, 0.02));
    });

    // SCENARIO-411: Larger athlete W=90kg H=180cm
    // 180^0.725: ln(180)=5.1930 → 0.725*5.1930=3.7650 → e^3.7650=43.165
    // 90^0.425:  ln(90)=4.4998 → 0.425*4.4998=1.9124 → e^1.9124=6.770
    // BSA = 0.007184 * 43.165 * 6.770 = 0.007184 * 292.23 ≈ 2.100
    test('SCENARIO-411: W=90kg H=180cm → BSA ≈ 2.10 m²', () {
      expect(bsaDuBois(90.0, 180.0), closeTo(2.10, 0.02));
    });
  });

  // ─── BMI ────────────────────────────────────────────────────────────────────
  group('bmi', () {
    // SCENARIO-412: W=70kg H=175cm → BMI = 70 / (1.75^2) = 70 / 3.0625 = 22.857
    test('SCENARIO-412: W=70kg H=175cm → BMI ≈ 22.86', () {
      expect(bmi(70.0, 175.0), closeTo(22.857, 0.01));
    });
  });

  // ─── HWR ────────────────────────────────────────────────────────────────────
  group('hwr (ponderal index)', () {
    // SCENARIO-413: W=75kg H=175cm
    // ∛75 = 4.2172... → hwr = 175/4.2172 = 41.498
    test('SCENARIO-413: W=75kg H=175cm → HWR ≈ 41.50', () {
      expect(hwr(75.0, 175.0), closeTo(41.50, 0.05));
    });
  });

  // ─── WAIST-HIP RATIO ────────────────────────────────────────────────────────
  group('waistHipRatio', () {
    test('SCENARIO-414: waist=80 hip=100 → ratio=0.80', () {
      expect(waistHipRatio(80.0, 100.0), closeTo(0.80, 0.001));
    });
  });

  // ─── WAIST-HIP RISK ─────────────────────────────────────────────────────────
  group('waistHipRisk (Holway proforma table)', () {
    // MEN 20-29: <0.83=bajo, .83-.88=moderado, .89-.94=alto, >.94=muyAlto

    test('SCENARIO-415: male 25y ratio=0.75 → bajo', () {
      expect(waistHipRisk(Sex.male, 25, 0.75), WaistHipRisk.bajo);
    });

    test('SCENARIO-416: male 25y ratio=0.85 → moderado', () {
      expect(waistHipRisk(Sex.male, 25, 0.85), WaistHipRisk.moderado);
    });

    test('SCENARIO-417: male 25y ratio=0.91 → alto', () {
      expect(waistHipRisk(Sex.male, 25, 0.91), WaistHipRisk.alto);
    });

    test('SCENARIO-418: male 25y ratio=0.95 → muyAlto', () {
      expect(waistHipRisk(Sex.male, 25, 0.95), WaistHipRisk.muyAlto);
    });

    // WOMEN 20-29: <0.71=bajo, .71-.77=moderado, .78-.82=alto, >.82=muyAlto

    test('SCENARIO-419: female 25y ratio=0.65 → bajo', () {
      expect(waistHipRisk(Sex.female, 25, 0.65), WaistHipRisk.bajo);
    });

    test('SCENARIO-420: female 25y ratio=0.74 → moderado', () {
      expect(waistHipRisk(Sex.female, 25, 0.74), WaistHipRisk.moderado);
    });

    test('SCENARIO-421: female 25y ratio=0.80 → alto', () {
      expect(waistHipRisk(Sex.female, 25, 0.80), WaistHipRisk.alto);
    });

    test('SCENARIO-422: female 25y ratio=0.85 → muyAlto', () {
      expect(waistHipRisk(Sex.female, 25, 0.85), WaistHipRisk.muyAlto);
    });

    // Age clamping: age < 20 → treated as 20-29 band
    test('SCENARIO-423: male age=15 (clamped to 20-29) ratio=0.75 → bajo', () {
      expect(waistHipRisk(Sex.male, 15, 0.75), WaistHipRisk.bajo);
    });

    // Age clamping: age > 69 → treated as 60-69 band
    // MEN 60-69: <0.91=bajo, .91-.98=moderado, .99-1.03=alto, >1.03=muyAlto
    test('SCENARIO-424: male age=75 (clamped to 60-69) ratio=0.95 → moderado',
        () {
      expect(waistHipRisk(Sex.male, 75, 0.95), WaistHipRisk.moderado);
    });

    // Different age band: MEN 50-59 <0.90=bajo
    test('SCENARIO-425: male 55y ratio=0.88 → bajo (50-59 band)', () {
      expect(waistHipRisk(Sex.male, 55, 0.88), WaistHipRisk.bajo);
    });

    // WOMEN 50-59: <0.74=bajo, .74-.81=moderado, .82-.88=alto, >.88=muyAlto
    test('SCENARIO-426: female 55y ratio=0.85 → alto (50-59 band)', () {
      expect(waistHipRisk(Sex.female, 55, 0.85), WaistHipRisk.alto);
    });
  });

  // ─── HARRIS-BENEDICT BMR ────────────────────────────────────────────────────
  group('bmrHarrisBenedict (1919)', () {
    // SCENARIO-430: Male W=70kg H=175cm age=30
    // BMR = 66.4730 + 13.7516*70 + 5.0033*175 - 6.7550*30
    //     = 66.4730 + 962.612 + 875.5775 - 202.65
    //     = 1702.0125 ≈ 1702.01
    test('SCENARIO-430: male W=70 H=175 age=30 → BMR ≈ 1702 kcal', () {
      expect(
          bmrHarrisBenedict(Sex.male, 70.0, 175.0, 30), closeTo(1702.0, 1.0));
    });

    // SCENARIO-431: Female W=60kg H=165cm age=30
    // BMR = 655.0955 + 9.5634*60 + 1.8496*165 - 4.6756*30
    //     = 655.0955 + 573.804 + 305.184 - 140.268
    //     = 1393.8155 ≈ 1393.82
    test('SCENARIO-431: female W=60 H=165 age=30 → BMR ≈ 1393.8 kcal', () {
      expect(
          bmrHarrisBenedict(Sex.female, 60.0, 165.0, 30), closeTo(1393.8, 1.0));
    });
  });

  // ─── CUNNINGHAM BMR ─────────────────────────────────────────────────────────
  group('bmrCunningham (1991)', () {
    // SCENARIO-432: FFM=60kg → BMR = 370 + 21.6*60 = 370 + 1296 = 1666
    test('SCENARIO-432: FFM=60kg → BMR = 1666 kcal', () {
      expect(bmrCunningham(60.0), closeTo(1666.0, 0.1));
    });

    // SCENARIO-433: FFM=40kg → BMR = 370 + 21.6*40 = 370 + 864 = 1234
    test('SCENARIO-433: FFM=40kg → BMR = 1234 kcal', () {
      expect(bmrCunningham(40.0), closeTo(1234.0, 0.1));
    });
  });
}
