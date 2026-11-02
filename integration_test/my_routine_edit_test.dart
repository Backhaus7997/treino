// ─────────────────────────────────────────────────────────────────────────────
// E2E (e) — Edit my own routine
// ─────────────────────────────────────────────────────────────────────────────
// Critical flow: a signed-in athlete opens the self-routine editor for one of
// their existing personal routines (SelfCreating mode), changes something (a
// day name), saves ("GUARDAR CAMBIOS"), and the change persists in Firestore.
//
// Route (lib/app/router.dart):
//   /workout/my-routine-editor  (extra: existingRoutineId)
//   Se abre con `push`, no con `go`: al guardar, el editor hace `context.pop()`
//   y con `go` no hay ruta debajo adonde volver.
//       → RoutineEditorScreen(mode: SelfCreating(existingRoutineId: extra))
//   `extra == null` means CREATE; a non-null id means EDIT.
//
// Runs against the Firebase EMULATORS only (Auth 9099, Firestore 8080 on
// 127.0.0.1). Never cloud. See integration_test/README.md to enable + run.
//
// SEED CONTRACT — ya lo cumple `scripts/seed_emulator_full.js`:
//   • Auth emulator: Martín (`kMartin` / `kSeedPassword`), verificado.
//   • Firestore emulator: `routines/{kOwnRoutineId}`, `user-created` con
//     `createdBy` = Martín, un día y un ejercicio con sets explícitos. Sale de
//     `ROUTINES.propiaDeMartin` del contrato; antes el seed no sembraba ninguna
//     rutina propia y esta suite no se podía correr.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:treino/features/workout/presentation/routine_editor_screen.dart';

import 'support/e2e_helpers.dart';
import 'support/emulator_admin.dart';
import 'support/seed_ids.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initFirebaseForEmulators);

  testWidgets('my routine: open editor in edit mode → change → save',
      (tester) async {
    await ensureSignedOut(tester);
    await pumpTreinoApp(tester);

    await signInViaUi(tester, email: kMartin.email, password: kSeedPassword);

    // Deep-link into the editor in EDIT mode by passing the existing id as
    // `extra` (the route maps a non-null String extra → SelfCreating(existingRoutineId)).
    await pushTo(tester, '/workout/my-routine-editor', extra: kOwnRoutineId);

    expect(
      find.byType(RoutineEditorScreen),
      findsOneWidget,
      reason: 'self-routine editor should mount in SelfCreating edit mode',
    );

    // ── Edit ─────────────────────────────────────────────────────────────────
    // El nombre del día es un TextField inline del día seleccionado
    // (`day_name_field`, único porque sólo se dibuja ese día). Arranca con el
    // nombre sembrado: si no, el editor abrió otra rutina.
    final dayName = find.byKey(const Key('day_name_field'));
    expect(dayName, findsOneWidget,
        reason: 'el día seleccionado se edita inline');
    expect(
      tester.widget<TextField>(dayName).controller?.text,
      kOwnRoutineFirstDayName,
      reason: 'el editor tiene que abrir la rutina sembrada',
    );

    // Nonce por corrida: la segunda corrida contra el mismo emulador sin
    // re-sembrar tiene que demostrar SU guardado, no encontrar el de la anterior.
    final edited =
        'Empuje E2E ${DateTime.now().millisecondsSinceEpoch % 100000}';
    await tester.enterText(dayName, edited);
    await tester.pump();

    // ── Save ─────────────────────────────────────────────────────────────────
    // `footer_submit_button`, "GUARDAR CAMBIOS" en modo edición.
    final save = find.byKey(const Key('footer_submit_button'));
    expect(
      find.descendant(
        of: save,
        matching: find.text(l10nOf(tester).workoutSelfEditorUpdateLabel),
      ),
      findsOneWidget,
      reason: 'en modo edición el botón dice GUARDAR CAMBIOS, no CREAR',
    );
    // El teclado del TextField abre un guard de 500 ms en el footer.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    await tester.tap(save);

    // Al guardar, el editor hace `pop` y vuelve a la pantalla de abajo.
    await tester.pumpAndSettle(const Duration(seconds: 4));
    expect(
      find.byType(RoutineEditorScreen),
      findsNothing,
      reason: 'un guardado exitoso cierra el editor',
    );

    // ── Verify persistence ───────────────────────────────────────────────────
    // Contra el documento, no contra la pantalla: el editor podría mostrar el
    // nombre nuevo desde su estado local sin haber escrito nada.
    final doc = await adminGetDoc('routines/$kOwnRoutineId');
    expect(doc, isNotNull, reason: 'la rutina sembrada tiene que existir');
    final days = doc!['days']! as List<Object?>;
    expect(
      (days.first! as Map<String, Object?>)['name'],
      edited,
      reason: 'el nombre del día editado tiene que llegar a Firestore',
    );
    expect(
      doc['createdBy'],
      kMartin.uid,
      reason: 'guardar no toca la identidad de la rutina',
    );
  });
}
