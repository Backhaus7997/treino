import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/chat/domain/chat.dart';

void main() {
  group('Chat JSON round-trip', () {
    test('full record with last message metadata', () {
      final chat = Chat(
        chatId: 'aaa_bbb',
        members: const ['aaa', 'bbb'],
        createdAt: DateTime.utc(2026, 5, 21, 10, 0),
        lastMessageAt: DateTime.utc(2026, 5, 21, 11, 30),
        lastMessageText: 'nos vemos a las 18',
        lastMessageSenderId: 'aaa',
      );
      final decoded = Chat.fromJson(chat.toJson());
      expect(decoded, equals(chat));
    });

    test('fresh chat without messages yet (last* nullable)', () {
      final chat = Chat(
        chatId: 'aaa_bbb',
        members: const ['aaa', 'bbb'],
        createdAt: DateTime.utc(2026, 5, 21, 10, 0),
      );
      final decoded = Chat.fromJson(chat.toJson());
      expect(decoded.lastMessageAt, isNull);
      expect(decoded.lastMessageText, isNull);
      expect(decoded.lastMessageSenderId, isNull);
      expect(decoded, equals(chat));
    });

    test('fromJson with Firestore Timestamps deserializes correctly', () {
      final rawMap = <String, dynamic>{
        'chatId': 'aaa_bbb',
        'members': ['aaa', 'bbb'],
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 5, 21, 10, 0)),
        'lastMessageAt': Timestamp.fromDate(DateTime.utc(2026, 5, 21, 12, 0)),
        'lastMessageText': 'hola',
        'lastMessageSenderId': 'bbb',
      };
      final decoded = Chat.fromJson(rawMap);
      expect(decoded.chatId, 'aaa_bbb');
      expect(decoded.members, ['aaa', 'bbb']);
      expect(decoded.createdAt, DateTime.utc(2026, 5, 21, 10, 0));
      expect(decoded.lastMessageAt, DateTime.utc(2026, 5, 21, 12, 0));
      expect(decoded.lastMessageSenderId, 'bbb');
    });

    test('equality holds for identical records', () {
      final a = Chat(
        chatId: 'aaa_bbb',
        members: const ['aaa', 'bbb'],
        createdAt: DateTime.utc(2026, 5, 21, 10, 0),
      );
      final b = Chat(
        chatId: 'aaa_bbb',
        members: const ['aaa', 'bbb'],
        createdAt: DateTime.utc(2026, 5, 21, 10, 0),
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });

  group('Chat.lastRead', () {
    final t0 = DateTime.utc(2026, 6, 1, 10, 0);
    final t1 = DateTime.utc(2026, 6, 1, 11, 0);

    test('lastRead round-trips correctly with uid → DateTime map', () {
      final chat = Chat(
        chatId: 'aaa_bbb',
        members: const ['aaa', 'bbb'],
        createdAt: t0,
        lastRead: {'aaa': t1},
      );
      final decoded = Chat.fromJson(chat.toJson());
      expect(decoded.lastRead, isNotNull);
      expect(decoded.lastRead!['aaa'], equals(t1));
    });

    test('lastRead: null round-trips to null', () {
      final chat = Chat(
        chatId: 'aaa_bbb',
        members: const ['aaa', 'bbb'],
        createdAt: t0,
      );
      final decoded = Chat.fromJson(chat.toJson());
      expect(decoded.lastRead, isNull);
    });

    test('fromJson decodes raw Timestamp map from Firestore path', () {
      final rawMap = <String, Object?>{
        'chatId': 'aaa_bbb',
        'members': ['aaa', 'bbb'],
        'createdAt': Timestamp.fromDate(t0),
        'lastRead': {
          'aaa': Timestamp.fromDate(t1),
        },
      };
      final decoded = Chat.fromJson(rawMap);
      expect(decoded.lastRead, isNotNull);
      expect(decoded.lastRead!['aaa'], equals(t1));
    });

    test('no lastRead key in JSON → lastRead is null (legacy doc)', () {
      final rawMap = <String, Object?>{
        'chatId': 'aaa_bbb',
        'members': ['aaa', 'bbb'],
        'createdAt': Timestamp.fromDate(t0),
      };
      final decoded = Chat.fromJson(rawMap);
      expect(decoded.lastRead, isNull);
    });

    test('copyWith preserves lastRead when not overridden', () {
      final chat = Chat(
        chatId: 'aaa_bbb',
        members: const ['aaa', 'bbb'],
        createdAt: t0,
        lastRead: {'aaa': t1},
      );
      final copied = chat.copyWith(lastMessageText: 'hey');
      expect(copied.lastRead, equals(chat.lastRead));
    });
  });

  // `closedAt` lo escribe una Cloud Function cuando termina el vínculo del par
  // (#1697). Ausente = abierto: es como se lee todo doc anterior al campo.
  group('Chat.closedAt / isClosed', () {
    final t0 = DateTime.utc(2026, 6, 1, 10, 0);
    final t1 = DateTime.utc(2026, 11, 12, 9, 30);

    test('Timestamp de Firestore → closedAt parseado e isClosed true', () {
      final decoded = Chat.fromJson(<String, Object?>{
        'chatId': 'aaa_bbb',
        'members': ['aaa', 'bbb'],
        'createdAt': Timestamp.fromDate(t0),
        'closedAt': Timestamp.fromDate(t1),
      });
      expect(decoded.closedAt, t1);
      expect(decoded.isClosed, isTrue);
    });

    test('doc sin la clave (legacy) → closedAt null e isClosed false', () {
      final decoded = Chat.fromJson(<String, Object?>{
        'chatId': 'aaa_bbb',
        'members': ['aaa', 'bbb'],
        'createdAt': Timestamp.fromDate(t0),
      });
      expect(decoded.closedAt, isNull);
      expect(decoded.isClosed, isFalse);
    });

    test('closedAt: null explícito también es abierto', () {
      final decoded = Chat.fromJson(<String, Object?>{
        'chatId': 'aaa_bbb',
        'members': ['aaa', 'bbb'],
        'createdAt': Timestamp.fromDate(t0),
        'closedAt': null,
      });
      expect(decoded.isClosed, isFalse);
    });

    test('round-trip por JSON conserva closedAt', () {
      final chat = Chat(
        chatId: 'aaa_bbb',
        members: const ['aaa', 'bbb'],
        createdAt: t0,
        closedAt: t1,
      );
      final decoded = Chat.fromJson(chat.toJson());
      expect(decoded.closedAt, t1);
      expect(decoded.isClosed, isTrue);
      expect(decoded, equals(chat));
    });

    test('copyWith(closedAt: null) reabre el chat (re-vínculo)', () {
      final closed = Chat(
        chatId: 'aaa_bbb',
        members: const ['aaa', 'bbb'],
        createdAt: t0,
        closedAt: t1,
      );
      expect(closed.copyWith(closedAt: null).isClosed, isFalse);
    });
  });
}
