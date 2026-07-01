/// Tests for RegistrarPagoDialog — PR2b (Strict TDD RED phase).
///
/// REQ-PAGW-REGISTRAR-001: dialog collects amount + concept, calls repo.add on
/// confirm; no call on cancel; validation shows error for empty fields.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/registrar_pago_dialog.dart';
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

Widget _wrapDialog(
  _MockPaymentRepo mockRepo, {
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
        home: const Scaffold(
          body: Center(child: RegistrarPagoDialog()),
        ),
      ),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late _MockPaymentRepo mockRepo;

  setUpAll(() {
    registerFallbackValue(
      Payment(
        id: '',
        trainerId: 'trainer-1',
        athleteId: 'athlete-1',
        amountArs: 1000,
        concept: 'test',
        status: PaymentStatus.paid,
        createdAt: DateTime.utc(2026, 1, 1),
        paidAt: DateTime.utc(2026, 1, 1),
      ),
    );
  });

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    mockRepo = _MockPaymentRepo();
    when(() => mockRepo.add(any())).thenAnswer((_) async {});
  });

  group('RegistrarPagoDialog (REQ-PAGW-REGISTRAR-001)', () {
    // (a) Dialog renders correctly
    testWidgets('dialog shows Monto and Concepto fields', (tester) async {
      await tester.pumpWidget(_wrapDialog(mockRepo));
      await tester.pumpAndSettle();

      expect(find.text('Registrar pago'), findsOneWidget); // i18n title
      expect(
          find.widgetWithText(TextField, 'Monto (ARS)').evaluate().isNotEmpty ||
              find.byType(TextField).evaluate().length >= 2,
          isTrue);
    });

    // (b) Cancel → repo NOT called
    testWidgets('SCENARIO 2 — cancel → repo.add NOT called', (tester) async {
      await tester.pumpWidget(_wrapDialog(mockRepo));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancelar')); // i18n
      await tester.pumpAndSettle();

      verifyNever(() => mockRepo.add(any()));
    });

    // (c) Empty fields → validation error, repo not called
    testWidgets('SCENARIO 3 — empty fields → validation error, no repo call',
        (tester) async {
      await tester.pumpWidget(_wrapDialog(mockRepo));
      await tester.pumpAndSettle();

      // Tap Registrar without entering data
      await tester.tap(find.text('Registrar')); // i18n
      await tester.pumpAndSettle();

      // Should show a validation error
      expect(
        find.text('Ingresá un monto válido.').evaluate().isNotEmpty || // i18n
            find
                .text('Completá todos los campos.')
                .evaluate()
                .isNotEmpty, // i18n
        isTrue,
      );
      verifyNever(() => mockRepo.add(any()));
    });
  });
}
