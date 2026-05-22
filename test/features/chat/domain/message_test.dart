import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/chat/domain/message.dart';

void main() {
  group('Message JSON round-trip', () {
    test('full record', () {
      final msg = Message(
        id: 'msg-001',
        senderId: 'aaa',
        text: 'arranca a las 18',
        createdAt: DateTime.utc(2026, 5, 21, 11, 30),
      );
      final decoded = Message.fromJson(msg.toJson());
      expect(decoded, equals(msg));
    });

    test('fromJson with Firestore Timestamp deserializes correctly', () {
      final rawMap = <String, dynamic>{
        'id': 'msg-002',
        'senderId': 'bbb',
        'text': 'dale, ahí voy',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 5, 21, 11, 35)),
      };
      final decoded = Message.fromJson(rawMap);
      expect(decoded.id, 'msg-002');
      expect(decoded.senderId, 'bbb');
      expect(decoded.text, 'dale, ahí voy');
      expect(decoded.createdAt, DateTime.utc(2026, 5, 21, 11, 35));
    });

    test('equality holds for identical records', () {
      final a = Message(
        id: 'msg-001',
        senderId: 'aaa',
        text: 'hola',
        createdAt: DateTime.utc(2026, 5, 21, 11, 30),
      );
      final b = Message(
        id: 'msg-001',
        senderId: 'aaa',
        text: 'hola',
        createdAt: DateTime.utc(2026, 5, 21, 11, 30),
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });
}
