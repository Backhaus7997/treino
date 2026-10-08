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

    // Este test pedía lo CONTRARIO: que el campo estuviera presente. Fijaba un
    // control `enabled: false` que se veía operable y no hacía nada — el PF lo
    // tipeaba y no pasaba nada. Ahora es el candado: la barra no vuelve a
    // ofrecer una búsqueda que no busca.
    testWidgets('la barra NO ofrece un buscador muerto', (tester) async {
      await _pumpTopBar(tester);
      expect(find.byType(TextField), findsNothing);
      expect(find.byIcon(TreinoIcon.search), findsNothing);
      expect(find.text('Buscar alumnos, rutinas, plan...'), findsNothing);
    });

    testWidgets('y la campana sigue pegada a la derecha', (tester) async {
      await _pumpTopBar(tester);
      final barra = tester.getRect(find.byType(CoachHubTopBar));
      final campana = tester.getRect(find.byIcon(TreinoIcon.bell));
      expect(
        barra.right - campana.right,
        lessThan(48),
        reason: 'sin el buscador en el centro, el `Expanded` del título es lo '
            'único que empuja la campana al borde. Con `Flexible` + `Spacer` '
            'se reparten el sobrante y queda a media barra (461 px medidos)',
      );
    });

    testWidgets('smoke visual en tema claro (mintMagentaLight)',
        (tester) async {
      await _pumpTopBar(tester, theme: AppTheme.light());
      expect(find.text('DASHBOARD'), findsOneWidget);
      expect(find.byType(CircleAvatar), findsNothing);
    });
  });
}
