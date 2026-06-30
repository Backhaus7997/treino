import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/persistence/shared_prefs_provider.dart';
import 'package:treino/features/coach_hub/application/sidebar_collapsed_provider.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_sidebar.dart';
import 'package:treino/features/coach_hub/presentation/shell/sidebar_registry.dart';

/// Monta el sidebar dentro de un `ShellRoute` real (necesita `GoRouterState`).
/// Resuelve las prefs en el cuerpo del test y overridea
/// `sharedPreferencesProvider` con un future ya completo → estado colapsado
/// determinista, sin depender del timing del method channel.
Future<void> _pumpSidebar(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  String initial = '/dashboard',
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final paths = sidebarRegistry.map((i) => i.route).toSet().toList();

  final router = GoRouter(
    initialLocation: initial,
    routes: [
      ShellRoute(
        builder: (ctx, state, child) => Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [const CoachHubSidebar(), Expanded(child: child)],
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
      ],
      child: MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('expandido → 264px, 6 headers y 19 labels [SCENARIO-750]',
      (tester) async {
    await _pumpSidebar(tester);

    final size =
        tester.getSize(find.byKey(const Key('coach_hub_sidebar_container')));
    expect(size.width, 264);

    for (final header in [
      'RESUMEN',
      'ALUMNOS',
      'PLAN',
      'WELLNESS',
      'NEGOCIO',
      'COMUNICACIÓN',
    ]) {
      expect(find.text(header), findsOneWidget, reason: header);
    }

    for (final item in sidebarRegistry) {
      expect(find.text(item.label), findsOneWidget, reason: item.label);
    }
  });

  testWidgets('colapsado → 72px, headers y labels ocultos [SCENARIO-754]',
      (tester) async {
    await _pumpSidebar(tester, prefs: {'coach_hub.sidebar.collapsed': true});

    final size =
        tester.getSize(find.byKey(const Key('coach_hub_sidebar_container')));
    expect(size.width, 72);

    expect(find.text('RESUMEN'), findsNothing);
    expect(find.text('Dashboard'), findsNothing);
    expect(find.byType(Icon), findsWidgets);
  });

  testWidgets('tap en item navega via context.go [SCENARIO-752]',
      (tester) async {
    await _pumpSidebar(tester);

    await tester.tap(find.text('Alumnos'));
    await tester.pumpAndSettle();

    expect(find.text('page:/alumnos'), findsOneWidget);
  });
}
