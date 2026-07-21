import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/pagos_web_screen.dart';
import 'package:treino/features/payments/application/pagos_por_cobrar_provider.dart'
    show pagosPorCobrarProvider;
import 'package:treino/features/payments/application/payment_providers.dart'
    show trainerPaymentsProvider;
import 'package:treino/l10n/app_l10n.dart';

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
    ];

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
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

    // (d) 4 tabs rendered
    testWidgets('SCENARIO — 4 tab labels rendered (REQ-PAGW-TAB-002)',
        (tester) async {
      tester.view.physicalSize = _kDesktopSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _wrap(const PagosScreen(), overrides: _emptyOverrides()),
      );
      await tester.pumpAndSettle();

      // Tab labels include counts (e.g. "Vencidos · 0"); look for the prefix.
      expect(find.textContaining('Vencidos'), findsOneWidget);
      expect(find.textContaining('Por vencer'), findsOneWidget);
      expect(find.textContaining('Pagados'), findsOneWidget);
      expect(find.textContaining('Todos'), findsOneWidget);
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
}
