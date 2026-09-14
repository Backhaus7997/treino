// ─────────────────────────────────────────────────────────────────────────────
// E2E (d) — Coach ↔ Athlete 1-1 chat
// ─────────────────────────────────────────────────────────────────────────────
// Critical flow: a signed-in athlete opens the 1-1 chat with their linked
// coach, types a message, sends it, and sees the outgoing bubble appear
// (real-time write to the Firestore emulator).
//
// Route (lib/app/router.dart):
//   /coach/chat/:chatId?other=:otherUid  → ChatScreen(chatId, otherUid)
//
// Runs against the Firebase EMULATORS only (Auth 9099, Firestore 8080 on
// 127.0.0.1). Never cloud. See integration_test/README.md to enable + run.
//
// SEED CONTRACT — ya lo cumple `scripts/seed_emulator_full.js`:
//   • Auth emulator: Martín (`kMartin`) y Lautaro (`kLautaro`), verificados.
//   • Firestore: `chats/{kCoachChatId}` con `members` ordenado y un `linkId`
//     que apunta a un `trainer_links` en `active` — es la rama de Coach de
//     `chatCreateOk` (firestore.rules:2210), la que habilita a los dos lados a
//     escribir sin depender de ningún follow.
//
// Los ids NO se declaran acá: salen de `support/seed_ids.dart`, generado desde
// `scripts/lib/e2e_seed_contract.js`. Antes esta suite decía
// `kSeedEmail = 'e2e.athlete@treino.test'`, un mail que no correspondía a
// ningún usuario sembrado y que hacía fallar el login hablando de credenciales.
//
// Correr el seed antes:
//   bash scripts/emulator.sh          (o SKIP_FUNCTIONS=1 para Firestore+Auth)
//   npm --prefix scripts run seed:emulator
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/chat/presentation/chat_screen.dart';

import 'support/e2e_helpers.dart';
import 'support/seed_ids.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initFirebaseForEmulators);

  testWidgets('chat: athlete opens 1-1 with coach and sends a message',
      (tester) async {
    await ensureSignedOut(tester);
    await pumpTreinoApp(tester);

    await signInViaUi(tester, email: kMartin.email, password: kSeedPassword);

    // Deep-link into the seeded 1-1 chat.
    await goTo(tester, '/coach/chat/$kCoachChatId?other=${kLautaro.uid}');

    expect(
      find.byType(ChatScreen),
      findsOneWidget,
      reason: 'chat route should mount the ChatScreen',
    );

    // El texto lleva un nonce por corrida, y no es cosmético: el chat ahora es
    // un documento PERSISTENTE del seed, no un placeholder. Con un texto fijo,
    // la segunda corrida contra el mismo emulador sin re-sembrar deja dos
    // globos idénticos y el `findsOneWidget` de abajo falla aunque el envío
    // haya andado perfecto — el rojo diría "no se mandó" sobre un mensaje que
    // sí se mandó, dos veces. Con el nonce, la aserción habla de ESTA corrida.
    final message = 'Hola profe, ¿arranco con el plan de hoy? '
        '[e2e-${DateTime.now().microsecondsSinceEpoch}]';
    final composer = find.byType(TextField);
    expect(composer, findsWidgets, reason: 'composer field should be present');
    await tester.enterText(composer.last, message);
    await tester.pump();

    // Send button is the IconButton carrying TreinoIcon.send.
    await tester.tap(find.byIcon(TreinoIcon.send));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // The outgoing message bubble should render after the write round-trips
    // through the Firestore emulator stream.
    expect(
      find.text(message),
      findsOneWidget,
      reason: 'sent message should appear as a bubble in the thread',
    );
  });
}
