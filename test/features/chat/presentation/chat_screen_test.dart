import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/analytics/analytics_service.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/chat/data/chat_repository.dart';
import 'package:treino/features/chat/domain/message.dart';
import 'package:treino/features/chat/presentation/chat_screen.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/session_providers.dart';

import '../../../helpers/fake_analytics_service.dart';

Widget _wrap(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: child,
      ),
    );

UserPublicProfile _pub(String uid, String name) => UserPublicProfile(
      uid: uid,
      displayName: name,
      displayNameLowercase: name.toLowerCase(),
    );

Message _msg({
  required String id,
  required String senderId,
  required String text,
  DateTime? at,
}) =>
    Message(
      id: id,
      senderId: senderId,
      text: text,
      createdAt: at ?? DateTime.utc(2026, 5, 21, 11, 0),
    );

void main() {
  group('ChatScreen', () {
    testWidgets('empty state cuando no hay mensajes', (tester) async {
      await tester.pumpWidget(_wrap(
        const ChatScreen(chatId: 'aaa_bbb', otherUid: 'bbb'),
        overrides: [
          currentUidProvider.overrideWith((_) => 'aaa'),
          messagesProvider('aaa_bbb').overrideWith(
            (_) => Stream.value(const <Message>[]),
          ),
          userPublicProfileProvider('bbb').overrideWith(
            (_) => Stream.value(_pub('bbb', 'Coach Joe')),
          ),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Sin mensajes todavía'), findsOneWidget);
      expect(find.textContaining('el primero'), findsOneWidget);
    });

    testWidgets(
        'renderiza burbujas propias (derecha) y ajenas con textos distintos',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const ChatScreen(chatId: 'aaa_bbb', otherUid: 'bbb'),
        overrides: [
          currentUidProvider.overrideWith((_) => 'aaa'),
          messagesProvider('aaa_bbb').overrideWith(
            (_) => Stream.value([
              // recordá: en el stream vienen desc por createdAt
              _msg(
                  id: 'm2',
                  senderId: 'bbb',
                  text: 'dale, ahí voy',
                  at: DateTime.utc(2026, 5, 21, 11, 5)),
              _msg(
                  id: 'm1',
                  senderId: 'aaa',
                  text: 'arranca a las 18',
                  at: DateTime.utc(2026, 5, 21, 11, 0)),
            ]),
          ),
          userPublicProfileProvider('bbb').overrideWith(
            (_) => Stream.value(_pub('bbb', 'Coach Joe')),
          ),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('arranca a las 18'), findsOneWidget);
      expect(find.text('dale, ahí voy'), findsOneWidget);
    });

    testWidgets('título del AppBar usa displayName del otro miembro',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const ChatScreen(chatId: 'aaa_bbb', otherUid: 'bbb'),
        overrides: [
          currentUidProvider.overrideWith((_) => 'aaa'),
          messagesProvider('aaa_bbb').overrideWith(
            (_) => Stream.value(const <Message>[]),
          ),
          userPublicProfileProvider('bbb').overrideWith(
            (_) => Stream.value(_pub('bbb', 'Coach Joe')),
          ),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Coach Joe'), findsOneWidget);
    });

    testWidgets('tap en send escribe el mensaje vía repo y limpia el textfield',
        (tester) async {
      // Usamos un repo real sobre FakeFirebaseFirestore para no mockear.
      final firestore = FakeFirebaseFirestore();
      final repo = ChatRepository(firestore: firestore);
      final chat = await repo.getOrCreate(selfId: 'aaa', otherId: 'bbb');
      final analytics = FakeAnalyticsService();

      await tester.pumpWidget(_wrap(
        ChatScreen(chatId: chat.chatId, otherUid: 'bbb'),
        overrides: [
          firestoreProvider.overrideWithValue(firestore),
          currentUidProvider.overrideWith((_) => 'aaa'),
          userPublicProfileProvider('bbb').overrideWith(
            (_) => Stream.value(_pub('bbb', 'Coach Joe')),
          ),
          analyticsServiceProvider.overrideWithValue(analytics),
        ],
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'hola');
      await tester.tap(find.byTooltip('Enviar'));
      await tester.pumpAndSettle();

      // Mensaje persistido
      final snap = await firestore
          .collection('chats')
          .doc(chat.chatId)
          .collection('messages')
          .get();
      expect(snap.docs.length, 1);
      expect(snap.docs.first.data()['text'], 'hola');

      // Textfield limpio
      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.controller!.text, '');

      // Analytics event disparado.
      expect(analytics.events, contains('chat_message_sent'));
    });

    testWidgets('tap en send con texto vacío no crea ningún mensaje',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      final repo = ChatRepository(firestore: firestore);
      final chat = await repo.getOrCreate(selfId: 'aaa', otherId: 'bbb');

      await tester.pumpWidget(_wrap(
        ChatScreen(chatId: chat.chatId, otherUid: 'bbb'),
        overrides: [
          firestoreProvider.overrideWithValue(firestore),
          currentUidProvider.overrideWith((_) => 'aaa'),
          userPublicProfileProvider('bbb').overrideWith(
            (_) => Stream.value(_pub('bbb', 'Coach Joe')),
          ),
        ],
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Enviar'));
      await tester.pumpAndSettle();

      final snap = await firestore
          .collection('chats')
          .doc(chat.chatId)
          .collection('messages')
          .get();
      expect(snap.docs.length, 0);
    });
  });
}
