// ─────────────────────────────────────────────────────────────────────────────
// E2E (b) — Register → Profile-setup → Home
// ─────────────────────────────────────────────────────────────────────────────
// Critical flow: a brand-new athlete signs up on /register (email + password +
// Terms), gets routed to /profile-setup (because the freshly created
// users/{uid} doc has displayName == null), completes the 5 onboarding steps,
// and the submit persists displayName → the email gate sends them to
// /verificar-mail → they type the 6-digit code from the mail → /home. See
// lib/app/router.dart `authRedirect`.
//
// Runs against the Firebase EMULATORS only (Auth 9099, Firestore 8080 on
// 127.0.0.1). Never cloud. See integration_test/README.md to enable + run.
//
// SEED CONTRACT:
//   • No pre-seeded user needed — this flow CREATES one, with a per-run unique
//     email and username so re-runs don't collide.
//   • Emulador COMPLETO, con Functions: el código lo pide la callable
//     `solicitarCodigoDeVerificacion` y lo confirma `verificarCodigoDeMail`.
//
// EL GATE DEL MAIL. Lo prende `app_config/email_gate` con `{enabled: true}` y
// el seed no lo siembra, así que contra el emulador el gate no existe: el
// recorrido llegaba a Inicio sin pedir código (así lo vio el recorrido manual
// de la E2E de 1.3.0). En producción sí está prendido, y este es el camino que
// recorre cualquier cuenta nueva. La suite lo prende para su corrida y lo deja
// como estaba al terminar (`addTearDown`), aunque falle.
//
// EL CÓDIGO. El backend guarda sólo el hash en `verificaciones_de_mail`; en
// claro existe únicamente en los `params` del mail que encola en `mail_queue`.
// La suite lo lee de ahí con `support/emulator_admin.dart`, que saltea las
// reglas con el token `owner` del emulador — ningún cliente puede leer esa
// colección, y está bien que así sea.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:treino/features/auth/presentation/verify_mail_screen.dart';
import 'package:treino/features/home/home_screen.dart';
import 'package:treino/features/profile_setup/presentation/profile_setup_flow.dart';

import 'support/e2e_helpers.dart';
import 'support/emulator_admin.dart';

/// Per-run suffix so re-runs don't collide in the Auth emulator nor in the
/// username index.
final String _runId = '${DateTime.now().millisecondsSinceEpoch % 10000000000}';
final String kNewEmail = 'e2e.new+$_runId@treino.test';
const String kNewPassword = 'Treino1234';
// 3–20 de `[A-Za-z0-9_.]`: `e2e_` + 10 dígitos = 14.
final String kNewUsername = 'e2e_$_runId';

const String _emailGatePath = 'app_config/email_gate';

/// Toca el botón primario del footer del profile-setup ([label]) y espera la
/// animación del PageView.
Future<void> _next(WidgetTester tester, String label) async {
  final button = find.widgetWithText(ElevatedButton, label);
  expect(
    tester.widget<ElevatedButton>(button).onPressed,
    isNotNull,
    reason: '"$label" tiene que estar habilitado: el paso quedó incompleto',
  );
  await tester.tap(button);
  await tester.pumpAndSettle();
}

/// El código del mail encolado para [uid], tal como lo recibiría el usuario.
Future<String> _codigoDelMail(String uid) async {
  final end = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(end)) {
    final mails = await adminWhereEqual('mail_queue', 'toUid', uid);
    for (final m in mails) {
      final params = m.data['params'] as Map<String, Object?>?;
      final codigo = params?['codigo'];
      if (m.data['kind'] == 'email-code-athlete' && codigo is String) {
        return codigo;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw TestFailure(
    'no apareció el mail con el código en mail_queue para $uid: ¿el emulador '
    'tiene Functions? (`./scripts/emulator.sh` sin SKIP_FUNCTIONS)',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initFirebaseForEmulators);

  testWidgets(
      'register → profile-setup → mail code → home: new athlete completes '
      'onboarding', (tester) async {
    // Prender el gate y devolverlo como estaba, pase lo que pase.
    // El teardown se registra ANTES de escribir: si el PATCH llega al emulador
    // y la respuesta se pierde, el gate tiene que volver igual.
    final gateAntes = await adminGetDoc(_emailGatePath);
    addTearDown(() async {
      if (gateAntes == null) {
        await adminDeleteDoc(_emailGatePath);
      } else {
        await adminSetDoc(_emailGatePath, gateAntes);
      }
    });
    await adminSetDoc(_emailGatePath, {'enabled': true});

    await ensureSignedOut(tester);
    await pumpTreinoApp(tester);
    final l10n = l10nOf(tester);

    // /welcome → tap primary CTA "EMPEZAR" (authWelcomeCta) → /register.
    await tester.tap(find.text(l10n.authWelcomeCta));
    await tester.pumpAndSettle();

    // Fill the register form: email + password. Antes esperaba tres campos
    // (había un "confirmar contraseña") y la suite se caía en esta línea.
    final fields = find.byType(TextFormField);
    expect(
      fields,
      findsNWidgets(2),
      reason: 'RegisterScreen has email + password fields',
    );
    await tester.enterText(fields.at(0), kNewEmail);
    await tester.enterText(fields.at(1), kNewPassword);
    await tester.pump();

    // Accept Terms — the checkbox gates the submit button (`_canSubmit`). El
    // label de al lado no es tocable (sus dos links abren los textos legales),
    // así que el blanco es el Checkbox.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();

    await tester.tap(find.widgetWithText(ElevatedButton, l10n.authRegisterCta));
    await pumpUntilFound(
      tester,
      find.byType(ProfileSetupFlow),
      reason: 'signup with displayName == null routes to /profile-setup',
    );
    await tester.pumpAndSettle();

    // ── Step 1: username + avatar ────────────────────────────────────────────
    // El único TextFormField del paso. SIGUIENTE espera el chequeo de
    // disponibilidad, que tiene un debounce de 450 ms.
    await tester.enterText(find.byType(TextFormField).first, kNewUsername);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await _next(tester, 'SIGUIENTE');

    // ── Step 2: fecha de nacimiento (gate de edad mínima) ────────────────────
    // Es un `showDatePicker` de Material. Arranca el 1/1 de hace 25 años, muy
    // por encima de la edad mínima (13): aceptar sin tocar nada es la fecha
    // válida más estable que hay.
    await tester.tap(find.byKey(const Key('profile_setup_born_at_field')));
    await tester.pumpAndSettle();
    final picker = find.byType(DatePickerDialog);
    expect(picker, findsOneWidget, reason: 'el campo abre el date picker');
    await tester.tap(
      find.text(MaterialLocalizations.of(tester.element(picker)).okButtonLabel),
    );
    await tester.pumpAndSettle();
    await _next(tester, 'SIGUIENTE');

    // ── Step 3: gym ──────────────────────────────────────────────────────────
    // "OTRO GYM / SIN GYM" (escrito a mano en `gym_search_box.dart`) valida el
    // paso sin depender de Places.
    await tester.tap(find.text('OTRO GYM / SIN GYM'));
    await tester.pumpAndSettle();
    await _next(tester, 'SIGUIENTE');

    // ── Step 4: experience + gender ──────────────────────────────────────────
    await tester.tap(find.text('PRINCIPIANTE'));
    await tester.tap(find.text('OTRO'));
    await tester.pumpAndSettle();
    await _next(tester, 'SIGUIENTE');

    // ── Step 5: weight + height → submit ("EMPEZAR") ─────────────────────────
    final metrics = find.byType(TextFormField);
    await tester.enterText(metrics.at(0), '75');
    await tester.enterText(metrics.at(1), '175');
    await tester.pumpAndSettle();
    // Si el perfil todavía no tiene `termsAcceptedAt`, este paso vuelve a
    // pedir los términos y EMPEZAR no envía sin ellos.
    final terms = find.byType(Checkbox);
    if (terms.evaluate().isNotEmpty &&
        tester.widget<Checkbox>(terms.first).value != true) {
      await tester.tap(terms.first);
      await tester.pumpAndSettle();
    }
    await _next(tester, 'EMPEZAR');

    // ── Gate del mail ────────────────────────────────────────────────────────
    // Submit persisted displayName + bornAt in ONE write → el gate del mail
    // (prendido arriba) manda a /verificar-mail. Ojo al tocar esto: si
    // displayName y bornAt alguna vez se separan, el gate de edad del router
    // manda a /birth-date en lugar de seguir.
    await pumpUntilFound(
      tester,
      find.byType(VerifyMailScreen),
      reason: 'una cuenta nueva confirma el mail antes de usar la app',
    );

    // La pantalla pide el código sola al montarse.
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final codigo = await _codigoDelMail(uid);
    await tester.enterText(
      find.byKey(const Key('verify_mail_code_field')),
      codigo,
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('verify_mail_confirm')));

    // La pantalla no navega: el router la saca cuando el perfil trae
    // `emailVerification`, que escribe la callable.
    await pumpUntilFound(
      tester,
      find.byType(HomeScreen),
      reason: 'con el código confirmado el router saca al usuario a /home',
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await dismissOnboardingTourIfPresent(tester);

    expect(
      find.byType(HomeScreen),
      findsOneWidget,
      reason: 'el registro termina en Inicio',
    );
  });
}
