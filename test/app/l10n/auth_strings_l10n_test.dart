// T-I18N-006 RED — SCENARIO-759, SCENARIO-760
// AuthStrings ARB key existence and value verbatim tests.
//
// These tests verify that AppL10n exposes all AuthStrings keys
// with verbatim es-AR values. The keys do NOT exist yet in the ARB — RED.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Pumps a minimal widget tree with AppL10n delegates so
/// AppL10n.of(context) resolves to es-AR strings.
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
  group('AppL10n — AuthStrings keys (SCENARIO-759, SCENARIO-760)', () {
    // --- Splash ---
    testWidgets('authSplashTagline verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.authSplashTagline, 'ENTRENÁ. COMPARTÍ. CRECÉ.');
    });

    // --- Welcome ---
    testWidgets('authWelcomeEyebrow verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.authWelcomeEyebrow, 'ENTRENAMIENTO · GYM · COACH');
    });

    testWidgets('authWelcomeBody verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(
        l10n.authWelcomeBody,
        'Cargá tu rutina, ejecutá los sets, seguí a tus pibes y encontrá un coach cerca tuyo.',
      );
    });

    testWidgets('authWelcomeCta verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.authWelcomeCta, 'EMPEZAR');
    });

    testWidgets('authWelcomeHaveAccount verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.authWelcomeHaveAccount, 'Ya tengo cuenta');
    });

    testWidgets('authWelcomeSignIn verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.authWelcomeSignIn, 'Iniciar sesión');
    });

    // --- Login ---
    testWidgets('authLoginTitle verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.authLoginTitle, 'BIENVENIDO');
    });

    testWidgets('authLoginSubtitle verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.authLoginSubtitle, 'Entrá para seguir tu rutina');
    });

    testWidgets('authLoginEmailHint verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.authLoginEmailHint, 'tu@email.com');
    });

    testWidgets('authLoginForgot verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.authLoginForgot, 'Olvidé la contraseña');
    });

    testWidgets('authLoginCta verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.authLoginCta, 'ENTRAR');
    });

    testWidgets('authLoginContinueWith verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.authLoginContinueWith, 'O CONTINUÁ CON');
    });

    testWidgets('authLoginNoAccount verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.authLoginNoAccount, '¿No tenés cuenta?');
    });

    testWidgets('authLoginRegisterLink verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.authLoginRegisterLink, 'Registrate');
    });

    testWidgets('authLoginTrainerCardTitle verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.authLoginTrainerCardTitle, '¿Sos entrenador?');
    });

    testWidgets('authLoginTrainerCardSubtitle verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.authLoginTrainerCardSubtitle, 'Pedí tu alta al equipo TREINO');
    });

    // --- Register ---
    testWidgets('authRegisterAppbar verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.authRegisterAppbar, 'CREAR CUENTA');
    });

    testWidgets('authRegisterTitle verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.authRegisterTitle, 'SUMATE A');
    });

    testWidgets('authRegisterSubtitle verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(
        l10n.authRegisterSubtitle,
        'Es gratis. En 30 segundos estás adentro.',
      );
    });

    testWidgets('authRegisterEmailLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.authRegisterEmailLabel, 'EMAIL');
    });

    testWidgets('authRegisterPasswordLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.authRegisterPasswordLabel, 'CONTRASEÑA');
    });

    testWidgets('authRegisterConfirmPasswordLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.authRegisterConfirmPasswordLabel, 'CONFIRMAR CONTRASEÑA');
    });

    testWidgets('authRegisterCta verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.authRegisterCta, 'CREAR CUENTA');
    });

    testWidgets('authRegisterDividerOr verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.authRegisterDividerOr, 'O');
    });

    // --- Forgot password ---
    testWidgets('authForgotTitle verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.authForgotTitle, 'RECUPERAR\nACCESO');
    });

    testWidgets('authForgotBody verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(
        l10n.authForgotBody,
        'Ingresá tu email y te enviamos un link para resetear la contraseña.',
      );
    });

    testWidgets('authForgotEmailLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.authForgotEmailLabel, 'EMAIL');
    });

    testWidgets('authForgotEmailHint verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.authForgotEmailHint, 'tu@email.com');
    });

    testWidgets('authForgotCta verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.authForgotCta, 'ENVIAR LINK');
    });

    testWidgets('authForgotSuccess verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(
        l10n.authForgotSuccess,
        'Si tu email está registrado, te enviamos un link para resetear la contraseña.',
      );
    });

    testWidgets('authForgotBackToLogin verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.authForgotBackToLogin, 'Volver al login');
    });

    // --- Trainer inquiry dialog ---
    testWidgets('authTrainerInquiryDialogTitle verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.authTrainerInquiryDialogTitle, 'Acceso de entrenador');
    });

    testWidgets('authTrainerInquiryDialogBody verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(
        l10n.authTrainerInquiryDialogBody,
        'Para alta de entrenador, escribinos a equipo@treino.app',
      );
    });

    testWidgets('authTrainerInquiryDialogClose verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.authTrainerInquiryDialogClose, 'Cerrar');
    });

    // --- Terms ---
    testWidgets('authTermsPlaceholder verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.authTermsPlaceholder, 'Próximamente');
    });

    // --- Social ---
    testWidgets('authGoogleLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.authGoogleLabel, 'GOOGLE');
    });

    testWidgets('authAppleLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.authAppleLabel, 'APPLE');
    });

    testWidgets('authComingSoonTooltip verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.authComingSoonTooltip, 'Próximamente');
    });

    // --- Validation ---
    testWidgets('authValidationEmailInvalid verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.authValidationEmailInvalid, 'El email no es válido');
    });

    testWidgets('authValidationPasswordRules verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(
        l10n.authValidationPasswordRules,
        'La contraseña debe tener al menos 8 caracteres, una letra y un número',
      );
    });

    testWidgets('authValidationPasswordMismatch verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.authValidationPasswordMismatch, 'Las contraseñas no coinciden');
    });

    // --- Profile ---
    testWidgets('authProfileSignOut verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.authProfileSignOut, 'Cerrar sesión');
    });
  });
}
