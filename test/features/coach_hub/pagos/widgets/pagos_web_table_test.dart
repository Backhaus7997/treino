/// Tests for PagosWebTable — PR2b (Strict TDD RED phase).
///
/// REQ-PAGW-TABLE-001, REQ-PAGW-EMPTY-001.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/pagos_web_table.dart';
import 'package:treino/features/payments/domain/payment.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/l10n/app_l10n.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

const _kDesktopSize = Size(1440, 900);

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

Payment _paid({
  String id = 'pay-1',
  String athleteId = 'uid-ana',
  int amountArs = 15000,
  String concept = 'Plan mensual',
}) =>
    Payment(
      id: id,
      trainerId: 'trainer-1',
      athleteId: athleteId,
      amountArs: amountArs,
      concept: concept,
      status: PaymentStatus.paid,
      createdAt: DateTime(2025, 6, 15),
      paidAt: DateTime(2025, 6, 15),
    );

Payment _pending({
  String id = 'pay-2',
  String athleteId = 'uid-bob',
  int amountArs = 8000,
  String concept = 'Plan semanal',
  bool vencido = false,
}) {
  final now = DateTime.now().toUtc();
  final createdAt = vencido
      ? DateTime.utc(now.year, now.month, 1).subtract(const Duration(days: 5))
      : DateTime.utc(now.year, now.month, 1);
  return Payment(
    id: id,
    trainerId: 'trainer-1',
    athleteId: athleteId,
    amountArs: amountArs,
    concept: concept,
    status: PaymentStatus.pending,
    createdAt: createdAt,
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

  group('PagosWebTable (REQ-PAGW-TABLE-001)', () {
    // (a) Paid payment row — 6 columns visible with correct data
    testWidgets(
        'SCENARIO 1 — paid row shows Alumno name, Concepto, Monto, Estado=Pagado',
        (tester) async {
      tester.view.physicalSize = _kDesktopSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final profiles = {
        'uid-ana': const UserPublicProfile(uid: 'uid-ana', displayName: 'Ana'),
      };

      await tester.pumpWidget(
        _wrap(
          PagosWebTable(
            payments: [_paid()],
            profiles: profiles,
            emptyLabel: 'Sin pagos',
            onMarcarPagado: null,
            onRecordar: null,
            showActions: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Alumno column shows name from profiles map
      expect(find.text('Ana'), findsOneWidget);
      // Concepto column
      expect(find.text('Plan mensual'), findsOneWidget);
      // Monto formatted es-AR
      expect(find.text(r'$15.000'), findsOneWidget);
      // Estado chip = Pagado
      expect(find.text('Pagado'), findsOneWidget);
    });

    // (b) Pending row — Estado is Pendiente or Vencido, never Pagado
    testWidgets(
        'SCENARIO 2 — pending row Estado shows Pendiente/Vencido, not Pagado',
        (tester) async {
      tester.view.physicalSize = _kDesktopSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final profiles = {
        'uid-bob': const UserPublicProfile(uid: 'uid-bob', displayName: 'Bob'),
      };

      await tester.pumpWidget(
        _wrap(
          PagosWebTable(
            payments: [_pending()],
            profiles: profiles,
            emptyLabel: 'Sin pagos',
            onMarcarPagado: null,
            onRecordar: null,
            showActions: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pagado'), findsNothing);
      // Either Pendiente or Vencido must appear
      final pendienteOrVencido = find.text('Pendiente').evaluate().isNotEmpty ||
          find.text('Vencido').evaluate().isNotEmpty;
      expect(pendienteOrVencido, isTrue);
    });

    // (c) Empty bucket → emptyLabel shown, no exception
    testWidgets(
        'SCENARIO — empty bucket renders emptyLabel without crash '
        '(REQ-PAGW-EMPTY-001)', (tester) async {
      tester.view.physicalSize = _kDesktopSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _wrap(
          const PagosWebTable(
            payments: [],
            profiles: {},
            emptyLabel: 'No hay pagos vencidos',
            onMarcarPagado: null,
            onRecordar: null,
            showActions: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No hay pagos vencidos'), findsOneWidget);
    });

    // (d) Column headers rendered when non-empty
    testWidgets('column headers ALUMNO / CONCEPTO / MONTO / ESTADO visible',
        (tester) async {
      tester.view.physicalSize = _kDesktopSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final profiles = {
        'uid-ana': const UserPublicProfile(uid: 'uid-ana', displayName: 'Ana'),
      };

      await tester.pumpWidget(
        _wrap(
          PagosWebTable(
            payments: [_paid()],
            profiles: profiles,
            emptyLabel: 'Sin pagos',
            onMarcarPagado: null,
            onRecordar: null,
            showActions: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ALUMNO'), findsOneWidget); // i18n
      expect(find.text('CONCEPTO'), findsOneWidget); // i18n
      expect(find.text('MONTO'), findsOneWidget); // i18n
      expect(find.text('ESTADO'), findsOneWidget); // i18n
    });

    // (e) Action buttons visible when showActions=true
    testWidgets('showActions=true renders Recordar button for pending row',
        (tester) async {
      tester.view.physicalSize = _kDesktopSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final profiles = {
        'uid-bob': const UserPublicProfile(uid: 'uid-bob', displayName: 'Bob'),
      };

      await tester.pumpWidget(
        _wrap(
          PagosWebTable(
            payments: [_pending()],
            profiles: profiles,
            emptyLabel: 'Sin pagos',
            onMarcarPagado: (_) {},
            onRecordar: (_) {},
            showActions: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Recordar'), findsOneWidget); // i18n
    });

    // (f) Fallback name when profile missing
    testWidgets('missing profile falls back to "Alumno" label', (tester) async {
      tester.view.physicalSize = _kDesktopSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _wrap(
          PagosWebTable(
            payments: [_paid(athleteId: 'uid-unknown')],
            profiles: const {}, // no profile for uid-unknown
            emptyLabel: 'Sin pagos',
            onMarcarPagado: null,
            onRecordar: null,
            showActions: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alumno'), findsOneWidget); // i18n fallback
    });
  });
}
