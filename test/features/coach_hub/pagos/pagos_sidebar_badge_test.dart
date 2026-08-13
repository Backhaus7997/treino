import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/persistence/shared_prefs_provider.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_sidebar.dart';
import 'package:treino/features/payments/application/payment_providers.dart'
    show trainerPaymentsProvider;
import 'package:treino/features/payments/domain/payment.dart';

/// Cablea el badge numérico del item «Pagos» del sidebar al conteo real de
/// vencidos (patrón Solicitudes, ADR-F4-04 / Fase 9 WU-08).
///
/// A diferencia de `coach_hub_sidebar_test.dart` (que fuerza un
/// `badgeProvider` fake vía `itemsOverride`), este test monta el
/// `sidebarRegistry` REAL para validar el wiring end-to-end:
/// `trainerPaymentsProvider` → `pagosBucketsProvider` →
/// `pagosBadgeCountProvider` → `pagosSidebarItems`.
void main() {
  final now = DateTime.now().toUtc();
  final periodStart = DateTime.utc(now.year, now.month, 1);

  Payment vencido(String id) => Payment(
        id: id,
        trainerId: 'trainer-1',
        athleteId: 'athlete-1',
        amountArs: 1000,
        concept: 'Test $id',
        status: PaymentStatus.pending,
        createdAt: periodStart.subtract(const Duration(days: 5)),
      );

  Future<void> pumpSidebar(
    WidgetTester tester, {
    required List<Override> overrides,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();

    final router = GoRouter(
      initialLocation: '/pagos',
      routes: [
        ShellRoute(
          builder: (ctx, state, child) => Scaffold(
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [const CoachHubSidebar(), Expanded(child: child)],
            ),
          ),
          routes: [
            GoRoute(path: '/pagos', builder: (_, __) => const Text('pagos')),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => Future.value(sp)),
          ...overrides,
        ],
        child: MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
      'sidebarRegistry real: el item Pagos muestra badge con el conteo de '
      'vencidos (WU-08)', (tester) async {
    await pumpSidebar(
      tester,
      overrides: [
        trainerPaymentsProvider.overrideWith(
          (ref) => Stream.value([vencido('v1'), vencido('v2')]),
        ),
      ],
    );

    expect(find.text('Pagos'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets(
      'sidebarRegistry real: sin vencidos, el item Pagos no muestra badge '
      '(el kit no renderiza con count == 0)', (tester) async {
    await pumpSidebar(
      tester,
      overrides: [
        trainerPaymentsProvider.overrideWith(
          (ref) => Stream.value(<Payment>[]),
        ),
      ],
    );

    expect(find.text('Pagos'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });
}
