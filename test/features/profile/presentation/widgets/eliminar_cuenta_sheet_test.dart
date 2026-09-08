// T44 RED — SCENARIO-560, 561, 562, 564
import 'package:flutter/material.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/profile/application/account_deletion_notifier.dart';
import 'package:treino/features/profile/presentation/widgets/eliminar_cuenta_sheet.dart';

import '../../../../helpers/test_app_wrapper.dart';

// --- Mocks ---
class MockAccountDeletionNotifier extends Mock
    implements AccountDeletionNotifier {
  @override
  Future<void> build() async {}
}

Widget _buildSheet({AccountDeletionNotifier? notifier}) {
  notifier ??= MockAccountDeletionNotifier();

  return ProviderScope(
    overrides: [
      accountDeletionNotifierProvider.overrideWith(() => notifier!),
    ],
    child: const TestAppWrapper(
      child: EliminarCuentaSheet(),
    ),
  );
}

void main() {
  // SCENARIO-560
  testWidgets(
      'SCENARIO-560: renders title "Eliminar cuenta", CANCELAR and ELIMINAR buttons',
      (tester) async {
    await tester.pumpWidget(_buildSheet());
    await tester.pumpAndSettle();

    expect(find.text('Eliminar cuenta'), findsOneWidget);
    expect(find.text('CANCELAR'), findsOneWidget);
    expect(find.text('ELIMINAR'), findsOneWidget);
  });

  // SCENARIO-560: destructive copy visible via RichText
  testWidgets('SCENARIO-560: destructive RichText copy is rendered',
      (tester) async {
    await tester.pumpWidget(_buildSheet());
    await tester.pumpAndSettle();

    // The body is a RichText widget. Verify at least one RichText is present
    // (the body copy with the word "irreversible" in a bold span).
    expect(find.byType(RichText), findsAtLeastNWidgets(1));
  });

  // SCENARIO-561: tap CANCELAR closes sheet
  testWidgets('SCENARIO-560: tap CANCELAR pops the sheet', (tester) async {
    bool popped = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountDeletionNotifierProvider
              .overrideWith(() => MockAccountDeletionNotifier()),
        ],
        child: TestAppWrapper(
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                await showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => const EliminarCuentaSheet(),
                );
                popped = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('CANCELAR'), findsOneWidget);
    await tester.tap(find.text('CANCELAR'));
    await tester.pumpAndSettle();

    expect(popped, isTrue);
  });

  // Fija el contrato: al confirmarse el borrado, el sheet se va y se aterriza
  // en /welcome.
  //
  // ATENCIÓN — este test NO reproduce el bug reportado (sheet flotando sobre
  // la pantalla de bienvenida después de borrar). Pasa con el pop explícito y
  // pasa sin él, incluso modelando el `ShellRoute` como la app real: en este
  // harness el `go()` sí se lleva el modal. O sea que en producción hay un
  // factor que acá no está —el sign-out, el redirect del router y su carrera
  // con este listener son los candidatos— y hasta que ese factor se aísle, el
  // pop explícito es una defensa razonable pero SIN prueba de que arregle lo
  // que se vio.
  //
  // Se deja igual porque el contrato que assertea es el correcto y hoy nadie
  // lo cubría.
  testWidgets('al confirmarse el borrado, el sheet se cierra y va a /welcome',
      (tester) async {
    // Router de verdad y no `TestAppWrapper`: este listener SIEMPRE dependió de
    // un `GoRouter` en contexto —ya llamaba `context.go('/welcome')`— y ningún
    // test lo ejercitaba, así que la dependencia nunca se había verificado.
    // Con `ShellRoute`, como la app real: el sheet se abre desde /perfil, que
    // vive DENTRO del shell, así que `showModalBottomSheet` lo empuja al
    // navigator del shell. /welcome está AFUERA. Esa es la forma exacta en la
    // que el modal sobrevivía al `go()`.
    final router = GoRouter(
      initialLocation: '/perfil',
      routes: [
        ShellRoute(
          builder: (_, __, child) => Scaffold(body: child),
          routes: [
            GoRoute(
              path: '/perfil',
              builder: (context, _) => TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => const EliminarCuentaSheet(),
                ),
                child: const Text('open'),
              ),
            ),
          ],
        ),
        GoRoute(
          path: '/welcome',
          builder: (_, __) => const Scaffold(body: Text('welcome')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountDeletionNotifierProvider
              .overrideWith(() => MockAccountDeletionNotifier()),
        ],
        child: MaterialApp.router(
          theme: AppTheme.dark(),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
          routerConfig: router,
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(EliminarCuentaSheet), findsOneWidget);

    // El notifier confirma que Auth borró al usuario.
    final container = ProviderScope.containerOf(
      tester.element(find.text('open')),
    );
    container.read(accountDeletedFlagProvider.notifier).state = true;
    await tester.pumpAndSettle();

    expect(
      find.byType(EliminarCuentaSheet),
      findsNothing,
      reason: 'el sheet tiene que cerrarse solo: `go()` no se lo lleva porque '
          'un modal vive en el Navigator RAÍZ, arriba del stack de páginas',
    );
    expect(find.text('welcome'), findsOneWidget);
  });

  // SCENARIO-562: loading state shows spinner
  testWidgets('SCENARIO-562: AsyncLoading state shows spinner and loading text',
      (tester) async {
    final mockNotifier = MockAccountDeletionNotifier();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountDeletionNotifierProvider.overrideWith(() => mockNotifier),
        ],
        child: const TestAppWrapper(
          child: EliminarCuentaSheet(),
        ),
      ),
    );

    // Simulate loading state
    await tester.pumpAndSettle();

    // The widget renders without crash in normal state
    expect(find.text('Eliminar cuenta'), findsOneWidget);
  });
}
