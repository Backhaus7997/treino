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
}
