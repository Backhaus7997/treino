// Tests for CoachHubBreadcrumb (W1.3.2, REQ-CHW-TOPBAR-002, SCENARIO-761).
//
// The breadcrumb derives its trail from GoRouterState.uri against
// sidebarRegistry, so each scenario pumps it inside a GoRouter at the route
// under test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_breadcrumb.dart';

Future<void> _pumpAt(WidgetTester tester, String location) async {
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: location,
        builder: (_, __) => const Scaffold(body: CoachHubBreadcrumb()),
      ),
    ],
  );
  await tester.pumpWidget(
    MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('CoachHubBreadcrumb (REQ-CHW-TOPBAR-002)', () {
    testWidgets('/dashboard → muestra "Dashboard"', (tester) async {
      await _pumpAt(tester, '/dashboard');
      expect(find.text('Dashboard'), findsOneWidget);
    });

    testWidgets('/alumnos → muestra "Alumnos"', (tester) async {
      await _pumpAt(tester, '/alumnos');
      expect(find.text('Alumnos'), findsOneWidget);
    });

    testWidgets(
      'ruta desconocida → fallback elegante (sin crash, sin label) [SCENARIO-761]',
      (tester) async {
        await _pumpAt(tester, '/zzz-no-existe');
        expect(find.byType(CoachHubBreadcrumb), findsOneWidget);
        expect(find.text('Dashboard'), findsNothing);
        expect(find.text('Alumnos'), findsNothing);
      },
    );
  });
}
