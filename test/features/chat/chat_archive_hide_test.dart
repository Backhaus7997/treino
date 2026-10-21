// Archivar y eliminar un chat POR MIEMBRO: modelo, derivaciones y escrituras.
// Las reglas que lo sostienen se prueban en
// scripts/rules_test/chat-archive-hide.test.js.
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/chat/application/chat_contacts_providers.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/chat/data/chat_repository.dart';
import 'package:treino/features/chat/domain/chat.dart';
import 'package:treino/features/chat/domain/message.dart';
import 'package:treino/features/moderation/application/moderation_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';

const _me = 'aaa';
const _other = 'bbb';

final _t0 = DateTime.utc(2026, 10, 1, 12);
final _before = _t0.subtract(const Duration(hours: 1));
final _after = _t0.add(const Duration(hours: 1));

Chat _chat({
  String other = _other,
  DateTime? lastMessageAt,
  String lastSender = _other,
  Map<String, DateTime>? archivedAt,
  Map<String, DateTime>? hiddenBefore,
}) {
  final members = [_me, other]..sort();
  return Chat(
    chatId: members.join('_'),
    members: members,
    createdAt: DateTime.utc(2026, 9, 1),
    lastMessageAt: lastMessageAt,
    lastMessageSenderId: lastSender,
    archivedAt: archivedAt,
    hiddenBefore: hiddenBefore,
  );
}

Message _msg(String id, DateTime at) =>
    Message(id: id, senderId: _other, text: id, createdAt: at);

void main() {
  group('Chat.isArchivedFor / isHiddenFor', () {
    test('archivado y sin mensajes nuevos → archivado', () {
      final c = _chat(lastMessageAt: _before, archivedAt: {_me: _t0});
      expect(c.isArchivedFor(_me), isTrue);
    });

    test('llega un mensaje posterior → vuelve solo a la bandeja', () {
      final c = _chat(lastMessageAt: _after, archivedAt: {_me: _t0});
      expect(c.isArchivedFor(_me), isFalse);
    });

    test('es por miembro: lo que archivo yo no lo archiva para el otro', () {
      final c = _chat(lastMessageAt: _before, archivedAt: {_me: _t0});
      expect(c.isArchivedFor(_other), isFalse);
    });

    test('eliminado: oculto hasta que el otro vuelve a escribir', () {
      expect(
        _chat(lastMessageAt: _before, hiddenBefore: {_me: _t0})
            .isHiddenFor(_me),
        isTrue,
      );
      expect(
        _chat(lastMessageAt: _after, hiddenBefore: {_me: _t0}).isHiddenFor(_me),
        isFalse,
      );
    });
  });

  group('chatHasUnread', () {
    test('archivado o eliminado sin novedades no cuenta como no leído', () {
      expect(
        chatHasUnread(
            _chat(lastMessageAt: _before, archivedAt: {_me: _t0}), _me),
        isFalse,
      );
      expect(
        chatHasUnread(
            _chat(lastMessageAt: _before, hiddenBefore: {_me: _t0}), _me),
        isFalse,
      );
    });

    test('el mensaje que lo desarchiva sí badgea', () {
      expect(
        chatHasUnread(
            _chat(lastMessageAt: _after, archivedAt: {_me: _t0}), _me),
        isTrue,
      );
    });
  });

  test('visibleMessagesFor oculta sólo lo anterior al borrado', () {
    final msgs = [_msg('nuevo', _after), _msg('viejo', _before)];
    expect(visibleMessagesFor(msgs, null), msgs);
    expect(
      visibleMessagesFor(msgs, _t0).map((m) => m.id),
      ['nuevo'],
    );
  });

  group('providers de bandeja', () {
    ProviderContainer container(List<Chat> chats) {
      final c = ProviderContainer(overrides: [
        currentUidProvider.overrideWith((_) => _me),
        chatsForCurrentUserProvider.overrideWith((_) => Stream.value(chats)),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('inbox sin archivados ni eliminados; Archivados sin eliminados',
        () async {
      final normal = _chat(other: 'n', lastMessageAt: _before);
      final archived =
          _chat(other: 'r', lastMessageAt: _before, archivedAt: {_me: _t0});
      final hidden =
          _chat(other: 'h', lastMessageAt: _before, hiddenBefore: {_me: _t0});
      final both = _chat(
        other: 'x',
        lastMessageAt: _before,
        archivedAt: {_me: _t0},
        hiddenBefore: {_me: _t0},
      );
      final c = container([normal, archived, hidden, both]);
      c.listen(inboxChatsProvider, (_, __) {});
      c.listen(archivedChatsProvider, (_, __) {});
      await pumpEventQueue();

      expect(c.read(inboxChatsProvider).requireValue, [normal]);
      expect(c.read(archivedChatsProvider).requireValue, [archived]);
    });

    test('visibleMessagesProvider espera al doc del chat antes de mostrar',
        () async {
      final chatId = ChatRepository.chatIdFor(_me, _other);
      final c = ProviderContainer(overrides: [
        currentUidProvider.overrideWith((_) => _me),
        messagesProvider(chatId).overrideWith(
          (_) => Stream.value([_msg('nuevo', _after), _msg('viejo', _before)]),
        ),
        chatByIdProvider(chatId).overrideWith(
          (_) => Stream.value(
            _chat(lastMessageAt: _after, hiddenBefore: {_me: _t0}),
          ),
        ),
      ]);
      addTearDown(c.dispose);
      c.listen(visibleMessagesProvider(chatId), (_, __) {});
      await pumpEventQueue();

      expect(
        c.read(visibleMessagesProvider(chatId)).requireValue.map((m) => m.id),
        ['nuevo'],
      );
    });

    test('un chat eliminado devuelve a la persona a «Escribile a…»', () async {
      final c = ProviderContainer(overrides: [
        currentUidProvider.overrideWith((_) => _me),
        chatContactLinksAsAthleteProvider
            .overrideWith((_) => Stream.value(const [])),
        chatContactLinksAsTrainerProvider
            .overrideWith((_) => Stream.value(const [])),
        chatContactFollowingProvider
            .overrideWith((_) => Stream.value(const [_other, 'r'])),
        chatsForCurrentUserProvider.overrideWith(
          (_) => Stream.value([
            _chat(lastMessageAt: _before, hiddenBefore: {_me: _t0}),
            _chat(other: 'r', lastMessageAt: _before, archivedAt: {_me: _t0}),
          ]),
        ),
        blockedUidsProvider(_me).overrideWith((_) => Stream.value(const [])),
      ]);
      addTearDown(c.dispose);
      c.listen(chatContactsProvider, (_, __) {});
      await pumpEventQueue();

      // El eliminado vuelve como contacto; el archivado NO (vive en Archivados).
      expect(
        c.read(chatContactsProvider).requireValue,
        [const ChatContact(uid: _other, reason: ChatContactReason.following)],
      );
    });
  });

  group('ChatRepository — escrituras por miembro', () {
    late FakeFirebaseFirestore firestore;
    late ChatRepository repo;
    final chatId = ChatRepository.chatIdFor(_me, _other);

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      repo = ChatRepository(firestore: firestore);
      await firestore.collection('chats').doc(chatId).set({
        'chatId': chatId,
        'members': [_me, _other],
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 9, 1)),
        'lastMessageAt': Timestamp.fromDate(_before),
        'archivedAt': {_other: Timestamp.fromDate(_before)},
      });
    });

    Future<Map<String, Object?>> doc() async =>
        (await firestore.collection('chats').doc(chatId).get()).data()!;

    test('archive escribe SÓLO mi clave y no pisa la del otro', () async {
      await repo.archive(chatId: chatId, uid: _me);
      final archived = (await doc())['archivedAt']! as Map;
      expect(archived.keys, unorderedEquals([_me, _other]));
      expect(archived[_me], isA<Timestamp>());
    });

    test('unarchive borra sólo mi clave', () async {
      await repo.archive(chatId: chatId, uid: _me);
      await repo.unarchive(chatId: chatId, uid: _me);
      expect(((await doc())['archivedAt']! as Map).keys, [_other]);
    });

    test('hideForUser estampa hiddenBefore.{uid} y no borra nada', () async {
      await firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add({'text': 'hola', 'senderId': _other});
      await repo.hideForUser(chatId: chatId, uid: _me);

      expect(((await doc())['hiddenBefore']! as Map).keys, [_me]);
      final msgs = await firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .get();
      expect(msgs.docs, hasLength(1));
    });

    test('el stream se ve archivado apenas se escribe', () async {
      await repo.archive(chatId: chatId, uid: _me);
      final chat = await repo.watchById(chatId).first;
      expect(chat!.isArchivedFor(_me), isTrue);
    });
  });
}
