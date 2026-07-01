/// Tests for marcarPagadoDoc action — PR2b (Strict TDD RED phase).
///
/// REQ-PAGW-ACTION-001: Marcar pagado via AlertDialog, repo.markManyPaid called.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/marcar_pagado_actions.dart';
import 'package:treino/features/payments/application/payment_providers.dart'
    show paymentRepositoryProvider;
import 'package:treino/features/payments/data/payment_repository.dart';
import 'package:treino/features/payments/domain/payment.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class _MockPaymentRepo extends Mock implements PaymentRepository {}

// ── Helpers ───────────────────────────────────────────────────────────────────

Payment _payment({String id = 'pay-1', bool vencido = false}) {
  final now = DateTime.now().toUtc();
  final createdAt = vencido
      ? DateTime.utc(now.year, now.month, 1).subtract(const Duration(days: 5))
      : DateTime.utc(now.year, now.month, 1);
  return Payment(
    id: id,
    trainerId: 'trainer-1',
    athleteId: 'athlete-1',
    amountArs: 12000,
    concept: 'Plan mensual',
    status: PaymentStatus.pending,
    createdAt: createdAt,
  );
}

Widget _wrapAction(
  _MockPaymentRepo mockRepo,
  Payment payment, {
  List<Override> overrides = const [],
}) =>
    ProviderScope(
      overrides: [
        paymentRepositoryProvider.overrideWithValue(mockRepo),
        currentUidProvider.overrideWithValue('trainer-1'),
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              key: const Key('trigger'),
              onPressed: () => marcarPagadoDoc(context, ref, payment),
              child: const Text('Trigger'),
            ),
          ),
        ),
      ),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late _MockPaymentRepo mockRepo;

  setUpAll(() {
    registerFallbackValue(DateTime.now());
  });

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    mockRepo = _MockPaymentRepo();
    when(() => mockRepo.markManyPaid(any(), any())).thenAnswer((_) async {});
  });

  group('marcarPagadoDoc (REQ-PAGW-ACTION-001)', () {
    // (a) Por vencer row — confirm → markManyPaid called with payment id
    testWidgets(
        'SCENARIO 1 — tap Marcar pagado + confirm → markManyPaid called '
        'with payment id', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final payment = _payment(id: 'pay-por-vencer');
      await tester.pumpWidget(_wrapAction(mockRepo, payment));
      await tester.pumpAndSettle();

      // Tap the trigger button
      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();

      // AlertDialog should appear
      expect(find.byType(AlertDialog), findsOneWidget);

      // Tap the confirm button (Cobrado)
      await tester.tap(find.text('Cobrado'));
      await tester.pumpAndSettle();

      // repo.markManyPaid must have been called with the payment id
      verify(
        () => mockRepo.markManyPaid(
          ['pay-por-vencer'],
          any(),
        ),
      ).called(1);
    });

    // (b) Vencidos row — confirm → markManyPaid called
    testWidgets(
        'SCENARIO 2 — vencido row: confirm → markManyPaid called '
        '(REQ-PAGW-ACTION-001)', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final payment = _payment(id: 'pay-vencido', vencido: true);
      await tester.pumpWidget(_wrapAction(mockRepo, payment));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text('Cobrado'));
      await tester.pumpAndSettle();

      verify(
        () => mockRepo.markManyPaid(['pay-vencido'], any()),
      ).called(1);
    });

    // (c) Cancel → repo NOT called
    testWidgets(
        'SCENARIO 3 — cancel dialog → repo NOT called, row remains '
        '(REQ-PAGW-ACTION-001)', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final payment = _payment(id: 'pay-cancel');
      await tester.pumpWidget(_wrapAction(mockRepo, payment));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      verifyNever(() => mockRepo.markManyPaid(any(), any()));
    });
  });
}
