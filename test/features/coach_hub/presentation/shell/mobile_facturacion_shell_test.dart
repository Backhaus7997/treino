import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/shell/mobile_facturacion_shell.dart';

/// Monta el `MobileFacturacionShell` dentro de un `ShellRoute` real, con el
/// `child` provisto por la ruta activa — mismo patrón que `_pumpScaffold` en
/// `coach_hub_scaffold_test.dart` y `_pumpSidebar` en
/// `coach_hub_sidebar_test.dart`: el `Navigator` anidado y su `ModalBarrier`
/// opaco son los de producción, no un doble.
Future<void> _pumpShell(WidgetTester tester) async {
  final router = GoRouter(
    initialLocation: '/facturacion/planes',
    routes: [
      ShellRoute(
        builder: (ctx, state, child) => MobileFacturacionShell(child: child),
        routes: [
          GoRoute(
            path: '/facturacion/planes',
            builder: (_, __) => const Text('CONTENT_SLOT'),
          ),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
  );
  await tester.pumpAndSettle();
}

void main() {
  // El guard de producción del bug de semántica del shell de facturación en
  // teléfono: el `Navigator` del `ShellRoute` (el `child`) siembra un
  // `ModalBarrier` con `BlockSemantics` que, sin `NavigatorSemanticsBoundary`,
  // borra la semántica de TODOS sus hermanos anteriores en el `Column` — acá,
  // el encabezado completo (marca "TREINO" + "Cerrar sesión"). Mismo
  // mecanismo que el guard de `coach_hub_scaffold_test.dart` en la rama de
  // escritorio.
  testWidgets(
      'el Navigator de la ruta de pago no borra la semántica del encabezado',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpShell(tester);

    expect(
      find.bySemanticsLabel('TREINO'),
      findsOneWidget,
      reason: 'la marca del encabezado no llega al árbol de semántica',
    );
    expect(
      find.bySemanticsLabel('Cerrar sesión'),
      findsOneWidget,
      reason: 'el botón de cerrar sesión no llega al árbol de semántica',
    );

    handle.dispose();
  });
}
