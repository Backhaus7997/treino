import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/chat/data/chat_repository.dart';
import 'package:treino/features/chat/domain/media_type.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late ChatRepository repo;

  const uidA = 'aaa';
  const uidB = 'bbb';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = ChatRepository(firestore: firestore);
  });

  // ─── chatIdFor ──────────────────────────────────────────────────────────

  group('chatIdFor', () {
    test('determinístico — orden no importa', () {
      expect(ChatRepository.chatIdFor(uidA, uidB),
          equals(ChatRepository.chatIdFor(uidB, uidA)));
    });

    test('formato sortedUids.join("_")', () {
      expect(ChatRepository.chatIdFor('zzz', 'aaa'), 'aaa_zzz');
    });

    test('rechaza uidA == uidB', () {
      expect(() => ChatRepository.chatIdFor('same', 'same'),
          throwsA(isA<ArgumentError>()));
    });
  });

  // ─── getOrCreate ────────────────────────────────────────────────────────

  group('getOrCreate', () {
    test('crea doc nuevo con members ordenados', () async {
      final chat = await repo.getOrCreate(selfId: uidA, otherId: uidB);
      expect(chat.chatId, 'aaa_bbb');
      expect(chat.members, ['aaa', 'bbb']);
      expect(chat.lastMessageAt, isNull);

      final snap = await firestore.collection('chats').doc('aaa_bbb').get();
      expect(snap.exists, isTrue);
      expect(snap.data()!['members'], ['aaa', 'bbb']);
    });

    test('idempotente — segunda llamada no crea otro doc', () async {
      await repo.getOrCreate(selfId: uidA, otherId: uidB);
      await repo.getOrCreate(selfId: uidB, otherId: uidA);
      final all = await firestore.collection('chats').get();
      expect(all.docs.length, 1);
    });

    test('devuelve el mismo Chat desde ambos lados', () async {
      final fromA = await repo.getOrCreate(selfId: uidA, otherId: uidB);
      final fromB = await repo.getOrCreate(selfId: uidB, otherId: uidA);
      expect(fromA.chatId, fromB.chatId);
      expect(fromA.members, fromB.members);
    });
  });

  // ─── sendMessage ────────────────────────────────────────────────────────

  group('sendMessage — text-only (regression, REQ-CHATMEDIA-015)', () {
    late String chatId;
    setUp(() async {
      final chat = await repo.getOrCreate(selfId: uidA, otherId: uidB);
      chatId = chat.chatId;
    });

    test('escribe doc en messages sub-collection', () async {
      await repo.sendMessage(chatId: chatId, senderId: uidA, text: 'hola');
      final snap = await firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .get();
      expect(snap.docs.length, 1);
      expect(snap.docs.first.data()['text'], 'hola');
      expect(snap.docs.first.data()['senderId'], uidA);
    });

    test('actualiza lastMessageText + lastMessageSenderId en el parent',
        () async {
      await repo.sendMessage(
          chatId: chatId, senderId: uidA, text: 'arranca a las 18');
      final parent = await firestore.collection('chats').doc(chatId).get();
      expect(parent.data()!['lastMessageText'], 'arranca a las 18');
      expect(parent.data()!['lastMessageSenderId'], uidA);
      expect(parent.data()!['lastMessageAt'], isNotNull);
    });

    test('preview se trunca a 80 chars con elipsis', () async {
      final longText = 'x' * 100;
      await repo.sendMessage(chatId: chatId, senderId: uidA, text: longText);
      final parent = await firestore.collection('chats').doc(chatId).get();
      final preview = parent.data()!['lastMessageText'] as String;
      expect(preview.length, 81); // 80 chars + 1 elipsis
      expect(preview.endsWith('…'), isTrue);
    });

    test('rechaza texto vacío sin media (REQ-CHATMEDIA-005)', () async {
      expect(
        () => repo.sendMessage(chatId: chatId, senderId: uidA, text: ''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rechaza texto solo-whitespace sin media', () async {
      expect(
        () => repo.sendMessage(chatId: chatId, senderId: uidA, text: '   '),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('trimea whitespace del texto antes de guardar', () async {
      await repo.sendMessage(chatId: chatId, senderId: uidA, text: '  hola  ');
      final snap = await firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .get();
      expect(snap.docs.first.data()['text'], 'hola');
    });
  });

  // ─── sendMessage — media (REQ-CHATMEDIA-003/004/005/011) ────────────────

  group('sendMessage — media messages', () {
    late String chatId;
    const mediaUrl =
        'https://storage.googleapis.com/bucket/chatMedia/c1/u1/img.jpg';

    setUp(() async {
      final chat = await repo.getOrCreate(selfId: uidA, otherId: uidB);
      chatId = chat.chatId;
    });

    // REQ-CHATMEDIA-003 + REQ-CHATMEDIA-011
    test('image-only: lastMessageText == "📷 Foto"', () async {
      await repo.sendMessage(
        chatId: chatId,
        senderId: uidA,
        mediaUrl: mediaUrl,
        mediaType: MediaType.image,
      );
      final parent = await firestore.collection('chats').doc(chatId).get();
      expect(parent.data()!['lastMessageText'], '📷 Foto');
    });

    // REQ-CHATMEDIA-003: doc fields written correctly
    test('image-only: message doc has mediaUrl and mediaType', () async {
      await repo.sendMessage(
        chatId: chatId,
        senderId: uidA,
        mediaUrl: mediaUrl,
        mediaType: MediaType.image,
      );
      final snap = await firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .get();
      expect(snap.docs.length, 1);
      final data = snap.docs.first.data();
      expect(data['mediaUrl'], mediaUrl);
      expect(data['mediaType'], 'image');
      expect(data['text'], '');
    });

    // REQ-CHATMEDIA-004 + REQ-CHATMEDIA-011
    test('video-only: lastMessageText == "🎥 Video"', () async {
      await repo.sendMessage(
        chatId: chatId,
        senderId: uidA,
        mediaUrl: 'https://example.com/vid.mp4',
        mediaType: MediaType.video,
      );
      final parent = await firestore.collection('chats').doc(chatId).get();
      expect(parent.data()!['lastMessageText'], '🎥 Video');
    });

    // REQ-CHATMEDIA-003: caption wins
    test('image + caption: lastMessageText uses caption', () async {
      await repo.sendMessage(
        chatId: chatId,
        senderId: uidA,
        text: 'Great form!',
        mediaUrl: mediaUrl,
        mediaType: MediaType.image,
      );
      final parent = await firestore.collection('chats').doc(chatId).get();
      expect(parent.data()!['lastMessageText'], 'Great form!');
    });

    // REQ-CHATMEDIA-004: video caption wins
    test('video + caption: lastMessageText uses caption', () async {
      await repo.sendMessage(
        chatId: chatId,
        senderId: uidA,
        text: 'Watch this rep',
        mediaUrl: 'https://example.com/vid.mp4',
        mediaType: MediaType.video,
      );
      final parent = await firestore.collection('chats').doc(chatId).get();
      expect(parent.data()!['lastMessageText'], 'Watch this rep');
    });

    // REQ-CHATMEDIA-011: caption truncates at 80 chars
    test('caption over 80 chars is truncated with ellipsis', () async {
      final longCaption = 'A' * 100;
      await repo.sendMessage(
        chatId: chatId,
        senderId: uidA,
        text: longCaption,
        mediaUrl: mediaUrl,
        mediaType: MediaType.image,
      );
      final parent = await firestore.collection('chats').doc(chatId).get();
      final preview = parent.data()!['lastMessageText'] as String;
      expect(preview.length, 81); // 80 + '…'
      expect(preview.endsWith('…'), isTrue);
    });

    // REQ-CHATMEDIA-005: empty text AND null mediaUrl → ArgumentError, no write
    test(
        'empty text + null mediaUrl throws ArgumentError without Firestore write',
        () async {
      expect(
        () => repo.sendMessage(
            chatId: chatId, senderId: uidA, text: '', mediaUrl: null),
        throwsA(isA<ArgumentError>()),
      );
      // Verify no message was written
      final snap = await firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .get();
      expect(snap.docs, isEmpty);
    });

    // REQ-CHATMEDIA-005: mediaUrl present but mediaType null → ArgumentError
    test('mediaUrl without mediaType throws ArgumentError', () async {
      expect(
        () => repo.sendMessage(
          chatId: chatId,
          senderId: uidA,
          mediaUrl: mediaUrl,
          mediaType: null,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // ─── watchMessages ──────────────────────────────────────────────────────

  group('watchMessages', () {
    late String chatId;
    setUp(() async {
      final chat = await repo.getOrCreate(selfId: uidA, otherId: uidB);
      chatId = chat.chatId;
    });

    test('emite lista vacía cuando no hay mensajes', () async {
      final stream = repo.watchMessages(chatId);
      final messages = await stream.first;
      expect(messages, isEmpty);
    });

    test('emite mensajes ordenados desc por createdAt', () async {
      await repo.sendMessage(chatId: chatId, senderId: uidA, text: 'primero');
      await Future.delayed(const Duration(milliseconds: 10));
      await repo.sendMessage(chatId: chatId, senderId: uidB, text: 'segundo');
      await Future.delayed(const Duration(milliseconds: 10));
      await repo.sendMessage(chatId: chatId, senderId: uidA, text: 'tercero');

      final messages = await repo.watchMessages(chatId).first;
      expect(messages.length, 3);
      // desc → tercero, segundo, primero
      expect(messages[0].text, 'tercero');
      expect(messages[1].text, 'segundo');
      expect(messages[2].text, 'primero');
    });

    test('respeta el limit', () async {
      for (var i = 0; i < 5; i++) {
        await repo.sendMessage(chatId: chatId, senderId: uidA, text: 'msg $i');
        await Future.delayed(const Duration(milliseconds: 5));
      }
      final messages = await repo.watchMessages(chatId, limit: 3).first;
      expect(messages.length, 3);
    });

    // REQ-CHATMEDIA-001: stream surfaces mediaUrl and mediaType
    test('stream surfaces mediaUrl and mediaType for media messages', () async {
      const url = 'https://example.com/photo.jpg';
      await repo.sendMessage(
        chatId: chatId,
        senderId: uidA,
        mediaUrl: url,
        mediaType: MediaType.image,
      );
      final messages = await repo.watchMessages(chatId).first;
      expect(messages.length, 1);
      expect(messages.first.mediaUrl, url);
      expect(messages.first.mediaType, MediaType.image);
      expect(messages.first.text, '');
    });
  });

  // ─── watchChatsForUser ──────────────────────────────────────────────────

  group('watchChatsForUser', () {
    test('emite solo los chats donde el uid es miembro', () async {
      await repo.getOrCreate(selfId: uidA, otherId: uidB);
      await repo.getOrCreate(selfId: 'ccc', otherId: 'ddd'); // unrelated

      // Forzamos un mensaje en el primer chat para que tenga lastMessageAt
      // (el orderBy de Firestore filtra docs sin el campo).
      final chatAB = ChatRepository.chatIdFor(uidA, uidB);
      await repo.sendMessage(chatId: chatAB, senderId: uidA, text: 'hola b');

      final chats = await repo.watchChatsForUser(uidA).first;
      expect(chats.length, 1);
      expect(chats.first.chatId, chatAB);
      expect(chats.first.members.contains(uidA), isTrue);
    });

    test('emite lista vacía cuando el user no tiene chats', () async {
      final chats = await repo.watchChatsForUser('lonely').first;
      expect(chats, isEmpty);
    });

    test('ordena por lastMessageAt desc', () async {
      // Chat 1: aaa-bbb
      final id1 = (await repo.getOrCreate(selfId: uidA, otherId: uidB)).chatId;
      await repo.sendMessage(chatId: id1, senderId: uidA, text: 'primero');
      await Future.delayed(const Duration(milliseconds: 20));

      // Chat 2: aaa-ccc
      final id2 = (await repo.getOrCreate(selfId: uidA, otherId: 'ccc')).chatId;
      await repo.sendMessage(chatId: id2, senderId: uidA, text: 'segundo');

      final chats = await repo.watchChatsForUser(uidA).first;
      expect(chats.length, 2);
      // El más reciente (id2) primero
      expect(chats[0].chatId, id2);
      expect(chats[1].chatId, id1);
    });
  });

  // ─── markAsRead ─────────────────────────────────────────────────────────

  group('markAsRead', () {
    late String chatId;
    setUp(() async {
      final chat = await repo.getOrCreate(selfId: uidA, otherId: uidB);
      chatId = chat.chatId;
      // Need a message so lastMessageAt exists (for watchChatsForUser)
      await repo.sendMessage(chatId: chatId, senderId: uidB, text: 'hola');
    });

    test('writes lastRead[uid] as a non-null Timestamp for caller', () async {
      await repo.markAsRead(chatId: chatId, uid: uidA);
      final snap = await firestore.collection('chats').doc(chatId).get();
      final data = snap.data()!;
      expect(data['lastRead'], isNotNull);
      final lastRead = data['lastRead'] as Map<String, Object?>;
      expect(lastRead[uidA], isNotNull);
    });

    test(
        'markAsRead(A) then markAsRead(B) leaves both keys present (no clobber)',
        () async {
      await repo.markAsRead(chatId: chatId, uid: uidA);
      await repo.markAsRead(chatId: chatId, uid: uidB);
      final snap = await firestore.collection('chats').doc(chatId).get();
      final lastRead = snap.data()!['lastRead'] as Map<String, Object?>;
      expect(lastRead[uidA], isNotNull);
      expect(lastRead[uidB], isNotNull);
    });

    test('re-marking A does not disturb B key', () async {
      await repo.markAsRead(chatId: chatId, uid: uidA);
      await repo.markAsRead(chatId: chatId, uid: uidB);
      // Re-mark A
      await repo.markAsRead(chatId: chatId, uid: uidA);
      final snap = await firestore.collection('chats').doc(chatId).get();
      final lastRead = snap.data()!['lastRead'] as Map<String, Object?>;
      expect(lastRead[uidA], isNotNull);
      expect(lastRead[uidB], isNotNull);
    });

    test('watchChatsForUser surfaces lastRead in returned Chat objects',
        () async {
      await repo.markAsRead(chatId: chatId, uid: uidA);
      final chats = await repo.watchChatsForUser(uidA).first;
      expect(chats, isNotEmpty);
      final chat = chats.firstWhere((c) => c.chatId == chatId);
      expect(chat.lastRead, isNotNull);
      expect(chat.lastRead![uidA], isNotNull);
    });
  });
}
