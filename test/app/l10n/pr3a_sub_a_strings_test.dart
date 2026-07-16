// T-I18N-SUB-A RED — PR#3a Sub-task A ARB key existence tests
//
// Covers:
//   - app/app.dart → appFcmSnackBarActionLabel
//   - profile/presentation/profile_edit_personal_screen.dart (5 validator keys)
//   - profile/presentation/widgets/eliminar_cuenta_sheet.dart (9 keys)
//   - coach/presentation/trainer_dashboard_tab.dart (9 keys)
//   - reviews/presentation/widgets/review_bottom_sheet.dart (1 key)
//   - workout/presentation/widgets/plantillas_section.dart (1 key)
//   - profile_setup/presentation/profile_setup_flow.dart (4 keys)
//
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
  group('AppL10n — PR#3a Sub-task A keys', () {
    // app.dart — FCM SnackBar action
    testWidgets('appFcmSnackBarActionLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.appFcmSnackBarActionLabel, 'Ver');
    });

    // profile_edit_personal_screen.dart — 5 validator keys
    testWidgets('profileEditPersonalNameRequired verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.profileEditPersonalNameRequired, 'Ingresá un nombre');
    });

    testWidgets('profileEditPersonalNameMaxLength verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.profileEditPersonalNameMaxLength, 'Máximo 50 caracteres');
    });

    testWidgets('profileEditPersonalWeightInvalidNumber verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.profileEditPersonalWeightInvalidNumber, 'Ingresá un número válido');
    });

    testWidgets('profileEditPersonalWeightOutOfRange verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.profileEditPersonalWeightOutOfRange, 'Ingresá un peso entre 30 y 300 kg');
    });

    testWidgets('profileEditPersonalHeightOutOfRange verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.profileEditPersonalHeightOutOfRange, 'Ingresá una altura entre 120 y 230 cm');
    });

    // eliminar_cuenta_sheet.dart — 9 keys
    testWidgets('eliminarCuentaSheetTitle verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.eliminarCuentaSheetTitle, 'Eliminar cuenta');
    });

    testWidgets('eliminarCuentaSheetBodyPrefix verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.eliminarCuentaSheetBodyPrefix, 'Esta acción es ');
    });

    testWidgets('eliminarCuentaSheetBodyBold verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.eliminarCuentaSheetBodyBold, 'irreversible');
    });

    testWidgets('eliminarCuentaSheetBodySuffix verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(
        l10n.eliminarCuentaSheetBodySuffix,
        '. Vamos a eliminar tu cuenta, tu perfil, tu historial '
        'de entrenamientos, tus posts y tu foto.',
      );
    });

    testWidgets('eliminarCuentaSheetDeleteCta verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.eliminarCuentaSheetDeleteCta, 'ELIMINAR');
    });

    testWidgets('eliminarCuentaSheetCancelCta verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.eliminarCuentaSheetCancelCta, 'CANCELAR');
    });

    testWidgets('eliminarCuentaSheetLoadingLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.eliminarCuentaSheetLoadingLabel, 'Eliminando tu cuenta...');
    });

    testWidgets('eliminarCuentaSheetLoadingSubtitle verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.eliminarCuentaSheetLoadingSubtitle, 'Esto puede tardar unos segundos.');
    });

    testWidgets('eliminarCuentaSheetErrorFallback verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(
        l10n.eliminarCuentaSheetErrorFallback,
        'No pudimos eliminar tu cuenta. Probá de nuevo.',
      );
    });

    testWidgets('eliminarCuentaSheetRetryLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.eliminarCuentaSheetRetryLabel, 'Reintentar');
    });

    // trainer_dashboard_tab.dart — 9 keys
    testWidgets('dashboardResumenDelDiaTitle verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.dashboardResumenDelDiaTitle, 'RESUMEN DEL DÍA');
    });

    testWidgets('dashboardStatPendientes verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.dashboardStatPendientes, 'PENDIENTES');
    });

    testWidgets('dashboardStatCompletadas verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.dashboardStatCompletadas, 'COMPLETADAS');
    });

    testWidgets('dashboardStatCanceladas verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.dashboardStatCanceladas, 'CANCELADAS');
    });

    testWidgets('dashboardProximasSesionesSectionLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.dashboardProximasSesionesSectionLabel, 'PRÓXIMAS SESIONES');
    });

    testWidgets('dashboardAgendaTrailingLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.dashboardAgendaTrailingLabel, 'Agenda');
    });

    testWidgets('dashboardEntrenaronHoySectionLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.dashboardEntrenaronHoySectionLabel, 'ENTRENARON HOY');
    });

    testWidgets('dashboardDejarFeedbackLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.dashboardDejarFeedbackLabel, 'Dejar feedback');
    });

    testWidgets('dashboardActividadRecienteSectionLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.dashboardActividadRecienteSectionLabel, 'ACTIVIDAD RECIENTE');
    });

    // review_bottom_sheet.dart — 1 key
    testWidgets('reviewSnackBarSuccess verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.reviewSnackBarSuccess, '¡Gracias por tu reseña!');
    });

    // plantillas_section.dart — 1 key
    testWidgets('plantillasRetryLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.plantillasRetryLabel, 'Reintentar');
    });

    // profile_setup_flow.dart — 4 keys
    testWidgets('profileSetupSaveError verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(
        l10n.profileSetupSaveError,
        'No pudimos guardar tu perfil. Probá de nuevo.',
      );
    });

    testWidgets('profileSetupCancelDialogTitle verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(
        l10n.profileSetupCancelDialogTitle,
        '¿Cancelar la creación de tu cuenta?',
      );
    });

    testWidgets('profileSetupCancelDialogBody verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(
        l10n.profileSetupCancelDialogBody,
        'Vamos a borrar tu cuenta. Esta acción no se puede deshacer.',
      );
    });

    testWidgets('profileSetupCancelAccountError verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(
        l10n.profileSetupCancelAccountError,
        'No pudimos cancelar la cuenta. Probá de nuevo.',
      );
    });
  });
}
