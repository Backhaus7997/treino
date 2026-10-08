import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_logo.dart';
import 'package:treino/features/coach_hub/presentation/shell/mobile_facturacion_shell.dart';

/// Monta el `MobileFacturacionShell` dentro de un `ShellRoute` real, con el
/// `child` provisto por la ruta activa — mismo patrón que `_pumpScaffold` en
/// `coach_hub_scaffold_test.dart` y `_pumpSidebar` en
/// `coach_hub_sidebar_test.dart`: el `Navigator` anidado y su `ModalBarrier`
/// opaco son los de producción, no un doble.
Future<void> _pumpShell(WidgetTester tester, {ThemeData? theme}) async {
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
    MaterialApp.router(theme: theme ?? AppTheme.dark(), routerConfig: router),
  );
  await tester.pumpAndSettle();
}

void main() {
  // La marca del encabezado es el wordmark oficial (`TreinoLogo`, el mismo del
  // sidebar y del móvil), no la palabra "TREINO" tipeada en Barlow Condensed.
  group('marca del encabezado', () {
    testWidgets('es el TreinoLogo, no el texto suelto «TREINO»',
        (tester) async {
      await _pumpShell(tester);

      expect(find.byType(TreinoLogo), findsOneWidget);
      expect(
        find.text('TREINO'),
        findsNothing,
        reason: 'la marca volvió a escribirse como texto',
      );
    });

    // El shell del teléfono NO es siempre oscuro: el Coach Hub arranca en
    // `ThemeMode.system`, y un teléfono en modo claro lo pinta sobre `paper50`.
    // Ahí el mint pleno compone 1,57:1 y el wordmark casi no se ve.
    testWidgets('tema oscuro: el wordmark va en accent, como el sidebar',
        (tester) async {
      await _pumpShell(tester, theme: AppTheme.dark());

      expect(
        tester.widget<TreinoLogo>(find.byType(TreinoLogo)).color,
        AppPalette.mintMagenta.accent,
      );
    });

    testWidgets('tema claro: el wordmark NO va en accent', (tester) async {
      await _pumpShell(tester, theme: AppTheme.light());

      final color = tester.widget<TreinoLogo>(find.byType(TreinoLogo)).color;
      expect(color, isNot(AppPalette.mintMagentaLight.accent));
      expect(color, AppPalette.mintMagentaLight.textPrimary);
    });
  });

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
