import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/chat/domain/chat.dart';
import 'package:treino/features/chat/presentation/chat_list_screen.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/session_providers.dart';

Widget _wrap(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: child,
      ),
    );

Chat _chat({
  String chatId = 'aaa_bbb',
  List<String> members = const ['aaa', 'bbb'],
  String? lastMessageText,
  DateTime? lastMessageAt,
  String? lastMessageSenderId,
}) =>
    Chat(
      chatId: chatId,
      members: members,
      createdAt: DateTime.utc(2026, 5, 21, 10, 0),
      lastMessageText: lastMessageText,
      lastMessageAt: lastMessageAt,
      lastMessageSenderId: lastMessageSenderId,
    );

UserPublicProfile _pub(String uid, String name) => UserPublicProfile(
      uid: uid,
      displayName: name,
      displayNameLowercase: name.toLowerCase(),
    );

void main() {
  group('ChatListScreen', () {
    testWidgets('empty state cuando no hay chats', (tester) async {
      await tester.pumpWidget(_wrap(
        const ChatListScreen(),
        overrides: [
          currentUidProvider.overrideWith((_) => 'aaa'),
          chatsForCurrentUserProvider
              .overrideWith((ref) => Stream.value(const <Chat>[])),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Sin mensajes todavía'), findsOneWidget);
      expect(find.textContaining('vínculo activo con un PF'), findsOneWidget);
    });

    testWidgets('lista de chats — muestra nombre del otro miembro + preview',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const ChatListScreen(),
        overrides: [
          currentUidProvider.overrideWith((_) => 'aaa'),
          chatsForCurrentUserProvider.overrideWith(
            (ref) => Stream.value([
              _chat(
                chatId: 'aaa_bbb',
                members: const ['aaa', 'bbb'],
                lastMessageText: 'arranca a las 18',
                lastMessageAt: DateTime.now().subtract(
                  const Duration(minutes: 5),
                ),
                lastMessageSenderId: 'bbb',
              ),
            ]),
          ),
          userPublicProfileProvider('bbb').overrideWith(
            (_) => Stream.value(_pub('bbb', 'Coach Joe')),
          ),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Coach Joe'), findsOneWidget);
      expect(find.text('arranca a las 18'), findsOneWidget);
    });

    testWidgets('placeholder cuando el chat no tiene mensajes todavía',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const ChatListScreen(),
        overrides: [
          currentUidProvider.overrideWith((_) => 'aaa'),
          chatsForCurrentUserProvider.overrideWith(
            (ref) => Stream.value([
              _chat(chatId: 'aaa_bbb', members: const ['aaa', 'bbb']),
            ]),
          ),
          userPublicProfileProvider('bbb').overrideWith(
            (_) => Stream.value(_pub('bbb', 'Coach Joe')),
          ),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Iniciá la conversación'), findsOneWidget);
    });
  });
}
