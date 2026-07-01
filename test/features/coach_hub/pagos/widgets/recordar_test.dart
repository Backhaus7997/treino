/// Tests del recordatorio de pago — PR2b.
///
/// REQ-PAGW-ACTION-002: mensaje de recordatorio (contenido) + envío por el
/// chat in-app (getOrCreate + sendMessage). El envío por chat reemplazó a
/// WhatsApp — no depende del teléfono del alumno y dispara notifyOnChatMessage.
library;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/chat/data/chat_repository.dart';
import 'package:treino/features/chat/domain/media_type.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/marcar_pagado_actions.dart';
import 'package:treino/features/payments/domain/payment.dart';
import 'package:treino/features/workout/application/session_providers.dart';

/// Fake que deja correr `getOrCreate` contra fake firestore (para resolver el
/// chatId determinístico) pero captura el `sendMessage` para poder asertarlo.
class _CapturingChatRepo extends ChatRepository {
  _CapturingChatRepo() : super(firestore: FakeFirebaseFirestore());

  String? sentChatId;
  String? sentSenderId;
  String? sentText;

  @override
  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    String text = '',
    String? mediaUrl,
    MediaType? mediaType,
  }) async {
    sentChatId = chatId;
    sentSenderId = senderId;
    sentText = text;
  }
}

void main() {
  group('reminderText (REQ-PAGW-ACTION-002)', () {
    test('incluye monto formateado, concepto y alias', () {
      final text = reminderText(
        amount: 12000,
        concept: 'Plan semanal',
        paymentAlias: 'alias.trainer',
      );
      expect(text, contains(r'$12.000'));
      expect(text, contains('Plan semanal'));
      expect(text, contains('alias.trainer'));
    });

    test('alias null → mensaje válido, sin substring "null"', () {
      final text = reminderText(
        amount: 12000,
        concept: 'Plan semanal',
        paymentAlias: null,
      );
      expect(text, isNotEmpty);
      expect(text, isNot(contains('null')));
      expect(text, contains(r'$12.000'));
      expect(text, contains('Plan semanal'));
    });

    test('alias vacío → se omite la cláusula de transferencia', () {
      final text = reminderText(
        amount: 12000,
        concept: 'Plan semanal',
        paymentAlias: '',
      );
      expect(text, isNotEmpty);
      expect(text, isNot(contains('transferir')));
    });

    test('caracteres especiales en el concepto no rompen', () {
      expect(
        () => reminderText(
          amount: 5000,
          concept: 'Plan & más #especial',
          paymentAlias: 'alias.trainer',
        ),
        returnsNormally,
      );
    });
  });

  group('recordar → envía por chat in-app (REQ-PAGW-ACTION-002)', () {
    testWidgets('confirmar en el diálogo envía el recordatorio por el chat',
        (tester) async {
      final repo = _CapturingChatRepo();
      const trainerId = 't1';
      final payment = Payment(
        id: 'p1',
        trainerId: trainerId,
        athleteId: 'a1',
        amountArs: 12000,
        concept: 'Plan semanal',
        status: PaymentStatus.pending,
        createdAt: DateTime.utc(2026, 1, 15),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUidProvider.overrideWithValue(trainerId),
            chatRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () =>
                        recordar(context, ref, payment, 'alias.trainer'),
                    child: const Text('go'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      // El diálogo muestra el mensaje pre-cargado + el botón Enviar.
      expect(find.text('Enviar'), findsOneWidget);
      expect(find.textContaining('Plan semanal'), findsWidgets);

      await tester.tap(find.text('Enviar'));
      await tester.pumpAndSettle();

      // Se envió por el chat, con el sender y el texto correctos.
      expect(repo.sentSenderId, trainerId);
      expect(repo.sentText, contains('Plan semanal'));
      expect(repo.sentText, contains(r'$12.000'));
      // chatId determinístico del par (sorted uids).
      expect(repo.sentChatId, ChatRepository.chatIdFor('t1', 'a1'));
    });

    testWidgets('cancelar el diálogo NO envía nada', (tester) async {
      final repo = _CapturingChatRepo();
      final payment = Payment(
        id: 'p2',
        trainerId: 't1',
        athleteId: 'a1',
        amountArs: 8000,
        concept: 'Plan mensual',
        status: PaymentStatus.pending,
        createdAt: DateTime.utc(2026, 1, 15),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUidProvider.overrideWithValue('t1'),
            chatRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => recordar(context, ref, payment, null),
                    child: const Text('go'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(repo.sentText, isNull);
    });
  });
}
