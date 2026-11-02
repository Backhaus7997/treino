// ─────────────────────────────────────────────────────────────────────────────
// E2E shared helpers — TREINO integration_test suites (QA Fase 6)
// ─────────────────────────────────────────────────────────────────────────────
//
// This file is INFRASTRUCTURE, not a test suite: it has no `main()` and is not
// discovered/executed by `flutter test integration_test/`. Each *_test.dart in
// this folder imports it to share the Firebase-emulator bootstrap and a couple
// of driving helpers.
//
// EMULATORS ONLY — NEVER cloud. Firestore 8080, Auth 9099, Functions 5001 y
// Storage 9199, vía `conectarEmuladores()` — la MISMA función que llama
// `main.dart` con `USE_EMULATOR=true`. Levantalos con `./scripts/emulator.sh`
// (completo, con Functions: el registro pide el código de verificación a una
// callable).
// El script fija `--project treino-dev`; el default de .firebaserc es
// `demo-treino` y dejaría los datos en otro namespace (#840).
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:treino/app/app.dart';
import 'package:treino/core/firebase/emuladores.dart';
import 'package:treino/core/persistence/shared_prefs_provider.dart';
import 'package:treino/firebase_options.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Guards `conectarEmuladores` so re-running suites in one process does not
/// throw "already configured".
bool _emulatorsWired = false;

/// Initializes Firebase and pins Firestore, Auth, Functions and Storage to the
/// local emulators. Call once from each suite's `setUpAll`. Idempotent across
/// suites in the same test process.
///
/// Llama a `conectarEmuladores()` y no a `useAuthEmulator` /
/// `useFirestoreEmulator` sueltos. Acá había exactamente esos dos, y el
/// encabezado decía "EMULATORS ONLY — NEVER cloud": las callables (el código de
/// verificación del mail, entre otras) y las subidas a Storage salían al
/// proyecto real, porque `pumpTreinoApp` monta `TreinoApp` sin pasar por
/// `main.dart`, que es quien conecta los cuatro. Con la función compartida, si
/// mañana se emula un servicio más, las suites lo heredan solas.
Future<void> initFirebaseForEmulators() async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  if (_emulatorsWired) return;

  await conectarEmuladores();
  // Deterministic reads in E2E: no offline cache masking emulator state.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
  );
  _emulatorsWired = true;
}

/// Pumps the REAL [TreinoApp] (same widget `main.dart` runs) inside a
/// [ProviderScope], eager-overriding [sharedPreferencesProvider] con la MISMA
/// función que usa `main.dart` — `sharedPreferencesOverride()` (ADR-LM-009)—
/// así `.requireValue` es seguro en el init de los providers.
///
/// Esta línea decía "exactly like production does" mientras el override de
/// abajo tenía un `async` que producción no tiene. Ahora llama a la función
/// compartida, que es la única forma de que la afirmación no se vuelva falsa
/// sola: si producción cambia el override, esto cambia con ella.
///
/// [overrides] lets a suite stub providers that would otherwise reach out to
/// device-only services.
///
/// TODO(e2e-infra): [TreinoApp.initState] eagerly reads the FCM / notification
/// providers (`fcmLifecycleProvider`, `fcmServiceProvider`). On a bare AVD
/// without Google Play services — or against the emulator project — token
/// registration can throw and block first frame. If boot hangs, pass overrides
/// here that stub `fcmServiceProvider` / `notificationProviders` with fakes.
Future<void> pumpTreinoApp(
  WidgetTester tester, {
  List<Override> overrides = const [],
}) async {
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // `sharedPreferencesOverride()` y NO un override inline. Acá había
        // `overrideWith((_) async => prefs)`, con el `async` que el dartdoc de
        // `shared_prefs_provider.dart:20` prohíbe con todas las letras: un
        // callback `async` devuelve un Future —aunque ya esté completo, cuesta
        // un microtask— y deja el provider en `AsyncLoading` el primer frame,
        // así que `app.dart:208` tiraba
        // `Bad state: Tried to call requireValue on an AsyncValue that has no
        // value` antes de pintar nada. Es el #543 otra vez.
        //
        // El comentario de abajo decía que esto replicaba producción "exactly".
        // No lo hacía — y esa es la parte cara: ninguna de las cinco suites
        // llegaba a montar la app, y el mensaje hablaba de Riverpod, no del
        // override. Nadie lo vio porque nunca se había corrido ninguna.
        sharedPreferencesOverride(prefs),
        ...overrides,
      ],
      child: const TreinoApp(),
    ),
  );
  // Splash → redirect resolves (anonymous → /welcome, or → /home when a
  // session is already restored). Give async auth/profile streams a beat.
  await tester.pumpAndSettle(const Duration(seconds: 3));
}

/// Signs the Firebase user out so a suite starts from the anonymous
/// `/welcome` gate regardless of a session left over by a previous suite.
Future<void> ensureSignedOut(WidgetTester tester) async {
  await FirebaseAuth.instance.signOut();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Los textos de la app en el idioma con el que arrancó, para buscar por
/// `find.text` sin copiar el literal.
///
/// Las suites buscaban `'Iniciar sesión'` y la bienvenida dice
/// `'INICIAR SESIÓN'`: un cambio de copy en el `.arb` dejó a TODAS las suites que
/// loguean paradas en el primer frame, con un error que hablaba de campos que
/// no aparecían. Leyendo la clave en vez del literal, el copy puede cambiar.
AppL10n l10nOf(WidgetTester tester) =>
    AppL10n.of(tester.element(find.byType(Navigator).first));

/// Pumps frames for [total] in [step] increments, WITHOUT waiting for the tree
/// to settle.
///
/// Para pantallas que nunca se asientan: el player de la sesión tiene un timer
/// que corre siempre (cronómetro y descanso), así que un `pumpAndSettle` ahí
/// adentro cuelga hasta el timeout del test — medido: 10 min 25 s.
Future<void> pumpFor(
  WidgetTester tester,
  Duration total, {
  Duration step = const Duration(milliseconds: 100),
}) async {
  final end = DateTime.now().add(total);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(step);
  }
}

/// Pumps until [finder] matches something, or fails after [timeout] naming
/// [reason]. Bounded alternative to `pumpAndSettle` for async results (a
/// Firestore round-trip, a callable) on screens that never settle.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
  String? reason,
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure(
    'pumpUntilFound: $finder no apareció en ${timeout.inSeconds} s'
    '${reason == null ? '' : ' — $reason'}',
  );
}

/// Cierra el tour de onboarding si está abierto (botón SALTAR).
///
/// El tour lo abre `OnboardingGate` encima de Inicio la primera vez que un
/// usuario con el perfil completo llega a la app, y es una ruta opaca: con él
/// arriba `find.byType(HomeScreen)` da 0 onstage / 1 offstage. Se descarta en
/// la suite —y no apagándolo desde el seed— porque el tour ES parte del
/// producto que un usuario nuevo ve, y el recorrido manual de la E2E lo prueba
/// sobre las cuentas sembradas. SALTAR lo marca visto (`onboardingSeen`), así
/// que en las corridas siguientes contra el mismo emulador ya no aparece y
/// esto no hace nada.
Future<void> dismissOnboardingTourIfPresent(WidgetTester tester) async {
  final skip = find.text(l10nOf(tester).onboardingTourSkip);
  if (skip.evaluate().isEmpty) return;
  await tester.tap(skip.first);
  await tester.pumpAndSettle();
}

/// Descarta el modal "Entrenamiento en curso" si Inicio lo abrió.
///
/// Inicio lo muestra cuando el usuario tiene una sesión `active` (lo deja una
/// corrida de `workout_session_flow_test` que se cortó a la mitad, o el
/// recorrido manual). No se puede cerrar tocando afuera, así que sin esto la
/// suite siguiente queda trabada debajo. El texto está escrito a mano en
/// `resume_session_modal.dart`, no sale del `.arb`.
Future<void> dismissResumeSessionPromptIfPresent(WidgetTester tester) async {
  if (find.text('Entrenamiento en curso').evaluate().isEmpty) return;
  await tester.tap(find.widgetWithText(OutlinedButton, 'Descartar'));
  await tester.pumpAndSettle();
}

/// Drives the UI login flow: `/welcome` → tap "INICIAR SESIÓN"
/// (`authWelcomeSignIn`) → fill the two [TextFormField]s → tap "ENTRAR"
/// (`authLoginCta`) → settle on `/home` → close the onboarding tour if it
/// opened.
///
/// Precondition: a verified user with [email]/[password] must exist in the
/// Auth emulator — the seeded accounts of `support/seed_ids.dart`.
Future<void> signInViaUi(
  WidgetTester tester, {
  required String email,
  required String password,
}) async {
  final l10n = l10nOf(tester);
  final signInLink = find.text(l10n.authWelcomeSignIn);
  if (signInLink.evaluate().isNotEmpty) {
    await tester.tap(signInLink.first);
    await tester.pumpAndSettle();
  }

  final fields = find.byType(TextFormField);
  expect(
    fields,
    findsWidgets,
    reason: 'LoginScreen should render email + password fields',
  );
  await tester.enterText(fields.at(0), email);
  await tester.enterText(fields.at(1), password);
  await tester.pump();

  await tester.tap(find.text(l10n.authLoginCta));
  await tester.pumpAndSettle(const Duration(seconds: 4));

  // El tour va por el navigator raíz y el modal de sesión en curso sólo se
  // abre con Inicio arriba, así que el modal puede aparecer recién cuando se
  // cierra el tour. El orden importa; las dos llamadas no hacen nada si no hay
  // nada que cerrar.
  await dismissOnboardingTourIfPresent(tester);
  await dismissResumeSessionPromptIfPresent(tester);
}

/// Como [goTo], pero con `push`: la pantalla queda ENCIMA de la actual.
///
/// Para pantallas que al terminar hacen `context.pop()` —el editor de rutina
/// después de GUARDAR CAMBIOS—: con `go` quedan como única ruta del stack y el
/// `pop` no tiene adónde volver.
Future<void> pushTo(
  WidgetTester tester,
  String location, {
  Object? extra,
}) async {
  final ctx = tester.element(find.byType(Navigator).first);
  unawaited(GoRouter.of(ctx).push<void>(location, extra: extra));
  await tester.pumpAndSettle(const Duration(seconds: 3));
}

/// Navigates the live GoRouter to [location] (optionally passing [extra]).
/// Used by suites that need to deep-link past a seeded document (a routine,
/// a chat) rather than tapping through every intermediate screen.
///
/// [settle] en `false` para destinos que nunca se asientan (el player de la
/// sesión): ahí pumpea [settleFor] y vuelve, en vez de colgarse en un
/// `pumpAndSettle`.
Future<void> goTo(
  WidgetTester tester,
  String location, {
  Object? extra,
  bool settle = true,
  Duration settleFor = const Duration(seconds: 3),
}) async {
  final ctx = tester.element(find.byType(Navigator).first);
  GoRouter.of(ctx).go(location, extra: extra);
  if (settle) {
    await tester.pumpAndSettle(settleFor);
  } else {
    await pumpFor(tester, settleFor);
  }
}
