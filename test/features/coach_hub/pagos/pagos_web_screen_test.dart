import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart'
    show trainerLinksStreamProvider;
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/pagos_web_screen.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart'
    show TreinoFilterChips;
import 'package:treino/features/payments/application/pagos_por_cobrar_provider.dart'
    show pagosPorCobrarProvider;
import 'package:treino/features/payments/application/payment_providers.dart'
    show paymentRepositoryProvider, trainerPaymentsProvider;
import 'package:treino/features/payments/data/payment_repository.dart';
import 'package:treino/features/payments/domain/payment.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart'
    show userPublicProfilesBatchProvider;
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class _MockPaymentRepo extends Mock implements PaymentRepository {}

// ── Setup ─────────────────────────────────────────────────────────────────────

const _kDesktopSize = Size(1440, 900);

Widget _wrap(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        // Wrap in Scaffold as the shell would — screen itself adds none
        home: Scaffold(body: child),
      ),
    );

List<Override> _emptyOverrides() => [
      trainerPaymentsProvider.overrideWith((ref) => Stream.value(const [])),
      pagosPorCobrarProvider.overrideWith((ref) => const AsyncValue.data([])),
      // Sin roster override, trainerLinksStreamProvider real cuelga en
      // `loading` (currentUidProvider null en test env → Stream.empty(),
      // que nunca emite) — el picker de alumno (ADR-F9-06) quedaría en su
      // skeleton shimmer para siempre y pumpAndSettle() nunca asienta.
      trainerLinksStreamProvider.overrideWith((ref) => Stream.value(const [])),
    ];

// Buckets: `_periodStart` = primer día del mes actual (UTC). Un `createdAt`
// anterior cae en Vencidos; en o después, en PorVencer (mismo criterio que
// pagosBucketsProvider — ver pagos_buckets_provider_test.dart).
final _now = DateTime.now().toUtc();
final _periodStart = DateTime.utc(_now.year, _now.month, 1);

Payment _payment({
  required String id,
  required String concept,
  required PaymentStatus status,
  required DateTime createdAt,
}) =>
    Payment(
      id: id,
      trainerId: 'trainer-1',
      athleteId: 'athlete-1',
      amountArs: 1000,
      concept: concept,
      status: status,
      createdAt: createdAt,
      paidAt: status == PaymentStatus.paid ? createdAt : null,
    );

List<Override> _mixedBucketsOverrides() {
  final vencido = _payment(
    id: 'v1',
    concept: 'Cuota vencida', // i18n
    status: PaymentStatus.pending,
    createdAt: _periodStart.subtract(const Duration(days: 5)),
  );
  final porVencer = _payment(
    id: 'pv1',
    concept: 'Cuota por vencer', // i18n
    status: PaymentStatus.pending,
    createdAt: _periodStart,
  );
  final pagado = _payment(
    id: 'p1',
    concept: 'Cuota pagada', // i18n
    status: PaymentStatus.paid,
    createdAt: _periodStart,
  );
  return [
    trainerPaymentsProvider
        .overrideWith((ref) => Stream.value([vencido, porVencer, pagado])),
    pagosPorCobrarProvider.overrideWith((ref) => const AsyncValue.data([])),
  ];
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
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

  // Desktop viewport for all tests
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('PagosScreen smoke (REQ-PAGW-SHELL-001/002, TAB-002, EMPTY-001)', () {
    // (a) Header, subtitle and CTA action present
    testWidgets(
        'SCENARIO 1 — section header "PAGOS", subtítulo y CTA "Registrar '
        'pago" presentes', (tester) async {
      tester.view.physicalSize = _kDesktopSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _wrap(const PagosScreen(), overrides: _emptyOverrides()),
      );
      await tester.pumpAndSettle();

      expect(find.text('PAGOS'), findsOneWidget); // i18n header
      expect(
        find.textContaining('Cobros, vencimientos'), // i18n
        findsOneWidget,
      );
      expect(find.text('Registrar pago'), findsOneWidget); // i18n CTA
      expect(find.byKey(const Key('pagos_registrar_pago_cta')), findsOneWidget);
    });

    // (b) Tap CTA "Registrar pago" → AlertDialog opens
    testWidgets(
        'SCENARIO 2 — tap CTA "Registrar pago" opens AlertDialog '
        '(REQ-PAGW-SHELL-002)', (tester) async {
      tester.view.physicalSize = _kDesktopSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _wrap(const PagosScreen(), overrides: _emptyOverrides()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('pagos_registrar_pago_cta')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
    });

    // (c) No Scaffold or SafeArea inside PagosScreen (REQ-PAGW-SHELL-001)
    testWidgets(
        'SCENARIO — no extra Scaffold or SafeArea inside PagosScreen '
        '(REQ-PAGW-SHELL-001)', (tester) async {
      tester.view.physicalSize = _kDesktopSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _wrap(const PagosScreen(), overrides: _emptyOverrides()),
      );
      await tester.pumpAndSettle();

      // The outer Scaffold is from _wrap — expect exactly 1.
      expect(find.byType(Scaffold), findsOneWidget);
      // No SafeArea inside PagosScreen.
      expect(find.byType(SafeArea), findsNothing);
    });

    // (d) TreinoFilterChips with the 4 filter labels, no Material TabBar
    testWidgets(
        'SCENARIO — TreinoFilterChips con los 4 filtros, sin TabBar '
        '(REQ-PAGW-TAB-002)', (tester) async {
      tester.view.physicalSize = _kDesktopSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _wrap(const PagosScreen(), overrides: _emptyOverrides()),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TreinoFilterChips), findsOneWidget);
      expect(find.byType(TabBar), findsNothing);

      expect(find.textContaining('Vencidos'), findsOneWidget);
      expect(find.textContaining('Por vencer'), findsOneWidget);
      expect(find.textContaining('Pagados'), findsOneWidget);
      expect(find.textContaining('Todos'), findsOneWidget);
    });

    // (d2) Tapping a chip switches the bucket shown in the table
    testWidgets(
        'SCENARIO — tocar un chip cambia el bucket mostrado en la tabla',
        (tester) async {
      tester.view.physicalSize = _kDesktopSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _wrap(const PagosScreen(), overrides: _mixedBucketsOverrides()),
      );
      await tester.pumpAndSettle();

      // Default filter is Vencidos.
      expect(find.text('Cuota vencida'), findsOneWidget);
      expect(find.text('Cuota por vencer'), findsNothing);
      expect(find.text('Cuota pagada'), findsNothing);

      await tester.tap(find.text('Por vencer'));
      await tester.pumpAndSettle();

      expect(find.text('Cuota vencida'), findsNothing);
      expect(find.text('Cuota por vencer'), findsOneWidget);
      expect(find.text('Cuota pagada'), findsNothing);

      await tester.tap(find.text('Pagados'));
      await tester.pumpAndSettle();

      expect(find.text('Cuota vencida'), findsNothing);
      expect(find.text('Cuota por vencer'), findsNothing);
      expect(find.text('Cuota pagada'), findsOneWidget);
    });

    // (e) Empty state per tab
    testWidgets(
        'SCENARIO — empty state text in default tab (REQ-PAGW-EMPTY-001)',
        (tester) async {
      tester.view.physicalSize = _kDesktopSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _wrap(const PagosScreen(), overrides: _emptyOverrides()),
      );
      await tester.pumpAndSettle();

      // Default tab is Vencidos (index 0) — it should show empty state.
      expect(
        find.text('No hay pagos vencidos'), // i18n
        findsOneWidget,
      );
    });

    // KPI row is present
    testWidgets('KPI row rendered with 3 tiles', (tester) async {
      tester.view.physicalSize = _kDesktopSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _wrap(const PagosScreen(), overrides: _emptyOverrides()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ingreso del mes'), findsOneWidget); // i18n
      expect(find.text('Pendiente cobrar'), findsOneWidget); // i18n
      expect(find.text('Vencido'), findsOneWidget); // i18n
    });
  });

  group('CTA "Registrar pago" persiste de verdad (REQ-PAGW-ACTION-003, '
      'ADR-F9-06 — remediación CRITICAL-1 verify ronda 1)', () {
    // Antes de esta pieza, `_onRegistrarPago` abría RegistrarPagoDialog y
    // descartaba el resultado: el trainer completaba el form, tocaba
    // "Registrar" y NO se persistía nada. Este test falla contra la
    // implementación vieja (repo.add nunca se llamaba) y pasa contra la
    // nueva (picker de alumno → registrarPago → repo.add real).
    testWidgets(
        'SCENARIO — CTA → elegir alumno → completar monto/concepto → '
        'repo.add llamado con el Payment correcto', (tester) async {
      tester.view.physicalSize = _kDesktopSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockRepo = _MockPaymentRepo();
      when(() => mockRepo.add(any())).thenAnswer((_) async {});

      final link = TrainerLink(
        id: 'l1',
        trainerId: 'trainer-1',
        athleteId: 'athlete-1',
        status: TrainerLinkStatus.active,
        requestedAt: DateTime.utc(2026, 1, 1),
      );

      await tester.pumpWidget(_wrap(
        const PagosScreen(),
        overrides: [
          ..._emptyOverrides(),
          paymentRepositoryProvider.overrideWithValue(mockRepo),
          currentUidProvider.overrideWithValue('trainer-1'),
          trainerLinksStreamProvider.overrideWith((ref) => Stream.value([link])),
          userPublicProfilesBatchProvider.overrideWith(
            (ref, key) async => {
              'athlete-1': const UserPublicProfile(
                uid: 'athlete-1',
                displayName: 'Juana Pérez',
              ),
            },
          ),
        ],
      ));
      await tester.pumpAndSettle();

      // Tap CTA → picker de alumno (no RegistrarPagoDialog directo).
      await tester.tap(find.byKey(const Key('pagos_registrar_pago_cta')));
      await tester.pumpAndSettle();
      expect(find.text('Elegí un alumno'), findsOneWidget); // i18n

      // Elegir el único alumno del roster.
      await tester.tap(find.text('Juana Pérez'));
      await tester.pumpAndSettle();

      // Ahora sí RegistrarPagoDialog.
      expect(find.text('Registrar pago'), findsWidgets);

      await tester.enterText(find.byType(TextField).first, '5000');
      await tester.enterText(find.byType(TextField).last, 'Clase suelta');
      await tester.tap(find.text('Registrar')); // i18n
      await tester.pumpAndSettle();

      final captured =
          verify(() => mockRepo.add(captureAny())).captured.single as Payment;
      expect(captured.athleteId, 'athlete-1');
      expect(captured.amountArs, 5000);
      expect(captured.concept, 'Clase suelta');
      expect(captured.status, PaymentStatus.paid);
    });
  });
}
