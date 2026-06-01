// T49 RED — SCENARIO-570: chat renders "Usuario eliminado" when public profile is absent
//
// Per ADR-ACCDEL-005: when a user's account is deleted, userPublicProfiles/{uid}
// is deleted by the CF. The chat UI must render "Usuario eliminado" at read time
// instead of crashing or showing a blank name.
//
// We test the ChatListScreen's _ChatRow which uses userPublicProfileProvider
// to look up the other user's name. When the profile doc is null (deleted),
// the row should show "Usuario eliminado".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/chat/domain/chat.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;

import '../../../../helpers/test_app_wrapper.dart';
import 'package:treino/features/chat/presentation/chat_list_screen.dart';

void main() {
  const currentUid = 'current-user-uid';
  const deletedUid = 'deleted-user-uid';

  final fakeChat = Chat(
    chatId: 'chat-1',
    members: const [currentUid, deletedUid],
    createdAt: DateTime(2026, 5, 1),
    lastMessageText: 'Hola',
    lastMessageAt: DateTime(2026, 5, 27),
  );

  Widget buildChatListScreen({
    required UserPublicProfile? deletedUserProfile,
  }) {
    return ProviderScope(
      overrides: [
        authStateChangesProvider.overrideWith((_) => const Stream.empty()),
        currentUidProvider.overrideWithValue(currentUid),
        chatsForCurrentUserProvider
            .overrideWith((_) => Stream.value([fakeChat])),
        userPublicProfileProvider(deletedUid).overrideWith(
          (_) => Stream.value(deletedUserProfile),
        ),
      ],
      child: const TestAppWrapper(child: ChatListScreen()),
    );
  }

  // SCENARIO-570: null profile (deleted user) → "Usuario eliminado"
  testWidgets(
      'SCENARIO-570: null userPublicProfile for senderId shows "Usuario eliminado"',
      (tester) async {
    await tester.pumpWidget(buildChatListScreen(deletedUserProfile: null));
    await tester.pumpAndSettle();

    // When the public profile is null (deleted user), the chat row must
    // display "Usuario eliminado" instead of a blank name or crashing.
    expect(
      find.text('Usuario eliminado'), // i18n: Fase 6 Etapa 3
      findsAtLeastNWidgets(1),
    );
  });

  // Positive: existing profile shows the real display name
  testWidgets('existing public profile shows display name', (tester) async {
    const profile = UserPublicProfile(
      uid: deletedUid,
      displayName: 'Ana García',
      avatarUrl: null,
    );

    await tester.pumpWidget(buildChatListScreen(deletedUserProfile: profile));
    await tester.pumpAndSettle();

    expect(find.text('Ana García'), findsAtLeastNWidgets(1));
    expect(find.text('Usuario eliminado'), findsNothing);
  });
}
