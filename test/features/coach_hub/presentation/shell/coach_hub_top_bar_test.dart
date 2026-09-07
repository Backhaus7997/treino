// Tests for CoachHubTopBar (REQ-SH-007, SCENARIO-760).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_top_bar.dart';

Future<void> _pumpTopBar(
  WidgetTester tester, {
  String initial = '/dashboard',
  ThemeData? theme,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: '/dashboard',
        builder: (_, __) => const Scaffold(body: CoachHubTopBar()),
      ),
      GoRoute(
        path: '/alumnos',
        builder: (_, __) => const Scaffold(body: CoachHubTopBar()),
      ),
      GoRoute(
        path: '/ajustes',
        builder: (_, __) => const Scaffold(body: CoachHubTopBar()),
      ),
    ],
  );

  await tester.pumpWidget(
    MaterialApp.router(
      theme: theme ?? AppTheme.dark(),
      routerConfig: router,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('CoachHubTopBar (REQ-SH-007)', () {
    testWidgets(
        'la cuenta ya no se duplica en el top bar: no hay avatar ni menu',
        (tester) async {
      await _pumpTopBar(tester);

      expect(find.byType(PopupMenuButton<String>), findsNothing);
      expect(find.byIcon(TreinoIcon.chevronDown), findsNothing);
      expect(find.byType(CircleAvatar), findsNothing);
    });

    testWidgets('campana presente a la derecha (inerte)', (tester) async {
      await _pumpTopBar(tester);
      expect(find.byTooltip('Notificaciones'), findsOneWidget);
    });

    testWidgets(
        'título de sección Barlow Condensed 700 UPPERCASE en /dashboard',
        (tester) async {
      await _pumpTopBar(tester);
      expect(find.text('DASHBOARD'), findsOneWidget);
    });

    testWidgets('título de sección cambia con la ruta activa (/alumnos)',
        (tester) async {
      await _pumpTopBar(tester, initial: '/alumnos');
      expect(find.text('ALUMNOS'), findsOneWidget);
    });

    testWidgets('la ruta de cuenta conserva un título sin sumar otro acceso',
        (tester) async {
      await _pumpTopBar(tester, initial: '/ajustes');
      expect(find.text('MI CUENTA'), findsOneWidget);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
    });

    testWidgets('campo de búsqueda decorativo presente', (tester) async {
      await _pumpTopBar(tester);
      expect(find.text('Buscar alumnos, rutinas, plan...'), findsOneWidget);
      expect(find.byIcon(TreinoIcon.search), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    });

    testWidgets('smoke visual en tema claro (mintMagentaLight)',
        (tester) async {
      await _pumpTopBar(tester, theme: AppTheme.light());
      expect(find.text('DASHBOARD'), findsOneWidget);
      expect(find.byType(CircleAvatar), findsNothing);
    });
  });
}
