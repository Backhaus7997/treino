// T-I18N-PR3a2 RED — routine_editor_screen.dart ARB key existence tests
//
// Groups A-G: all 24 keys for routine_editor_screen periodization migration.
// These tests will FAIL until ARB keys are added and codegen is re-run.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/l10n/app_l10n.dart';

Future<AppL10n> _pumpAndGetL10n(WidgetTester tester) async {
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
      locale: const Locale('es', 'AR'),
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
  group('AppL10n — PR#3a2 routine_editor_screen keys', () {
    // ── Group A — Duplicar semana dialog ──────────────────────────────────
    testWidgets('Group A: routineEditorDuplicateWeekTitle verbatim',
        (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.routineEditorDuplicateWeekTitle, 'Duplicar semana');
    });

    testWidgets('Group A: routineEditorDuplicateWeekBody with placeholders',
        (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(
        l10n.routineEditorDuplicateWeekBody(1, 2),
        'Se copiará la Semana 1 en la Semana 2.',
      );
    });

    testWidgets('Group A: routineEditorDialogCancel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.routineEditorDialogCancel, 'Cancelar');
    });

    testWidgets('Group A: routineEditorDialogConfirm verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.routineEditorDialogConfirm, 'Confirmar');
    });

    // ── Group B — Eliminar scope dialog ───────────────────────────────────
    testWidgets('Group B: routineEditorDeleteScopeTitle verbatim',
        (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(
        l10n.routineEditorDeleteScopeTitle,
        '¿Eliminar solo de esta semana o de todas?',
      );
    });

    testWidgets('Group B: routineEditorScopeOnlyThisWeek verbatim',
        (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.routineEditorScopeOnlyThisWeek, 'Solo esta semana');
    });

    testWidgets('Group B: routineEditorScopeAllWeeks verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.routineEditorScopeAllWeeks, 'Todas las semanas');
    });

    // ── Group C — Agregar scope dialog ────────────────────────────────────
    testWidgets('Group C: routineEditorAddScopeTitle verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.routineEditorAddScopeTitle, '¿En qué semanas agregar?');
    });

    testWidgets('Group C: routineEditorAddScopeBody verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(
        l10n.routineEditorAddScopeBody,
        '¿Agregar el ejercicio solo en esta semana o en todas?',
      );
    });

    testWidgets('Group C: routineEditorAddOnlyThisWeek verbatim',
        (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(
          l10n.routineEditorAddOnlyThisWeek, 'Agregar solo en esta semana');
    });

    testWidgets('Group C: routineEditorAddAllWeeks verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.routineEditorAddAllWeeks, 'Agregar en todas las semanas');
    });

    // ── Group D — Week presence bar / actions ─────────────────────────────
    testWidgets('Group D: routineEditorWeekLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.routineEditorWeekLabel, 'Semana');
    });

    testWidgets('Group D: routineEditorRemoveLastWeek verbatim',
        (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.routineEditorRemoveLastWeek, 'Quitar última');
    });

    // routineEditorDuplicateWeekTitle reused for action bar — already tested in Group A

    // ── Group E — Section labels ───────────────────────────────────────────
    testWidgets('Group E: routineEditorLevelSection verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.routineEditorLevelSection, 'NIVEL');
    });

    testWidgets('Group E: routineEditorWeeksSection verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.routineEditorWeeksSection, 'SEMANAS');
    });

    testWidgets('Group E: routineEditorDaysSection verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.routineEditorDaysSection, 'DÍAS DEL PLAN');
    });

    // ── Group F — Form hints ───────────────────────────────────────────────
    testWidgets('Group F: routineEditorNameHint verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.routineEditorNameHint, 'Ej: Fuerza PPL');
    });

    testWidgets('Group F: routineEditorSplitHint verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.routineEditorSplitHint, 'PPL / Full Body');
    });

    testWidgets('Group F: routineEditorIncompleteSetsLabel with placeholder',
        (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(
        l10n.routineEditorIncompleteSetsLabel(3),
        'Sets incompletos en Sem 3',
      );
    });

    // ── Group G — SetType menu ─────────────────────────────────────────────
    testWidgets('Group G: routineEditorSetTypeNormal verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.routineEditorSetTypeNormal, 'Normal');
    });

    testWidgets('Group G: routineEditorSetTypeWarmup verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.routineEditorSetTypeWarmup, 'Entrada en calor (W)');
    });

    testWidgets('Group G: routineEditorSetTypeDrop verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.routineEditorSetTypeDrop, 'Drop (D)');
    });

    testWidgets('Group G: routineEditorSetTypeFailure verbatim',
        (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.routineEditorSetTypeFailure, 'Al fallo (F)');
    });
  });
}
