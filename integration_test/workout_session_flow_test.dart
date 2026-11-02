// ─────────────────────────────────────────────────────────────────────────────
// E2E (c) — Start workout → Session player → Summary
// ─────────────────────────────────────────────────────────────────────────────
// Critical flow: a signed-in athlete with an assigned routine starts a fresh
// training session, confirms a set in the SessionPlayer, taps "TERMINAR
// SESIÓN", accepts "TERMINAR IGUAL", and lands on the PostWorkoutSummary
// screen.
//
// Se confirma UNA serie y no todas a propósito: alcanza para habilitar el
// botón de terminar (`doneSetsTotal > 0`) y además recorre el diálogo de
// terminar antes de tiempo, que es la rama que un usuario real toca casi
// siempre. Completar las 10 series del día sólo alargaría la suite.
//
// NADA de `pumpAndSettle` adentro del player: tiene un timer que corre siempre
// (cronómetro y descanso) y el árbol no se asienta nunca. Con el `goTo` de
// antes esta suite colgaba 10 min 25 s hasta el timeout. Van `pumpFor` y
// `pumpUntilFound`, acotados.
//
// Route map (lib/app/router.dart):
//   /workout/session/:routineId/:dayNumber   → SessionPlayerScreen(FreshSession)
//   /workout/session-summary/:sessionId       → PostWorkoutSummaryScreen
//
// Runs against the Firebase EMULATORS only (Auth 9099, Firestore 8080 on
// 127.0.0.1). Never cloud. See integration_test/README.md to enable + run.
//
// SEED CONTRACT — ya lo cumple `scripts/seed_emulator_full.js`:
//   • Auth emulator: Martín (`kMartin` / `kSeedPassword`), verificado.
//   • Firestore emulator: `kAssignedRoutineId`, asignada a Martín, con el día
//     `kDayNumber`. Sus slots usan los campos legacy (`targetSets`,
//     `targetRepsMax`, `targetWeightKg`), y el player precarga reps y kg desde
//     ahí: tocar el check alcanza para confirmar la serie.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/workout/presentation/post_workout_summary_screen.dart';
import 'package:treino/features/workout/presentation/session_player_screen.dart';

import 'support/e2e_helpers.dart';
import 'support/emulator_admin.dart';
import 'support/seed_ids.dart';

// Credenciales e ids: `support/seed_ids.dart`, generado desde el seed.
const String kRoutineId = kAssignedRoutineId;

/// `dayNumber` is 1-based on the wire (see router).
const int kDayNumber = 1;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initFirebaseForEmulators);

  testWidgets('workout: start session → confirm a set → finish → summary',
      (tester) async {
    await ensureSignedOut(tester);
    // Sin sesión activa, Inicio no abre "Entrenamiento en curso" encima.
    await closeActiveSessionsOf(kMartin.uid);
    await pumpTreinoApp(tester);

    await signInViaUi(tester, email: kMartin.email, password: kSeedPassword);

    // Deep-link straight into a fresh session for the seeded routine/day.
    // (Tapping through Home's "empezar entrenamiento" card is the fuller path;
    //  deep-linking keeps the suite robust to Home layout changes.)
    //
    // Desde la pestaña Entrenar y con `push`, que es como entra la app
    // (`routine_detail_screen.dart`). El player es una ruta top-level y las
    // pestañas viven en un `ShellRoute` con su propio navigator: empujado
    // desde Inicio, Inicio sigue siendo la ruta ACTUAL de ese navigator, su
    // listener de sesión activa ve la sesión que el player acaba de crear y
    // abre "Entrenamiento en curso" encima del player — el tap al check caía
    // en el diálogo. Desde Entrenar, Inicio no está montado.
    await goTo(tester, '/workout');
    await pushTo(
      tester,
      '/workout/session/$kRoutineId/$kDayNumber',
      settle: false,
    );
    await pumpUntilFound(
      tester,
      find.byType(SessionPlayerScreen),
      reason: 'fresh-session route should mount the player',
    );

    // ── Confirmar la primera serie ───────────────────────────────────────────
    // El check de la serie actual es el PRIMER círculo vacío: las series
    // futuras también lo dibujan (al 40 %), pero tocarlas no hace nada.
    final setCheck = find.byIcon(TreinoIcon.checkCircleEmpty);
    await pumpUntilFound(
      tester,
      setCheck,
      reason: 'el player tiene que mostrar la serie actual con su check',
    );
    await tester.tap(setCheck.first);
    await pumpFor(tester, const Duration(seconds: 1));

    // ── Terminar ─────────────────────────────────────────────────────────────
    // "TERMINAR SESIÓN" está escrito a mano en `_TerminarSessionButton`, no
    // sale del `.arb`. Se habilita con la primera serie confirmada.
    final finish = find.widgetWithText(ElevatedButton, 'TERMINAR SESIÓN');
    expect(finish, findsOneWidget, reason: 'el footer tiene el botón');
    expect(
      tester.widget<ElevatedButton>(finish).onPressed,
      isNotNull,
      reason: 'con una serie confirmada, terminar tiene que estar habilitado',
    );
    await tester.tap(finish);
    await pumpFor(tester, const Duration(seconds: 1));

    // Quedan series sin hacer → `_FinishEarlyDialog` ("¿TERMINAR IGUAL?").
    final l10n = l10nOf(tester);
    final confirmEarly = find.widgetWithText(
      ElevatedButton,
      l10n.sessionFinishEarlyConfirm,
    );
    await pumpUntilFound(
      tester,
      confirmEarly,
      reason: 'con series pendientes, terminar pide confirmación',
    );
    await tester.tap(confirmEarly);

    // ── Summary ──────────────────────────────────────────────────────────────
    // finishSession() writes the finished session and navigates to
    // /workout/session-summary/:sessionId. The summary has a confetti overlay,
    // so this is bounded too.
    await pumpUntilFound(
      tester,
      find.byType(PostWorkoutSummaryScreen),
      reason: 'finishing a session should open the post-workout summary',
    );
    expect(find.byType(PostWorkoutSummaryScreen), findsOneWidget);
  });
}
