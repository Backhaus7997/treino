/// Tests for PagosWebTable — Fase 9 WU-06 (Strict TDD RED phase).
///
/// Migración de la tabla plana (Container ad-hoc) a `CoachHubDataTable` del
/// kit v2, con celdas ricas (avatar de iniciales + badge de estado por
/// color) y estados completos resueltos por el kit (loading shimmer /
/// error+retry / empty). Las acciones de fila se difieren a WU-07 — sin
/// columna ACCIONES en este archivo.
///
/// REQ-PAGW-TABLE-001, REQ-PAGW-EMPTY-001.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/pagos_web_table.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart'
    show CoachHubDataTable;
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

/// Pago pendiente vencido hace exactamente [diasAtraso] días de calendario
/// (dueAt-aware — REQ-VENC-11), para verificar el label relativo del badge.
Payment _vencidoHaceDias(int diasAtraso, {String id = 'pay-2'}) {
  final now = DateTime.now().toUtc();
  return Payment(
    id: id,
    trainerId: 'trainer-1',
    athleteId: 'uid-bob',
    amountArs: 8000,
    concept: 'Plan semanal',
    status: PaymentStatus.pending,
    createdAt: now.subtract(Duration(days: diasAtraso + 30)),
    dueAt: now.subtract(Duration(days: diasAtraso)),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

  group('PagosWebTable → CoachHubDataTable (Fase 9 WU-06)', () {
    testWidgets(
        'SCENARIO 1 — renders CoachHubDataTable with alumno name and monto '
        'formatted es-AR', (tester) async {
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
            emptyMessage: 'Sin pagos',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CoachHubDataTable), findsOneWidget);
      expect(find.text('Ana'), findsOneWidget);
      expect(find.text('Plan mensual'), findsOneWidget);
      expect(find.text(r'$15.000'), findsOneWidget);
    });

    testWidgets(
        "SCENARIO 2 — estado badge shows 'Vencido 4d' for a payment overdue "
        '4 days (dueAt-aware, REQ-VENC-11)', (tester) async {
      tester.view.physicalSize = _kDesktopSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final profiles = {
        'uid-bob': const UserPublicProfile(uid: 'uid-bob', displayName: 'Bob'),
      };

      await tester.pumpWidget(
        _wrap(
          PagosWebTable(
            payments: [_vencidoHaceDias(4)],
            profiles: profiles,
            emptyMessage: 'Sin pagos',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Vencido 4d'), findsOneWidget); // i18n
    });

    testWidgets('SCENARIO 3 — empty list shows emptyMessage via kit',
        (tester) async {
      tester.view.physicalSize = _kDesktopSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _wrap(
          const PagosWebTable(
            payments: [],
            profiles: {},
            emptyMessage: 'No hay pagos vencidos',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No hay pagos vencidos'), findsOneWidget);
    });

    testWidgets('SCENARIO 4 — loading:true shows the kit skeleton shimmer',
        (tester) async {
      tester.view.physicalSize = _kDesktopSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _wrap(
          const PagosWebTable(
            payments: [],
            profiles: {},
            emptyMessage: 'Sin pagos',
            loading: true,
          ),
        ),
      );
      // No pumpAndSettle — shimmer runs an animation loop.
      await tester.pump();

      expect(find.byKey(const Key('data_table_skeleton')), findsOneWidget);
    });

    testWidgets(
        'SCENARIO 5 — column headers ALUMNO / CONCEPTO / MONTO / '
        'VENCIMIENTO / ESTADO visible, no PLAN column (ADR-F9-02)',
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
            emptyMessage: 'Sin pagos',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ALUMNO'), findsOneWidget); // i18n
      expect(find.text('CONCEPTO'), findsOneWidget); // i18n
      expect(find.text('MONTO'), findsOneWidget); // i18n
      expect(find.text('VENCIMIENTO'), findsOneWidget); // i18n
      expect(find.text('ESTADO'), findsOneWidget); // i18n
      expect(find.text('PLAN'), findsNothing);
    });

    testWidgets('SCENARIO 6 — missing profile falls back to "Alumno" label',
        (tester) async {
      tester.view.physicalSize = _kDesktopSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _wrap(
          PagosWebTable(
            payments: [_paid(athleteId: 'uid-unknown')],
            profiles: const {}, // no profile for uid-unknown
            emptyMessage: 'Sin pagos',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alumno'), findsOneWidget); // i18n fallback
    });

    testWidgets(
        'SCENARIO 7 — errorMessage + onRetry renders the kit error state',
        (tester) async {
      tester.view.physicalSize = _kDesktopSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      var retried = false;

      await tester.pumpWidget(
        _wrap(
          PagosWebTable(
            payments: const [],
            profiles: const {},
            emptyMessage: 'Sin pagos',
            errorMessage: 'Error al cargar pagos.',
            onRetry: () => retried = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Error al cargar pagos.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('data_table_retry')));
      expect(retried, isTrue);
    });
  });

  group('PagosWebTable → acciones de fila (Fase 9 WU-07)', () {
    testWidgets(
        'SCENARIO 8 — showActions:true + pago pending muestra Recordar y '
        'Marcar pagado; tocar Marcar pagado invoca el callback',
        (tester) async {
      tester.view.physicalSize = _kDesktopSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final profiles = {
        'uid-bob': const UserPublicProfile(uid: 'uid-bob', displayName: 'Bob'),
      };
      final pending = _vencidoHaceDias(4);
      Payment? marcado;

      await tester.pumpWidget(
        _wrap(
          PagosWebTable(
            payments: [pending],
            profiles: profiles,
            emptyMessage: 'Sin pagos',
            onMarcarPagado: (p) => marcado = p,
            onRecordar: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Recordar'), findsOneWidget); // i18n
      expect(find.text('Marcar pagado'), findsOneWidget); // i18n

      await tester.tap(find.text('Marcar pagado'));
      await tester.pumpAndSettle();

      expect(marcado, pending);
    });

    testWidgets(
        'SCENARIO 9 — showActions:false (tab Pagados) no muestra Recordar '
        'ni Marcar pagado', (tester) async {
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
            emptyMessage: 'Sin pagos',
            showActions: false,
            onMarcarPagado: (_) {},
            onRecordar: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Recordar'), findsNothing);
      expect(find.text('Marcar pagado'), findsNothing);
      expect(find.text('ACCIONES'), findsNothing); // i18n — no column either
    });

    testWidgets(
        'SCENARIO 10 — pago ya pagado con showActions:true muestra Recordar '
        'pero NO Marcar pagado', (tester) async {
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
            emptyMessage: 'Sin pagos',
            onMarcarPagado: (_) {},
            onRecordar: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Recordar'), findsOneWidget); // i18n
      expect(find.text('Marcar pagado'), findsNothing);
    });
  });
}
