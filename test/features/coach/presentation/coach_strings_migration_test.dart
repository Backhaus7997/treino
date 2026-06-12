// T-I18N-012 RED — SCENARIO-761
// CoachStrings ARB key existence and value verbatim tests.
//
// These tests verify that AppL10n exposes all CoachStrings keys
// with verbatim es-AR values. Keys do NOT exist yet in ARB — RED.
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
  group('AppL10n — CoachStrings keys (SCENARIO-761)', () {
    // ── TrainersListScreen ─────────────────────────────────────────────────
    testWidgets('coachAppBarTitle verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachAppBarTitle, 'Entrenadores');
    });
    testWidgets('coachLoadingLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachLoadingLabel, 'Cargando entrenadores…');
    });
    testWidgets('coachErrorLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachErrorLabel, 'No pudimos cargar los entrenadores.');
    });
    testWidgets('coachRetryLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachRetryLabel, 'Reintentar');
    });
    testWidgets('coachEmptyLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachEmptyLabel, 'No encontramos entrenadores en tu zona.');
    });
    testWidgets('coachMapToggleLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachMapToggleLabel, 'Mapa');
    });
    testWidgets('coachMapProximamente verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachMapProximamente, 'Próximamente');
    });

    // ── TrainerListTile ────────────────────────────────────────────────────
    testWidgets('coachDistanceUnknown verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachDistanceUnknown, '—');
    });
    testWidgets('coachMonthlyRateUnit verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachMonthlyRateUnit, '/mes');
    });

    // ── TrainerSpecialtyChips ──────────────────────────────────────────────
    testWidgets('coachSpecialtyAll verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachSpecialtyAll, 'Todos');
    });

    // ── TrainerStatsRow ────────────────────────────────────────────────────
    testWidgets('coachStatsReviewsLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachStatsReviewsLabel, 'RESEÑAS');
    });
    testWidgets('coachStatsExperienceLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachStatsExperienceLabel, 'AÑOS EXP');
    });
    testWidgets('coachStatsStudentsLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachStatsStudentsLabel, 'ALUMNOS');
    });
    testWidgets('coachStatsPlaceholder verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachStatsPlaceholder, '—');
    });

    // ── TrainerPublicProfileScreen ─────────────────────────────────────────
    testWidgets('coachProfileLoadingLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachProfileLoadingLabel, 'Cargando perfil…');
    });
    testWidgets('coachProfileErrorLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachProfileErrorLabel, 'No pudimos cargar este perfil.');
    });
    testWidgets('coachProfileNotFoundLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachProfileNotFoundLabel, 'Entrenador no encontrado.');
    });
    testWidgets('coachProfileBioEmpty verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachProfileBioEmpty, 'Sin descripción.');
    });
    testWidgets('coachProfileRateLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachProfileRateLabel, 'Tarifa mensual');
    });

    // ── TrainerContactCtaStub ──────────────────────────────────────────────
    testWidgets('coachCtaLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachCtaLabel, 'PEDIR VÍNCULO');
    });
    testWidgets('coachCtaProximamente verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachCtaProximamente, 'Próximamente — Etapa 3');
    });

    // ── LocationPermissionRationaleSheet ───────────────────────────────────
    testWidgets('coachLocationSheetTitle verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachLocationSheetTitle, 'Permitir ubicación');
    });
    testWidgets('coachLocationSheetBody verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(
        l10n.coachLocationSheetBody,
        'TREINO usa tu ubicación para mostrarte entrenadores cerca tuyo. '
            'Tu ubicación no es visible para otros usuarios.',
      );
    });
    testWidgets('coachLocationSheetAccept verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachLocationSheetAccept, 'ACEPTAR');
    });
    testWidgets('coachLocationSheetDeny verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachLocationSheetDeny, 'Ahora no');
    });

    // ── Coach Plans (MiPlan) ───────────────────────────────────────────────
    testWidgets('coachMiPlanTitle verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachMiPlanTitle, 'MI PLAN');
    });
    testWidgets('coachMiPlanEmpty verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachMiPlanEmpty, 'No tenés rutina asignada todavía.');
    });
    testWidgets('coachMiPlanError verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachMiPlanError, 'Error al cargar tu plan.');
    });
    testWidgets('coachMiPlanFinalizado verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachMiPlanFinalizado, 'Plan finalizado');
    });
    testWidgets('coachMiPlanCurrent verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachMiPlanCurrent, 'Actual');
    });
    testWidgets('coachAssignedByPrefix verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachAssignedByPrefix, 'Asignado por ');
    });
    testWidgets('coachAssignedByLoading verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachAssignedByLoading, 'Asignado por …');
    });
    testWidgets('coachAssignedByError verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachAssignedByError, 'Asignado por un PF');
    });
    testWidgets('coachCreatePlanCta verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachCreatePlanCta, 'CREAR PLAN');
    });
    testWidgets('coachCreatePlanSuccess verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachCreatePlanSuccess, 'Plan creado y asignado.');
    });
    testWidgets('coachCreatePlanError verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(
        l10n.coachCreatePlanError,
        'No pudimos crear el plan. Intentá de nuevo.',
      );
    });
    testWidgets('coachAthleteDetailNoPlans verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachAthleteDetailNoPlans, 'Todavía no le asignaste planes.');
    });
    testWidgets('coachEditorTitle verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachEditorTitle, 'Crear plan');
    });
    testWidgets('coachEditorEditTitle verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachEditorEditTitle, 'Editar plan');
    });
    testWidgets('coachEditorNameLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachEditorNameLabel, 'NOMBRE');
    });
    testWidgets('coachEditorSplitLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachEditorSplitLabel, 'SPLIT (e.g. PPL)');
    });
    testWidgets('coachEditorAddDay verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachEditorAddDay, 'Agregar día');
    });
    testWidgets('coachEditorAddSlot verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachEditorAddSlot, 'Agregar ejercicio');
    });
    testWidgets('coachEditorAddSuperset verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachEditorAddSuperset, '+ Superserie');
    });
    testWidgets('coachEditorSubmit verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachEditorSubmit, 'ASIGNAR PLAN');
    });
    testWidgets('coachEditorUpdateLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachEditorUpdateLabel, 'GUARDAR CAMBIOS');
    });
    testWidgets('coachUpdatePlanSuccess verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachUpdatePlanSuccess, 'Plan actualizado.');
    });
    testWidgets('coachExercisePicker verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.coachExercisePicker, 'Buscar ejercicio');
    });
  });
}
