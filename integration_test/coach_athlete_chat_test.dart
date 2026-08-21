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
// SEED CONTRACT:
//   • Auth emulator: verified athlete { kSeedEmail / kSeedPassword }, and a
//     second user acting as the coach.
//   • Firestore emulator: a `chats/{chatId}` doc whose participants are the
//     athlete uid and the coach uid (plus whatever the security rules require —
//     see firestore.rules for the chat membership shape). Put the chat id in
//     kChatId and the coach uid in kOtherUid.
//   • Optional: an active trainer↔athlete link, if the rules gate chat writes
//     on it.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/chat/presentation/chat_screen.dart';

import 'support/e2e_helpers.dart';

// TODO(seed): credentials of the seeded athlete.
const String kSeedEmail = 'e2e.athlete@treino.test';
const String kSeedPassword = 'Treino1234';

// TODO(seed): the seeded chat id and the coach (other participant) uid.
const String kChatId = 'REPLACE_WITH_SEEDED_CHAT_ID';
const String kOtherUid = 'REPLACE_WITH_SEEDED_COACH_UID';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initFirebaseForEmulators);

  testWidgets('chat: athlete opens 1-1 with coach and sends a message',
      (tester) async {
    await ensureSignedOut(tester);
    await pumpTreinoApp(tester);

    await signInViaUi(tester, email: kSeedEmail, password: kSeedPassword);

    // Deep-link into the seeded 1-1 chat.
    await goTo(tester, '/coach/chat/$kChatId?other=$kOtherUid');

    expect(
      find.byType(ChatScreen),
      findsOneWidget,
      reason: 'chat route should mount the ChatScreen',
    );

    // Type into the composer TextField and send.
    const message = 'Hola profe, ¿arranco con el plan de hoy?';
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
