import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/persistence/shared_prefs_provider.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_sidebar.dart';
import 'package:treino/features/coach_hub/presentation/shell/sidebar_registry.dart';
import 'package:treino/features/moderation/application/moderation_queue_providers.dart';

/// El ítem «Moderación» del sidebar aparece SÓLO con el claim `moderator`.
///
/// Se monta el `sidebarRegistry` REAL y no un `itemsOverride`: lo que se mide
/// es el cableado de punta a punta —`isModeratorProvider` →
/// `visibleProvider` → el filtro del sidebar—, no que un item sintético con un
/// provider falso se esconda.
///
/// **Esto es UI, no control de acceso**, y el test no puede sugerir otra cosa:
/// la ruta `/moderacion` existe igual y se puede escribir a mano. Lo que
/// protege de verdad es `assertModerator` del otro lado de los tres callables,
/// donde hay Admin SDK y las rules no participan.
void main() {
  Future<void> montar(
    WidgetTester tester, {
    required bool esModerador,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    final paths = {...sidebarRegistry.map((i) => i.route), '/ajustes'}.toList();

    final router = GoRouter(
      initialLocation: '/ajustes',
      routes: [
        ShellRoute(
          builder: (ctx, state, child) => Scaffold(
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const CoachHubSidebar(),
                Expanded(child: child),
              ],
            ),
          ),
          routes: [
            for (final p in paths)
              GoRoute(path: p, builder: (_, __) => Text('page:$p')),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => Future.value(sp)),
          // Se overridea el provider DERIVADO y no el del token: leer el claim
          // de verdad pediría un `FirebaseAuth` real. Lo que este test mide es
          // el filtro del sidebar, que consume exactamente este booleano.
          isModeratorProvider.overrideWith((ref) => esModerador),
        ],
        child: MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('SIN el claim, el item no existe en el sidebar', (tester) async {
    await montar(tester, esModerador: false);

    expect(find.text('Moderación'), findsNothing);
  });

  testWidgets('CON el claim, el item aparece', (tester) async {
    // Control positivo. Sin este caso, el de arriba pasa igual si el item
    // nunca se registró, si la etiqueta cambió, o si el sidebar entero dejó de
    // renderizar — y "no aparece" se leería como éxito.
    await montar(tester, esModerador: true);

    expect(find.text('Moderación'), findsOneWidget);
  });

  testWidgets('el resto del sidebar no se ve afectado', (tester) async {
    // El filtro nuevo corre sobre TODOS los items. Si estuviera mal escrito
    // —por ejemplo tratando `visibleProvider == null` como "no visible"— el
    // sidebar quedaría vacío y el test de arriba seguiría en verde.
    await montar(tester, esModerador: false);

    expect(find.text('Alumnos'), findsOneWidget);
  });
}
