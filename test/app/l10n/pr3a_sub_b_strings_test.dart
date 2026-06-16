// T-I18N-SUB-B RED — PR#3a Sub-task B ARB key existence tests
//
// Covers: re_auth_bottom_sheet, profile_gym_screen, profile_edit_trainer_screen,
//         athlete_detail_screen, new_session_sheet, athlete_coach_view,
//         check_in_strings migration.
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
  group('AppL10n — PR#3a Sub-task B keys', () {
    // re_auth_bottom_sheet.dart
    testWidgets('reAuthPasswordLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.reAuthPasswordLabel, 'Contraseña');
    });

    // profile_gym_screen.dart
    testWidgets('profileGymSearchHint verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.profileGymSearchHint, 'Buscar gym');
    });

    // profile_edit_trainer_screen.dart (6 keys)
    testWidgets('profileEditTrainerTitleEdit verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.profileEditTrainerTitleEdit, 'Editá tu perfil profesional');
    });

    testWidgets('profileEditTrainerTitleOnboarding verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.profileEditTrainerTitleOnboarding, 'Completá tu perfil profesional');
    });

    testWidgets('profileEditTrainerSaveSuccess verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.profileEditTrainerSaveSuccess, 'Perfil actualizado.');
    });

    testWidgets('profileEditTrainerSaveError verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.profileEditTrainerSaveError, 'No pudimos guardar. Probá de nuevo.');
    });

    testWidgets('profileEditTrainerValidationSpecialty verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.profileEditTrainerValidationSpecialty, 'Elegí una especialidad.');
    });

    testWidgets('profileEditTrainerValidationLocation verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.profileEditTrainerValidationLocation, 'Agregá al menos una ubicación o activá clases virtuales.');
    });

    // athlete_detail_screen.dart (~7 keys)
    testWidgets('athleteDetailPlansSection verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.athleteDetailPlansSection, 'PLANES ASIGNADOS');
    });

    testWidgets('athleteDetailProfileLoadError verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.athleteDetailProfileLoadError, 'No pudimos cargar este perfil.');
    });

    testWidgets('athleteDetailPlanDeleteTitle verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.athleteDetailPlanDeleteTitle, 'Eliminar plan');
    });

    testWidgets('athleteDetailPlanDeleteCancel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.athleteDetailPlanDeleteCancel, 'Cancelar');
    });

    testWidgets('athleteDetailPlanDeleteConfirm verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.athleteDetailPlanDeleteConfirm, 'Eliminar');
    });

    testWidgets('athleteDetailPlanDeleteSuccess verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.athleteDetailPlanDeleteSuccess, 'Plan eliminado.');
    });

    testWidgets('athleteDetailMessageCta verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.athleteDetailMessageCta, 'MENSAJE');
    });

    // new_session_sheet.dart (~10 keys)
    testWidgets('newSessionSheetTitle verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.newSessionSheetTitle, 'NUEVA SESIÓN');
    });

    testWidgets('newSessionSheetAlumnoLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.newSessionSheetAlumnoLabel, 'ALUMNO');
    });

    testWidgets('newSessionSheetFechaLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.newSessionSheetFechaLabel, 'FECHA');
    });

    testWidgets('newSessionSheetHoraLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.newSessionSheetHoraLabel, 'HORA DE INICIO');
    });

    testWidgets('newSessionSheetDuracionLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.newSessionSheetDuracionLabel, 'DURACIÓN (MIN)');
    });

    testWidgets('newSessionSheetNotaLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.newSessionSheetNotaLabel, 'NOTA PREVIA (OPCIONAL)');
    });

    testWidgets('newSessionSheetSubmitSingle verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.newSessionSheetSubmitSingle, 'REGISTRAR SESIÓN');
    });

    testWidgets('newSessionSheetSubmitRecurring verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.newSessionSheetSubmitRecurring, 'REGISTRAR SERIE');
    });

    testWidgets('newSessionSheetDurationError verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.newSessionSheetDurationError, 'Ingresá una duración válida (5–480 min).');
    });

    testWidgets('newSessionSheetNoActiveAthletes verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.newSessionSheetNoActiveAthletes, 'No tenés alumnos activos.');
    });

    // athlete_coach_view.dart — 2 strings
    testWidgets('athleteCoachViewTrainerFallbackName verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.athleteCoachViewTrainerFallbackName, 'tu Personal Trainer');
    });

    testWidgets('athleteCoachViewLinkError verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.athleteCoachViewLinkError, 'No pudimos cargar tu vínculo.');
    });

    // check_in_strings migration (4 keys)
    testWidgets('checkInHeader verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.checkInHeader, '¿ESTÁS EN EL GYM HOY?');
    });

    testWidgets('checkInNeutralSubtext verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.checkInNeutralSubtext, 'Confirma tu entrenamiento de hoy');
    });

    testWidgets('checkInNoButton verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.checkInNoButton, 'NO');
    });

    testWidgets('checkInSiButton verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.checkInSiButton, 'SÍ, ENTRÉ');
    });
  });
}
