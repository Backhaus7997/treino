// ARB key existence and value verbatim tests for the measurements + reviews
// l10n migration (#510).
//
// The hardcoded es-AR copy that used to live inline in
// MeasurementProgressChart, LogMeasurementScreen and the reviews widgets is now
// behind AppL10n keys. These tests pin the es-AR values verbatim so a rename or
// a copy edit that silently changes what the user reads fails here first —
// several widget tests still assert this copy through `find.text(...)`.
//
// Same shape as workout_strings_migration_test.dart / agenda_strings_migration_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/l10n/app_l10n.dart';

// ── Helper ─────────────────────────────────────────────────────────────────

AppL10n _l10n(WidgetTester tester) =>
    AppL10n.of(tester.element(find.byType(SizedBox)));

Widget _harness() => MaterialApp(
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: const Scaffold(body: SizedBox.shrink()),
    );

// ── Tests ──────────────────────────────────────────────────────────────────

void main() {
  group('AppL10n — MeasurementProgressChart keys (#510)', () {
    testWidgets('section label + metric chips', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      final l = _l10n(t);
      expect(l.measurementChartSectionLabel, 'PROGRESO');
      expect(l.measurementChartMetricWeight, 'Peso');
      expect(l.measurementChartMetricBodyFat, '% Graso');
      expect(l.measurementChartMetricMuscleMass, 'Masa muscular');
      expect(l.measurementChartMetricWaist, 'Cintura');
      expect(l.measurementChartMetricChest, 'Pecho');
      expect(l.measurementChartMetricHips, 'Cadera');
      expect(l.measurementChartMetricShoulders, 'Hombros');
      expect(l.measurementChartMetricGlutes, 'Glúteos');
      expect(l.measurementChartMetricBiceps, 'Bíceps');
      expect(l.measurementChartMetricBicepsFlexed, 'Bíceps flex');
      expect(l.measurementChartMetricForearm, 'Antebrazo');
      expect(l.measurementChartMetricUpperThigh, 'Muslo sup');
      expect(l.measurementChartMetricMidThigh, 'Muslo medio');
      expect(l.measurementChartMetricCalf, 'Gemelo');
    });

    testWidgets('span label — ICU plural on both branches', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      final l = _l10n(t);
      expect(l.measurementChartSpanDays(1), '(1 día)');
      expect(l.measurementChartSpanDays(3), '(3 días)');
      expect(l.measurementChartSpanWeeks(1), '(1 semana)');
      expect(l.measurementChartSpanWeeks(6), '(6 semanas)');
    });
  });

  group('AppL10n — LogMeasurementScreen keys (#510)', () {
    testWidgets('titles, CTAs and snackbars', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      final l = _l10n(t);
      expect(l.measurementLogTitleCreate, 'Cargar medición');
      expect(l.measurementLogTitleEdit, 'Editar medición');
      expect(l.measurementLogSaveCta, 'GUARDAR MEDICIÓN');
      expect(l.measurementLogUpdateCta, 'GUARDAR CAMBIOS');
      expect(
        l.measurementLogNoSession,
        'No hay sesión activa. No se puede guardar.',
      );
      expect(l.measurementLogSaveSuccess, 'Medición guardada');
      expect(l.measurementLogUpdateSuccess, 'Medición actualizada');
      expect(
        l.measurementLogSaveError,
        'No pudimos guardar la medición. Probá de nuevo.',
      );
    });

    testWidgets('body composition section', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      final l = _l10n(t);
      expect(l.measurementLogSectionBodyComposition, 'COMPOSICIÓN CORPORAL');
      expect(l.measurementLogFieldWeight, 'Peso (kg)');
      expect(l.measurementLogFieldBodyFat, 'Grasa (%)');
      expect(l.measurementLogFieldMuscleMass, 'Masa muscular (kg)');
      expect(l.measurementLogSectionNotes, 'NOTAS');
      expect(l.measurementLogNotesHint, 'Observaciones del entrenador…');
    });

    testWidgets('circumferences section', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      final l = _l10n(t);
      expect(l.measurementLogCircumferencesTitle, 'CIRCUNFERENCIAS');
      expect(
        l.measurementLogCircumferencesHint,
        'Opcional. Cargá las que quieras.',
      );
      expect(l.measurementLogGroupTrunk, 'TRONCO');
      expect(l.measurementLogGroupUpperBody, 'TREN SUPERIOR');
      expect(l.measurementLogGroupLowerBody, 'TREN INFERIOR');
      expect(l.measurementLogFieldShoulders, 'Hombros');
      expect(l.measurementLogFieldChest, 'Pecho');
      expect(l.measurementLogFieldWaist, 'Cintura');
      expect(l.measurementLogFieldHips, 'Cadera');
      expect(l.measurementLogFieldGlutes, 'Glúteos');
      expect(l.measurementLogFieldBiceps, 'Bíceps');
      expect(l.measurementLogFieldBicepsFlexed, 'Bíceps (flex)');
      expect(l.measurementLogFieldForearm, 'Antebrazo');
      expect(l.measurementLogFieldUpperThigh, 'Muslo superior');
      expect(l.measurementLogFieldMidThigh, 'Muslo medio');
      expect(l.measurementLogFieldCalf, 'Gemelo');
      expect(l.measurementLogBilateralLeftHint, 'I (cm)');
      expect(l.measurementLogBilateralRightHint, 'D (cm)');
    });
  });

  group('AppL10n — reviews keys (#510)', () {
    testWidgets('ReviewBottomSheet', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      final l = _l10n(t);
      expect(l.reviewSheetTitleEdit, 'Editá tu reseña');
      expect(
        l.reviewSheetTitleThirtyDay('Ana'),
        'Ya llevás un mes entrenando con Ana. ¿Cómo va?',
      );
      expect(
        l.reviewSheetTitleStandard('Ana'),
        '¿Cómo fue tu experiencia con Ana?',
      );
      expect(l.reviewSheetCommentHint, 'Contanos cómo fue (opcional)');
      expect(l.reviewSheetCancel, 'CANCELAR');
      expect(l.reviewSheetSubmit, 'ENVIAR');
      expect(
        l.reviewSnackBarError,
        'No pudimos guardar tu reseña. Probá de nuevo.',
      );
    });

    testWidgets('ReviewCta + TrainerReviewsSection', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      final l = _l10n(t);
      expect(l.reviewCtaCreate, 'DEJAR UNA RESEÑA');
      expect(l.reviewCtaEdit, 'EDITAR MI RESEÑA');
      expect(l.reviewTrainerFallbackName, 'tu Personal Trainer');
      expect(l.reviewsSectionTitle, 'RESEÑAS');
      expect(l.reviewsSectionEmpty, 'Sin reseñas todavía');
    });

    testWidgets('ReviewTile — deleted author + relative dates', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      final l = _l10n(t);
      expect(l.reviewTileDeletedUser, 'Usuario eliminado');
      expect(l.reviewTileDateToday, 'hoy');
      expect(l.reviewTileDateDaysAgo(1), 'hace 1 día');
      expect(l.reviewTileDateDaysAgo(5), 'hace 5 días');
      expect(l.reviewTileDateMonthsAgo(1), 'hace 1 mes');
      expect(l.reviewTileDateMonthsAgo(4), 'hace 4 meses');
    });
  });
}
