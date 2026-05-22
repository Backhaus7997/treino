import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/chat/data/chat_repository.dart';
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
      final state =
          await container.read(chatsForCurrentUserProvider.future);
      expect(state, isEmpty);
    });

    test('emite los chats del current user', () async {
      final firestore = FakeFirebaseFirestore();
      final container =
          makeContainer(firestore: firestore, currentUid: 'aaa');
      final repo = container.read(chatRepositoryProvider);

      // Crear chat + mandar mensaje para que aparezca en el orderBy
      final chat =
          await repo.getOrCreate(selfId: 'aaa', otherId: 'bbb');
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
      final container =
          makeContainer(firestore: firestore, currentUid: 'aaa');
      final repo = container.read(chatRepositoryProvider);
      final chat =
          await repo.getOrCreate(selfId: 'aaa', otherId: 'bbb');
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

  group('chatForLinkProvider', () {
    test('crea o resuelve el chat para un link (desde lado athlete)',
        () async {
      final firestore = FakeFirebaseFirestore();
      final container =
          makeContainer(firestore: firestore, currentUid: 'athlete-1');
      final link = makeLink(trainerId: 'trainer-1', athleteId: 'athlete-1');

      final chat = await container.read(chatForLinkProvider(link).future);
      expect(chat.members.contains('athlete-1'), isTrue);
      expect(chat.members.contains('trainer-1'), isTrue);
    });

    test('crea o resuelve el chat para un link (desde lado trainer)',
        () async {
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
