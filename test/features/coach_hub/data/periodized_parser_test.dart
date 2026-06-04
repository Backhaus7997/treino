import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/data/excel_parser.dart';
import 'package:treino/features/coach_hub/data/periodized_template_builder.dart';
import 'package:treino/features/profile/domain/experience_level.dart';

void main() {
  group('parsePeriodizedExcelBytes', () {
    test('el template periodizado generado se puede parsear', () {
      final bytes = buildPeriodizedTemplateBytes();
      final plan = parsePeriodizedExcelBytes(bytes);

      expect(plan.name, 'Fuerza tren superior');
      expect(plan.level, ExperienceLevel.intermediate);
      expect(plan.daysPerWeek, 4);
      expect(plan.durationWeeks, 6);

      // El ejemplo trae 2 semanas cargadas (1 y 2).
      expect(plan.weeks.map((w) => w.weekNumber).toList(), [1, 2]);
    });

    test('agrupa por semana → día y respeta el Orden', () {
      final bytes = buildPeriodizedTemplateBytes();
      final plan = parsePeriodizedExcelBytes(bytes);

      final week1 = plan.weeks.firstWhere((w) => w.weekNumber == 1);
      expect(week1.days, hasLength(1));

      final day1 = week1.days.single;
      expect(day1.dayNumber, 1);
      expect(
        day1.items.map((i) => i.rowName).toList(),
        ['Press banca', 'Remo con barra', 'Press militar'],
      );
      // Bloque "A" en los dos primeros (superserie), suelto el tercero.
      expect(day1.items[0].block, 'A');
      expect(day1.items[1].block, 'A');
      expect(day1.items[2].block, isNull);
    });

    test('la semana 2 progresa la prescripción', () {
      final bytes = buildPeriodizedTemplateBytes();
      final plan = parsePeriodizedExcelBytes(bytes);

      final pressW1 = plan.weeks
          .firstWhere((w) => w.weekNumber == 1)
          .days
          .single
          .items
          .firstWhere((i) => i.rowName == 'Press banca');
      final pressW2 = plan.weeks
          .firstWhere((w) => w.weekNumber == 2)
          .days
          .single
          .items
          .firstWhere((i) => i.rowName == 'Press banca');

      expect(pressW1.repsMax, 8);
      expect(pressW2.repsMax, 10); // progresión
      expect(pressW2.weightKg, greaterThan(pressW1.weightKg!));
    });
  });
}
