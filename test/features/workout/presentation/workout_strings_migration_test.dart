// WorkoutStrings ARB key existence and value verbatim tests.
// These tests verify that AppL10n exposes all WorkoutStrings keys
// with the exact es-AR copy that was in workout_strings.dart.
//
// RED → GREEN cycle:
//   RED  (T-I18N-017/018): this file; keys do not exist yet in ARB → all fail
//   GREEN (T-I18N-019): add keys to ARB, migrate call sites, delete workout_strings.dart

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
  group('AppL10n — WorkoutStrings keys (SCENARIO-763)', () {
    // ── Post-workout summary ──────────────────────────────────────────────
    testWidgets('workoutSummaryHeaderCompleted', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutSummaryHeaderCompleted, 'BUEN ENTRENO');
    });

    testWidgets('workoutSummaryHeaderAbandoned', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutSummaryHeaderAbandoned, 'SESIÓN INTERRUMPIDA');
    });

    testWidgets('workoutStatDuration', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutStatDuration, 'DURACIÓN');
    });

    testWidgets('workoutStatVolume', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutStatVolume, 'VOLUMEN');
    });

    testWidgets('workoutStatSets', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutStatSets, 'SETS');
    });

    testWidgets('workoutStatPrsToday', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutStatPrsToday, 'PRs HOY');
    });

    testWidgets('workoutStatPrsTodayStub', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutStatPrsTodayStub, '—');
    });

    testWidgets('workoutPrsSectionTitle', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutPrsSectionTitle, 'PRS DE LA SESIÓN');
    });

    testWidgets('workoutPrsPlaceholder', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutPrsPlaceholder, 'Próximamente');
    });

    testWidgets('workoutButtonDone', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutButtonDone, 'LISTO');
    });

    testWidgets('workoutButtonShare', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutButtonShare, 'COMPARTIR');
    });

    testWidgets('workoutButtonRetry', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutButtonRetry, 'Reintentar');
    });

    testWidgets('workoutButtonBackToWorkout', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutButtonBackToWorkout, 'Volver a Entrenar');
    });

    testWidgets('workoutNotFoundTitle', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutNotFoundTitle, 'Sesión no encontrada');
    });

    testWidgets('workoutErrorTitle', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutErrorTitle, 'No pudimos cargar tu sesión');
    });

    testWidgets('workoutSnackShareSuccess', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutSnackShareSuccess, '¡Post compartido!');
    });

    testWidgets('workoutSnackShareError', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutSnackShareError,
          'No pudimos compartir tu post. Intentá de nuevo.');
    });

    testWidgets('workoutPostAutoCompleteText', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutPostAutoCompleteText, '¡Terminé mi entreno! 💪');
    });

    // ── Historial ────────────────────────────────────────────────────────
    testWidgets('workoutHistorialHeading', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutHistorialHeading, 'HISTORIAL');
    });

    testWidgets('workoutHistorialEmptyMessage', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutHistorialEmptyMessage, 'Todavía no entrenaste.');
    });

    testWidgets('workoutHistorialEmptyCta', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutHistorialEmptyCta, 'Empezar entrenamiento');
    });

    testWidgets('workoutHistorialErrorMessage', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutHistorialErrorMessage,
          'No pudimos cargar tu historial.');
    });

    testWidgets('workoutHistorialErrorRetry', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutHistorialErrorRetry, 'Reintentar');
    });

    testWidgets('workoutHistorialCardKgSuffix', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutHistorialCardKgSuffix, ' kg');
    });

    testWidgets('workoutHistorialCardMinSuffix', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutHistorialCardMinSuffix, ' min');
    });

    testWidgets('workoutHistorialShowLess', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutHistorialShowLess, 'Ver menos');
    });

    testWidgets('workoutHistorialShowMore — ICU interpolation', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutHistorialShowMore(3), 'Ver más (3)');
    });

    // ── Session detail screen ─────────────────────────────────────────────
    testWidgets('workoutDetailStatDuration', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutDetailStatDuration, 'DURACIÓN');
    });

    testWidgets('workoutDetailStatSets', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutDetailStatSets, 'SETS');
    });

    testWidgets('workoutDetailStatVolume', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutDetailStatVolume, 'VOLUMEN');
    });

    testWidgets('workoutDetailStatPrsToday', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutDetailStatPrsToday, 'PRS HOY');
    });

    testWidgets('workoutDetailPrBadge', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutDetailPrBadge, 'PR');
    });

    // ── Self-creating editor ──────────────────────────────────────────────
    testWidgets('workoutSelfEditorTitle', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutSelfEditorTitle, 'Nueva rutina');
    });

    testWidgets('workoutSelfEditorEditTitle', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutSelfEditorEditTitle, 'Editar rutina');
    });

    testWidgets('workoutSelfEditorSubmitLabel', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutSelfEditorSubmitLabel, 'CREAR RUTINA');
    });

    testWidgets('workoutSelfEditorUpdateLabel', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutSelfEditorUpdateLabel, 'GUARDAR CAMBIOS');
    });

    testWidgets('workoutSelfEditorSuccess', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutSelfEditorSuccess, 'Rutina creada');
    });

    testWidgets('workoutSelfEditorUpdateSuccess', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutSelfEditorUpdateSuccess, 'Rutina actualizada');
    });

    testWidgets('workoutSelfEditorNotFound', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutSelfEditorNotFound,
          'Esta rutina ya no existe. Volvé y actualizá la lista.');
    });

    testWidgets('workoutSelfEditorError', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutSelfEditorError,
          'No pudimos crear la rutina. Reintentá.');
    });

    testWidgets('workoutSelfEditorPermissionDenied', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutSelfEditorPermissionDenied,
          'No tenés permisos para hacer esto. Recargá la app.');
    });

    testWidgets('workoutEditStubToast', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutEditStubToast,
          'Pronto vas a poder editar el contenido. Por ahora podés archivar y crear de nuevo.');
    });

    testWidgets('workoutSelfEditorCapReached', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutSelfEditorCapReached,
          'Llegaste al máximo de 10 rutinas activas.');
    });

    // ── Mis Rutinas section ───────────────────────────────────────────────
    testWidgets('workoutMisRutinasSectionTitle', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutMisRutinasSectionTitle, 'MIS RUTINAS');
    });

    testWidgets('workoutMisRutinasCta', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutMisRutinasCta, 'CREAR RUTINA');
    });

    testWidgets('workoutMisRutinasCtaDisabledTooltip', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutMisRutinasCtaDisabledTooltip,
          'Llegaste al máximo de 10 rutinas activas. Archivá una para crear otra.');
    });

    testWidgets('workoutMisRutinasEmptyState', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutMisRutinasEmptyState,
          'Todavía no creaste ninguna rutina. Tocá CREAR RUTINA para armar la primera.');
    });

    testWidgets('workoutMisRutinasError', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(
          _l10n(t).workoutMisRutinasError, 'No pudimos cargar tus rutinas.');
    });

    testWidgets('workoutMisRutinasErrorRetry', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutMisRutinasErrorRetry, 'Reintentar');
    });

    testWidgets('workoutMisRutinasOverflowEdit', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutMisRutinasOverflowEdit, 'EDITAR');
    });

    testWidgets('workoutMisRutinasOverflowArchive', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutMisRutinasOverflowArchive, 'ARCHIVAR');
    });

    testWidgets('workoutMisRutinasConfirmTitle', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutMisRutinasConfirmTitle, 'Archivar rutina');
    });

    testWidgets('workoutMisRutinasConfirmBody', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutMisRutinasConfirmBody,
          'La rutina dejará de aparecer en MIS RUTINAS. Tu historial se conserva.');
    });

    testWidgets('workoutMisRutinasConfirmCancel', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutMisRutinasConfirmCancel, 'CANCELAR');
    });

    testWidgets('workoutMisRutinasConfirmConfirm', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutMisRutinasConfirmConfirm, 'ARCHIVAR');
    });

    testWidgets('workoutMisRutinasArchiveSuccess', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutMisRutinasArchiveSuccess, 'Rutina archivada');
    });

    testWidgets('workoutMisRutinasArchiveError', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutMisRutinasArchiveError,
          'No pudimos archivar la rutina. Reintentá.');
    });

    // ── Split fallback ────────────────────────────────────────────────────
    testWidgets('workoutSplitFallback', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutSplitFallback, 'Sin split');
    });

    // ── Exercise picker filter strings ────────────────────────────────────
    testWidgets('workoutPickerMuscleFilter', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutPickerMuscleFilter, 'Músculos');
    });

    testWidgets('workoutPickerEquipmentFilter', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutPickerEquipmentFilter, 'Equipamiento');
    });

    testWidgets('workoutPickerMuscleSheetTitle', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutPickerMuscleSheetTitle, 'Grupo muscular');
    });

    testWidgets('workoutPickerEquipmentSheetTitle', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutPickerEquipmentSheetTitle, 'Tipo de equipo');
    });

    testWidgets('workoutPickerMuscleAll', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutPickerMuscleAll, 'Todos los músculos');
    });

    testWidgets('workoutPickerEquipmentAll', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutPickerEquipmentAll, 'Todo el equipamiento');
    });

    testWidgets('workoutPickerEmptyFiltered', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(
          _l10n(t).workoutPickerEmptyFiltered, 'Ningún ejercicio coincide');
    });

    testWidgets('workoutPickerEmptyFilteredHint', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutPickerEmptyFilteredHint,
          'Probá quitando un filtro o ajustando la búsqueda.');
    });

    testWidgets('workoutPickerAddButton — ICU count=1', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutPickerAddButton(1), 'Agregar 1 ejercicio');
    });

    testWidgets('workoutPickerAddButton — ICU count=3', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutPickerAddButton(3), 'Agregar 3 ejercicios');
    });

    // ── Athlete name hint ─────────────────────────────────────────────────
    testWidgets('workoutSelfEditorNameHint', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutSelfEditorNameHint, 'Mi rutina');
    });

    // ── Filter sheet CTAs ─────────────────────────────────────────────────
    testWidgets('workoutPickerSheetClear', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutPickerSheetClear, 'Limpiar');
    });

    testWidgets('workoutPickerSheetApplyAll', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutPickerSheetApplyAll, 'APLICAR (TODOS)');
    });

    testWidgets('workoutPickerSheetApply — ICU count=3', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).workoutPickerSheetApply(3), 'APLICAR (3)');
    });
  });
}
