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

// ── registrarPago (third-caller coverage gap) ──────────────────────────────
//
// This is the coverage gap that let the bug ship: `registrarPago` is opened
// from alumno_detail_screen.dart's two call sites but had no test driving it
// through the widened RegistrarPagoDialog (athleteId + Estado). These tests
// pump a trigger that invokes `registrarPago(context, ref, 'a1')` directly.

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
    registerFallbackValue(
      Payment(
        id: '',
        trainerId: 'trainer-1',
        athleteId: 'a1',
        amountArs: 1000,
        concept: 'fallback',
        status: PaymentStatus.paid,
        createdAt: DateTime.utc(2026, 1, 1),
      ),
    );
  });

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    mockRepo = _MockPaymentRepo();
    when(() => mockRepo.markManyPaid(any(), any())).thenAnswer((_) async {});
    when(() => mockRepo.add(any())).thenAnswer((_) async {});
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

  group('registrarPago (third-caller coverage gap)', () {
    Widget wrapRegistrar(_MockPaymentRepo mockRepo,
            {String athleteId = 'a1'}) =>
        ProviderScope(
          overrides: [
            paymentRepositoryProvider.overrideWithValue(mockRepo),
            currentUidProvider.overrideWithValue('trainer-1'),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  key: const Key('trigger'),
                  onPressed: () => registrarPago(context, ref, athleteId),
                  child: const Text('Trigger'),
                ),
              ),
            ),
          ),
        );

    // (a) Estado=Cobrado → repo.add called with a paid Payment scoped to the
    // passed athleteId — the dialog's dropdown must be hidden (no dropdown
    // interaction needed), proving the athlete can't be swapped by mistake.
    testWidgets(
        'SCENARIO — Estado=Cobrado + amount + concept → repo.add called with '
        'Payment(athleteId: "a1", status: paid, paidAt != null)',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(wrapRegistrar(mockRepo, athleteId: 'a1'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();

      // Dropdown must be hidden — athleteId was passed positionally.
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);

      await tester.enterText(
          find.widgetWithText(TextField, 'Monto (ARS)'), '2500');
      await tester.enterText(
          find.widgetWithText(TextField, 'Concepto'), 'Clase suelta');

      await tester.tap(find.text('Registrar')); // i18n
      await tester.pumpAndSettle();

      final captured =
          verify(() => mockRepo.add(captureAny())).captured.single as Payment;
      expect(captured.athleteId, 'a1');
      expect(captured.trainerId, 'trainer-1');
      expect(captured.amountArs, 2500);
      expect(captured.concept, 'Clase suelta');
      expect(captured.status, PaymentStatus.paid);
      expect(captured.paidAt, isNotNull);
      expect(captured.dueAt, isNull);
      expect(find.text('Pago registrado.'), findsOneWidget); // i18n
    });

    // (b) Estado=Pendiente + due date → repo.add called with a pending
    // Payment (dueAt set, paidAt null) — the branch that the broken caller
    // couldn't reach at all (its old showDialog<({int, String})> type
    // couldn't even carry a status).
    testWidgets(
        'SCENARIO — Estado=Pendiente + due date → repo.add called with '
        'Payment(status: pending, dueAt != null, paidAt: null)',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(wrapRegistrar(mockRepo, athleteId: 'a1'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'Monto (ARS)'), '3000');
      await tester.enterText(
          find.widgetWithText(TextField, 'Concepto'), 'Cuota mensual');

      await tester.tap(find.text('Pendiente')); // i18n
      await tester.pumpAndSettle();
      await tester.tap(find.text('Elegí una fecha')); // i18n
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Registrar')); // i18n
      await tester.pumpAndSettle();

      final captured =
          verify(() => mockRepo.add(captureAny())).captured.single as Payment;
      expect(captured.athleteId, 'a1');
      expect(captured.status, PaymentStatus.pending);
      expect(captured.dueAt, isNotNull);
      expect(captured.paidAt, isNull);
      expect(find.text('Pago registrado.'), findsOneWidget); // i18n
    });

    // (c) Cancel → repo NOT called.
    testWidgets('SCENARIO — cancel dialog → repo.add NOT called',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(wrapRegistrar(mockRepo, athleteId: 'a1'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancelar')); // i18n
      await tester.pumpAndSettle();

      verifyNever(() => mockRepo.add(any()));
    });
  });
}
