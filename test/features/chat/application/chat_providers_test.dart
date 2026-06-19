import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/chat/data/chat_repository.dart';
import 'package:treino/features/chat/domain/chat.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';

void main() {
  // ── Helpers ──────────────────────────────────────────────────────────────

  ProviderContainer makeContainer({
    required FakeFirebaseFirestore firestore,
    String? currentUid,
  }) {
    final container = ProviderContainer(overrides: [
      firestoreProvider.overrideWithValue(firestore),
      currentUidProvider.overrideWith((ref) => currentUid),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  TrainerLink makeLink({
    required String trainerId,
    required String athleteId,
    TrainerLinkStatus status = TrainerLinkStatus.active,
  }) =>
      TrainerLink(
        id: 'link-${trainerId}_$athleteId',
        trainerId: trainerId,
        athleteId: athleteId,
        status: status,
        requestedAt: DateTime.utc(2026, 5, 21, 10, 0),
        acceptedAt: status == TrainerLinkStatus.active
            ? DateTime.utc(2026, 5, 21, 11, 0)
            : null,
      );

  group('chatRepositoryProvider', () {
    test('expone una instancia de ChatRepository', () {
      final container = makeContainer(firestore: FakeFirebaseFirestore());
      final repo = container.read(chatRepositoryProvider);
      expect(repo, isA<ChatRepository>());
    });
  });

  group('chatsForCurrentUserProvider', () {
    test('emite lista vacía cuando no hay current uid', () async {
      final container =
          makeContainer(firestore: FakeFirebaseFirestore(), currentUid: null);
      final state = await container.read(chatsForCurrentUserProvider.future);
      expect(state, isEmpty);
    });

    test('emite los chats del current user', () async {
      final firestore = FakeFirebaseFirestore();
      final container = makeContainer(firestore: firestore, currentUid: 'aaa');
      final repo = container.read(chatRepositoryProvider);

      // Crear chat + mandar mensaje para que aparezca en el orderBy
      final chat = await repo.getOrCreate(selfId: 'aaa', otherId: 'bbb');
      await repo.sendMessage(
          chatId: chat.chatId, senderId: 'aaa', text: 'hola');

      final chats = await container.read(chatsForCurrentUserProvider.future);
      expect(chats.length, 1);
      expect(chats.first.members, ['aaa', 'bbb']);
    });
  });

  group('messagesProvider', () {
    test('emite mensajes de un chatId', () async {
      final firestore = FakeFirebaseFirestore();
      final container = makeContainer(firestore: firestore, currentUid: 'aaa');
      final repo = container.read(chatRepositoryProvider);
      final chat = await repo.getOrCreate(selfId: 'aaa', otherId: 'bbb');
      await repo.sendMessage(
          chatId: chat.chatId, senderId: 'aaa', text: 'hola');

      final messages =
          await container.read(messagesProvider(chat.chatId).future);
      expect(messages.length, 1);
      expect(messages.first.text, 'hola');
    });

    test('emite lista vacía cuando el chatId es ""', () async {
      final container =
          makeContainer(firestore: FakeFirebaseFirestore(), currentUid: 'aaa');
      final messages = await container.read(messagesProvider('').future);
      expect(messages, isEmpty);
    });
  });

  // ── chatHasUnread ────────────────────────────────────────────────────────

  group('chatHasUnread', () {
    const uid = 'aaa';
    const otherUid = 'bbb';
    final base = DateTime.utc(2026, 6, 1, 10, 0);
    final before = base.subtract(const Duration(minutes: 5));
    final after = base.add(const Duration(minutes: 5));

    Chat makeChat({
      DateTime? lastMessageAt,
      String? lastMessageSenderId,
      Map<String, DateTime>? lastRead,
    }) =>
        Chat(
          chatId: 'aaa_bbb',
          members: const ['aaa', 'bbb'],
          createdAt: DateTime.utc(2026, 1, 1),
          lastMessageAt: lastMessageAt,
          lastMessageSenderId: lastMessageSenderId,
          lastRead: lastRead,
        );

    test('other sender + null lastRead → unread', () {
      final c = makeChat(
        lastMessageAt: base,
        lastMessageSenderId: otherUid,
        lastRead: null,
      );
      expect(chatHasUnread(c, uid), isTrue);
    });

    test('other sender + lastRead before lastMessageAt → unread', () {
      final c = makeChat(
        lastMessageAt: base,
        lastMessageSenderId: otherUid,
        lastRead: {uid: before},
      );
      expect(chatHasUnread(c, uid), isTrue);
    });

    test('other sender + lastRead after lastMessageAt → read', () {
      final c = makeChat(
        lastMessageAt: base,
        lastMessageSenderId: otherUid,
        lastRead: {uid: after},
      );
      expect(chatHasUnread(c, uid), isFalse);
    });

    test('other sender + lastRead == lastMessageAt → read (equal = read)', () {
      final c = makeChat(
        lastMessageAt: base,
        lastMessageSenderId: otherUid,
        lastRead: {uid: base},
      );
      expect(chatHasUnread(c, uid), isFalse);
    });

    test('self sender → read regardless of lastRead', () {
      final c = makeChat(
        lastMessageAt: base,
        lastMessageSenderId: uid,
        lastRead: null,
      );
      expect(chatHasUnread(c, uid), isFalse);
    });

    test('lastMessageAt null → read (no message)', () {
      final c = makeChat(
        lastMessageAt: null,
        lastMessageSenderId: otherUid,
        lastRead: null,
      );
      expect(chatHasUnread(c, uid), isFalse);
    });

    test('uid key missing from lastRead map → unread', () {
      final c = makeChat(
        lastMessageAt: base,
        lastMessageSenderId: otherUid,
        lastRead: {otherUid: after}, // only otherUid has entry, not uid
      );
      expect(chatHasUnread(c, uid), isTrue);
    });
  });

  // ── totalUnreadCountProvider ─────────────────────────────────────────────

  group('totalUnreadCountProvider', () {
    final base = DateTime.utc(2026, 6, 1, 10, 0);
    final before = base.subtract(const Duration(minutes: 5));

    Chat makeUnreadChat(String chatId, String uid) => Chat(
          chatId: chatId,
          members: const ['aaa', 'bbb'],
          createdAt: DateTime.utc(2026, 1, 1),
          lastMessageAt: base,
          lastMessageSenderId: 'bbb',
          lastRead: {uid: before},
        );

    Chat makeReadChat(String chatId, String uid) => Chat(
          chatId: chatId,
          members: const ['aaa', 'bbb'],
          createdAt: DateTime.utc(2026, 1, 1),
          lastMessageAt: before,
          lastMessageSenderId: 'bbb',
          lastRead: {uid: base},
        );

    ProviderContainer makeContainerWithChats(
      List<Chat> chats, {
      String? uid,
    }) {
      final container = ProviderContainer(overrides: [
        currentUidProvider.overrideWith((ref) => uid),
        chatsForCurrentUserProvider.overrideWith(
          (ref) => Stream.value(chats),
        ),
      ]);
      addTearDown(container.dispose);
      return container;
    }

    test('3 chats 2 unread → 2', () async {
      const uid = 'aaa';
      final chats = [
        makeUnreadChat('c1', uid),
        makeUnreadChat('c2', uid),
        makeReadChat('c3', uid),
      ];
      final container = makeContainerWithChats(chats, uid: uid);
      // Subscribe to keep autoDispose alive and wait for stream to emit
      final sub = container.listen(totalUnreadCountProvider, (_, __) {});
      await container.read(chatsForCurrentUserProvider.future);
      final count = container.read(totalUnreadCountProvider);
      sub.close();
      expect(count, 2);
    });

    test('0 chats → 0', () async {
      final container = makeContainerWithChats([], uid: 'aaa');
      final sub = container.listen(totalUnreadCountProvider, (_, __) {});
      await container.read(chatsForCurrentUserProvider.future);
      final count = container.read(totalUnreadCountProvider);
      sub.close();
      expect(count, 0);
    });

    test('null uid → 0', () async {
      final container = makeContainerWithChats([], uid: null);
      final sub = container.listen(totalUnreadCountProvider, (_, __) {});
      await Future.delayed(Duration.zero);
      final count = container.read(totalUnreadCountProvider);
      sub.close();
      expect(count, 0);
    });

    test('chatsForCurrentUserProvider loading → 0', () {
      final container = ProviderContainer(overrides: [
        currentUidProvider.overrideWith((ref) => 'aaa'),
        chatsForCurrentUserProvider.overrideWith(
          (ref) => Stream<List<Chat>>.fromFuture(
            Completer<List<Chat>>().future,
          ),
        ),
      ]);
      addTearDown(container.dispose);
      expect(container.read(totalUnreadCountProvider), 0);
    });

    test('chatsForCurrentUserProvider error → 0', () async {
      final container = ProviderContainer(overrides: [
        currentUidProvider.overrideWith((ref) => 'aaa'),
        chatsForCurrentUserProvider.overrideWith(
          (ref) => Stream<List<Chat>>.error(Exception('err')),
        ),
      ]);
      addTearDown(container.dispose);
      await Future.delayed(Duration.zero);
      expect(container.read(totalUnreadCountProvider), 0);
    });
  });

  group('chatForLinkProvider', () {
    test('crea o resuelve el chat para un link (desde lado athlete)', () async {
      final firestore = FakeFirebaseFirestore();
      final container =
          makeContainer(firestore: firestore, currentUid: 'athlete-1');
      final link = makeLink(trainerId: 'trainer-1', athleteId: 'athlete-1');

      final chat = await container.read(chatForLinkProvider(link).future);
      expect(chat.members.contains('athlete-1'), isTrue);
      expect(chat.members.contains('trainer-1'), isTrue);
    });

    test('crea o resuelve el chat para un link (desde lado trainer)', () async {
      final firestore = FakeFirebaseFirestore();
      final container =
          makeContainer(firestore: firestore, currentUid: 'trainer-1');
      final link = makeLink(trainerId: 'trainer-1', athleteId: 'athlete-1');

      final chat = await container.read(chatForLinkProvider(link).future);
      expect(chat.members.contains('athlete-1'), isTrue);
      expect(chat.members.contains('trainer-1'), isTrue);
    });

    test('falla si no hay current uid', () async {
      final container =
          makeContainer(firestore: FakeFirebaseFirestore(), currentUid: null);
      final link = makeLink(trainerId: 'trainer-1', athleteId: 'athlete-1');
      expect(
        () => container.read(chatForLinkProvider(link).future),
        throwsA(isA<StateError>()),
      );
    });

    test('idempotente — ambos lados resuelven al mismo chat', () async {
      final firestore = FakeFirebaseFirestore();
      final link = makeLink(trainerId: 'trainer-1', athleteId: 'athlete-1');

      final athleteContainer =
          makeContainer(firestore: firestore, currentUid: 'athlete-1');
      final fromAthlete =
          await athleteContainer.read(chatForLinkProvider(link).future);

      final trainerContainer =
          makeContainer(firestore: firestore, currentUid: 'trainer-1');
      final fromTrainer =
          await trainerContainer.read(chatForLinkProvider(link).future);

      expect(fromAthlete.chatId, fromTrainer.chatId);

      // Y solo hay un doc en Firestore
      final all = await firestore.collection('chats').get();
      expect(all.docs.length, 1);
    });
  });
}
