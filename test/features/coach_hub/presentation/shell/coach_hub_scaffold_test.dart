import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/application/sidebar_collapsed_provider.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_scaffold.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_sidebar.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_top_bar.dart';

// TODO(W1.3): responsive tests (mobile banner < 768, force-collapse 1024–1279).

/// Monta el `CoachHubScaffold` dentro de un `ShellRoute`, con el `child`
/// provisto por la ruta activa (como en producción, ADR-CHW-008).
Future<void> _pumpScaffold(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();

  final router = GoRouter(
    initialLocation: '/dashboard',
    routes: [
      ShellRoute(
        pageBuilder: (ctx, state, child) =>
            NoTransitionPage(child: CoachHubScaffold(child: child)),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (_, __) => const Text('CONTENT_SLOT'),
          ),
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
  testWidgets('renderiza sidebar + top bar + slot de contenido [SCENARIO-748]',
      (tester) async {
    await _pumpScaffold(tester);

    expect(find.byType(CoachHubSidebar), findsOneWidget);
    expect(find.byType(CoachHubTopBar), findsOneWidget);
    expect(find.text('CONTENT_SLOT'), findsOneWidget);
  });

  testWidgets('usa palette.bg como fondo, sin HEX literal [SCENARIO-749]',
      (tester) async {
    await _pumpScaffold(tester);

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AppPalette.mintMagenta.bg);
  });

  testWidgets('existe exactamente un Scaffold en el shell', (tester) async {
    await _pumpScaffold(tester);
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
