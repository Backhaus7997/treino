// Log performance test screen i18n key existence + verbatim tests.
//
// Covers performance/presentation/log_performance_test_screen.dart, which
// previously used hardcoded Spanish literals instead of AppL10n. These tests
// FAIL until the performance ARB keys are added and codegen is re-run.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/l10n/app_l10n.dart';

Future<AppL10n> _pumpAndGetL10n(WidgetTester tester, Locale locale) async {
  late AppL10n captured;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppL10n.supportedLocales,
      locale: locale,
      home: Builder(
        builder: (context) {
          captured = AppL10n.of(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return captured;
}

void main() {
  group('AppL10n — log performance screen keys (es_AR)', () {
    Future<AppL10n> es(WidgetTester t) =>
        _pumpAndGetL10n(t, const Locale('es', 'AR'));

    testWidgets('header + actions verbatim', (tester) async {
      final l10n = await es(tester);
      expect(l10n.performanceLogTitle, 'Cargar evaluación');
      expect(l10n.performanceLogCancel, 'Cancelar');
      expect(l10n.performanceLogSaveCta, 'GUARDAR EVALUACIÓN');
    });

    testWidgets('snackbars verbatim', (tester) async {
      final l10n = await es(tester);
      expect(
        l10n.performanceLogNoSession,
        'No hay sesión activa. No se puede guardar.',
      );
      expect(l10n.performanceLogSaveSuccess, 'Evaluación guardada');
      expect(
        l10n.performanceLogSaveError,
        'No pudimos guardar la evaluación. Probá de nuevo.',
      );
    });

    testWidgets('section labels verbatim', (tester) async {
      final l10n = await es(tester);
      expect(l10n.performanceLogSectionJumps, 'SALTOS (cm)');
      expect(l10n.performanceLogSectionSpeed, 'VELOCIDAD (seg)');
      expect(l10n.performanceLogSectionStrength, 'FUERZA 1RM (kg)');
      expect(l10n.performanceLogSectionEndurance, 'RESISTENCIA / OTROS');
      expect(l10n.performanceLogSectionNotes, 'NOTAS');
    });

    testWidgets('translatable field labels verbatim', (tester) async {
      final l10n = await es(tester);
      expect(l10n.performanceLogFieldBroadJump, 'Salto largo');
      expect(l10n.performanceLogFieldSquat1rm, 'Sentadilla');
      expect(l10n.performanceLogFieldBenchPress, 'Press banca');
      expect(l10n.performanceLogFieldDeadlift, 'Peso muerto');
      expect(l10n.performanceLogFieldOverheadPress, 'Press militar');
      expect(l10n.performanceLogFieldPullUp, 'Dominada lastrada');
      expect(l10n.performanceLogFieldSitAndReach, 'Flexibilidad sit-and-reach');
      expect(l10n.performanceLogNotesHint, 'Observaciones del entrenador…');
    });
  });

  group('AppL10n — log performance screen keys (en)', () {
    testWidgets('strings localize to English', (tester) async {
      final l10n = await _pumpAndGetL10n(tester, const Locale('en'));
      expect(l10n.performanceLogTitle, 'Log assessment');
      expect(l10n.performanceLogCancel, 'Cancel');
      expect(l10n.performanceLogSaveCta, 'SAVE ASSESSMENT');
      expect(l10n.performanceLogSaveSuccess, 'Assessment saved');
      expect(l10n.performanceLogSectionJumps, 'JUMPS (cm)');
      expect(l10n.performanceLogFieldDeadlift, 'Deadlift');
    });
  });
}
