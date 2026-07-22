// Tests de AlumnoBreadcrumb — link «‹ Alumnos» del detalle de Alumno.
//
// Remediación barrido final (accesibilidad de teclado sistémica): el widget
// envolvía un TreinoTappable crudo (sin Focus ni Semantics(button)) en vez de
// TreinoInteractiveState — inalcanzable por teclado.
//
// SCENARIO-ABC-01: tap navega a `/alumnos`.
// SCENARIO-ABC-02: focusable, Semantics(button) y Enter activa la navegación.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/sections/alumnos/widgets/alumno_breadcrumb.dart';

Future<GoRouter> _pumpWithRouter(WidgetTester tester, Widget child) async {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => child),
      GoRoute(
          path: '/alumnos', builder: (_, __) => const Text('page:/alumnos')),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    MaterialApp.router(
      theme: AppTheme.dark(),
      routerConfig: router,
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  group('AlumnoBreadcrumb —', () {
    testWidgets('tap en «Alumnos» navega a /alumnos [SCENARIO-ABC-01]',
        (tester) async {
      await _pumpWithRouter(
        tester,
        Builder(
          builder: (context) => AlumnoBreadcrumb(
            palette: AppPalette.of(context),
          ),
        ),
      );

      await tester.tap(find.text('Alumnos'));
      await tester.pumpAndSettle();

      expect(find.text('page:/alumnos'), findsOneWidget);
    });

    testWidgets(
        '«Alumnos»: focusable, Semantics(button) y Enter activa la '
        'navegación [SCENARIO-ABC-02]', (tester) async {
      final handle = tester.ensureSemantics();

      await _pumpWithRouter(
        tester,
        Builder(
          builder: (context) => AlumnoBreadcrumb(
            palette: AppPalette.of(context),
          ),
        ),
      );

      final semantics = tester.getSemantics(find.text('Alumnos'));
      expect(semantics.flagsCollection.isButton, isTrue,
          reason:
              'el link "Alumnos" debe exponer Semantics(button: true)');

      final focusNode = Focus.of(tester.element(find.text('Alumnos')));
      focusNode.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('page:/alumnos'), findsOneWidget,
          reason: 'Enter (teclado) debe activar la navegación igual que el tap');

      handle.dispose();
    });
  });
}
