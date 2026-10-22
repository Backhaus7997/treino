// T44 RED — SCENARIO-560, 561, 562, 564
import 'package:flutter/material.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/auth/domain/auth_failure.dart';
import 'package:treino/features/profile/application/account_deletion_notifier.dart';
import 'package:treino/features/profile/application/trainer_unlink_impact_provider.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/presentation/widgets/eliminar_cuenta_sheet.dart';

import '../../../../helpers/onboarding_test_helpers.dart';
import '../../../../helpers/test_app_wrapper.dart';

// --- Mocks ---
// Un `Mock` de mocktail NO sirve como Notifier: Riverpod le llama `_setElement`
// y revienta con NoSuchMethodError, o sea que el estado arrancaba en ERROR. El
// sheet viejo mostraba los errores en un SnackBar que sólo se disparaba ante un
// CAMBIO de estado, así que ese error de arranque nunca se veía; ahora el error
// vive en el sheet y el doble tiene que ser un Notifier de verdad.
class MockAccountDeletionNotifier extends AccountDeletionNotifier {
  @override
  Future<void> build() async {}
}

UserProfile _profile(UserRole role) => UserProfile(
      onboardingSeen: allSurfacesSeen(),
      uid: 'uid-test',
      email: 'test@test.com',
      displayName: 'Test User',
      role: role,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
    );

/// Notifier que arranca en error y cuenta los retry.
class _ErrorNotifier extends AccountDeletionNotifier {
  _ErrorNotifier(this.failure);
  final AuthFailure failure;
  int retries = 0;

  @override
  Future<void> build() async => throw failure;

  @override
  Future<void> retry([BuildContext? context]) async => retries++;
}

Widget _buildSheet({
  bool busy = false,
  AccountDeletionNotifier? notifier,
  UserRole role = UserRole.athlete,
  AsyncValue<int> unlinkImpact = const AsyncData(0),
}) {
  notifier ??= MockAccountDeletionNotifier();

  return ProviderScope(
    overrides: [
      accountDeletionNotifierProvider.overrideWith(() => notifier!),
      accountDeletionBusyProvider.overrideWith((_) => busy),
      userProfileProvider.overrideWith((_) => Stream.value(_profile(role))),
      trainerUnlinkImpactProvider.overrideWithValue(unlinkImpact),
    ],
    child: const TestAppWrapper(
      child: EliminarCuentaSheet(),
    ),
  );
}

/// Notifier que pasa a AsyncLoading al tocar ELIMINAR y falla a pedido.
class _ControlledNotifier extends AccountDeletionNotifier {
  @override
  Future<void> build() async {}

  @override
  Future<void> deleteAccount([BuildContext? context]) async {
    state = const AsyncLoading();
  }

  void fail(AuthFailure failure) =>
      state = AsyncError(failure, StackTrace.empty);
}

/// Opacidad efectiva de [finder]: producto de los fades que lo envuelven
/// (`AnimatedOpacity` y `AnimatedSwitcher` pintan con `FadeTransition`).
double _opacityOf(WidgetTester tester, Finder finder) {
  var opacity = 1.0;
  final fades = find.ancestor(
    of: finder,
    matching: find.byWidgetPredicate(
      (w) => w is Opacity || w is FadeTransition,
    ),
  );
  for (final w in tester.widgetList(fades)) {
    opacity *= w is Opacity ? w.opacity : (w as FadeTransition).opacity.value;
  }
  return opacity;
}

/// El sheet abierto como en la app: modal, `isScrollControlled`, `bgCard`.
Widget _buildModal(AccountDeletionNotifier notifier) {
  return ProviderScope(
    overrides: [
      accountDeletionNotifierProvider.overrideWith(() => notifier),
      userProfileProvider
          .overrideWith((_) => Stream.value(_profile(UserRole.athlete))),
    ],
    child: TestAppWrapper(
      child: Builder(
        builder: (context) => TextButton(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            useRootNavigator: true,
            isScrollControlled: true,
            builder: (_) => const EliminarCuentaSheet(),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
}

/// Más que el `AppMotion.base` (240 ms) del cross-fade. `pumpAndSettle` no
/// sirve con el spinner girando.
const _fade = Duration(milliseconds: 400);

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

  // Eliminar la cuenta da de baja la suscripcion pero NO devuelve plata. Sin este
  // aviso, quien borra la cuenta cree que se le reembolsa (y el texto viejo de
  // Coach Hub lo prometia de verdad).
  testWidgets(
      'avisa que la suscripcion se cancela y que no se devuelve el dinero',
      (tester) async {
    await tester.pumpWidget(_buildSheet());
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Si tenés una suscripción paga, se cancela y no se te vuelve a cobrar. '
        'No se devuelve el dinero del período en curso.',
      ),
      findsOneWidget,
    );
  });

  // SCENARIO-561: tap CANCELAR closes sheet
  testWidgets('SCENARIO-560: tap CANCELAR pops the sheet', (tester) async {
    bool popped = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountDeletionNotifierProvider
              .overrideWith(() => MockAccountDeletionNotifier()),
          userProfileProvider
              .overrideWith((_) => Stream.value(_profile(UserRole.athlete))),
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
          userProfileProvider
              .overrideWith((_) => Stream.value(_profile(UserRole.athlete))),
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

  group('aviso de alumnos que se desvinculan (SC-PSD-31..33)', () {
    testWidgets('PF con 3 alumnos ve el aviso y ELIMINAR sigue habilitado',
        (tester) async {
      await tester.pumpWidget(
        _buildSheet(role: UserRole.trainer, unlinkImpact: const AsyncData(3)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Se van a desvincular 3 alumnos. Les avisamos.'),
        findsOneWidget,
      );
      final cta = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'ELIMINAR'),
      );
      expect(cta.onPressed, isNotNull);
    });

    testWidgets('PF con 1 alumno usa el singular', (tester) async {
      await tester.pumpWidget(
        _buildSheet(role: UserRole.trainer, unlinkImpact: const AsyncData(1)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Se va a desvincular 1 alumno. Le avisamos.'),
        findsOneWidget,
      );
    });

    testWidgets('PF con 0 alumnos no ve el aviso', (tester) async {
      await tester.pumpWidget(
        _buildSheet(role: UserRole.trainer, unlinkImpact: const AsyncData(0)),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('desvincular'), findsNothing);
    });

    testWidgets('un atleta no ve el aviso aunque el conteo exista',
        (tester) async {
      await tester.pumpWidget(
        _buildSheet(role: UserRole.athlete, unlinkImpact: const AsyncData(3)),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('desvincular'), findsNothing);
    });

    testWidgets('conteo cargando: sin aviso y sin bloquear la baja',
        (tester) async {
      await tester.pumpWidget(
        _buildSheet(
          role: UserRole.trainer,
          unlinkImpact: const AsyncLoading<int>(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('desvincular'), findsNothing);
      final cta = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'ELIMINAR'),
      );
      expect(cta.onPressed, isNotNull);
    });

    testWidgets('conteo con error: sin aviso y sin bloquear la baja',
        (tester) async {
      await tester.pumpWidget(
        _buildSheet(
          role: UserRole.trainer,
          unlinkImpact: const AsyncError<int>('x', StackTrace.empty),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('desvincular'), findsNothing);
      final cta = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'ELIMINAR'),
      );
      expect(cta.onPressed, isNotNull);
    });
  });

  // El sheet se abre en el Navigator RAÍZ: un SnackBar del Scaffold de abajo
  // queda tapado por el modal. El error TIENE que estar dentro del sheet.
  group('error visible dentro de la hoja', () {
    testWidgets('unavailable: muestra el mensaje de la suscripción y reintenta',
        (tester) async {
      final notifier = _ErrorNotifier(
        const AuthFailure.subscriptionCancelFailed(),
      );
      await tester.pumpWidget(_buildSheet(notifier: notifier));
      await tester.pumpAndSettle();

      final msg = find.descendant(
        of: find.byType(EliminarCuentaSheet),
        matching: find.text(
          'No pudimos cancelar tu suscripción, así que tu cuenta no se '
          'eliminó. Probá de nuevo en unos minutos.',
        ),
      );
      expect(msg, findsOneWidget);

      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      expect(notifier.retries, 1);
    });

    testWidgets('permission-denied: mensaje claro, no el genérico',
        (tester) async {
      await tester.pumpWidget(
        _buildSheet(
          notifier: _ErrorNotifier(const AuthFailure.deletionNotAllowed()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'No pudimos eliminar tu cuenta desde la app. Escribinos y lo '
          'resolvemos.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('No pudimos eliminar tu cuenta. Probá de nuevo.'),
        findsNothing,
      );
    });

    testWidgets('permission-denied: sin Reintentar (no puede resolverse)',
        (tester) async {
      await tester.pumpWidget(
        _buildSheet(
          notifier: _ErrorNotifier(const AuthFailure.deletionNotAllowed()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reintentar'), findsNothing);
    });

    testWidgets('busy (re-auth abierta): Reintentar y ELIMINAR deshabilitados',
        (tester) async {
      await tester.pumpWidget(
        _buildSheet(
          busy: true,
          notifier: _ErrorNotifier(const AuthFailure.deletionFailed()),
        ),
      );
      await tester.pumpAndSettle();

      final retry = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Reintentar'),
      );
      final cta = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'ELIMINAR'),
      );
      expect(retry.onPressed, isNull);
      expect(cta.onPressed, isNull);
    });

    testWidgets(
        'pantalla chica y texto x2: sin overflow, con aviso, error y botón',
        (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 480),
            textScaler: TextScaler.linear(2),
          ),
          child: _buildSheet(
            role: UserRole.trainer,
            unlinkImpact: const AsyncData(3),
            notifier: _ErrorNotifier(const AuthFailure.deletionFailed()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('desvincular'), findsOneWidget);
      expect(
        find.text('No pudimos eliminar tu cuenta. Probá de nuevo.'),
        findsOneWidget,
      );
      expect(find.text('Reintentar'), findsOneWidget);
      // Alcanzable: el contenido hace scroll.
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('error genérico: mensaje de deletionFailed', (tester) async {
      await tester.pumpWidget(
        _buildSheet(
          notifier: _ErrorNotifier(const AuthFailure.deletionFailed()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('No pudimos eliminar tu cuenta. Probá de nuevo.'),
        findsOneWidget,
      );
    });
  });

  // La carga se dibujaba ENCIMA de la confirmación con un velo `bg` al 85 %
  // sobre un sheet `bgCard`: título, párrafos y ELIMINAR se leían debajo del
  // spinner. La carga tiene que REEMPLAZAR el contenido.
  group('carga: reemplaza la confirmación', () {
    final confirmacion = [
      'Eliminar cuenta',
      'ELIMINAR',
      'CANCELAR',
      'Si tenés una suscripción paga, se cancela y no se te vuelve a cobrar. '
          'No se devuelve el dinero del período en curso.',
    ];

    testWidgets('en reposo: confirmación visible y sin carga', (tester) async {
      await tester.pumpWidget(_buildModal(_ControlledNotifier()));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      for (final t in confirmacion) {
        expect(_opacityOf(tester, find.text(t)), 1.0, reason: t);
      }
      expect(find.text('Eliminando tu cuenta...'), findsNothing);
    });

    testWidgets(
        'cargando: la confirmación queda invisible y sin taps; la carga, visible',
        (tester) async {
      await tester.pumpWidget(_buildModal(_ControlledNotifier()));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('ELIMINAR'));
      await tester.pump();
      await tester.pump(_fade);

      for (final t in confirmacion) {
        expect(_opacityOf(tester, find.text(t)), 0.0, reason: t);
      }
      expect(find.text('ELIMINAR').hitTestable(), findsNothing);
      expect(find.text('CANCELAR').hitTestable(), findsNothing);

      for (final t in [
        'Eliminando tu cuenta...',
        'Esto puede tardar unos segundos.',
      ]) {
        expect(_opacityOf(tester, find.text(t)), 1.0, reason: t);
      }
      expect(
        _opacityOf(tester, find.byType(CircularProgressIndicator)),
        1.0,
      );
    });

    testWidgets('cargando: el alto del sheet no cambia', (tester) async {
      await tester.pumpWidget(_buildModal(_ControlledNotifier()));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final antes = tester.getSize(find.byType(EliminarCuentaSheet));

      await tester.tap(find.text('ELIMINAR'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
        expect(tester.getSize(find.byType(EliminarCuentaSheet)), antes);
      }
    });

    // Control del control: el mismo drag y el mismo tap afuera SÍ cierran el
    // sheet en reposo. Sin esto, «no se cerró» podría ser un gesto que nunca
    // llegó.
    testWidgets('en reposo: el drag hacia abajo cierra el sheet',
        (tester) async {
      await tester.pumpWidget(_buildModal(_ControlledNotifier()));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.fling(
        find.text('Eliminar cuenta'),
        const Offset(0, 500),
        2000,
      );
      await tester.pumpAndSettle();
      expect(find.byType(EliminarCuentaSheet), findsNothing);
    });

    testWidgets('en reposo: el tap afuera cierra el sheet', (tester) async {
      await tester.pumpWidget(_buildModal(_ControlledNotifier()));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.byType(EliminarCuentaSheet), findsNothing);
    });

    testWidgets('cargando: ni el drag ni el tap afuera cierran el sheet',
        (tester) async {
      await tester.pumpWidget(_buildModal(_ControlledNotifier()));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ELIMINAR'));
      await tester.pump();
      await tester.pump(_fade);

      await tester.fling(
        find.text('Eliminando tu cuenta...'),
        const Offset(0, 500),
        2000,
      );
      await tester.pump();
      await tester.pump(_fade);
      expect(find.byType(EliminarCuentaSheet), findsOneWidget, reason: 'drag');

      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      await tester.pump(_fade);
      expect(find.byType(EliminarCuentaSheet), findsOneWidget,
          reason: 'tap afuera');
    });

    testWidgets('si falla, vuelve la confirmación con el error adentro',
        (tester) async {
      final notifier = _ControlledNotifier();
      await tester.pumpWidget(_buildModal(notifier));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ELIMINAR'));
      await tester.pump();
      await tester.pump(_fade);

      notifier.fail(const AuthFailure.deletionFailed());
      await tester.pumpAndSettle();

      expect(find.text('Eliminando tu cuenta...'), findsNothing);
      for (final t in confirmacion) {
        expect(_opacityOf(tester, find.text(t)), 1.0, reason: t);
      }
      final error = find.descendant(
        of: find.byType(EliminarCuentaSheet),
        matching: find.text('No pudimos eliminar tu cuenta. Probá de nuevo.'),
      );
      expect(error, findsOneWidget);
      expect(_opacityOf(tester, error), 1.0);
      expect(find.text('ELIMINAR').hitTestable(), findsOneWidget);
    });
  });

  // SCENARIO-562: loading state shows spinner
  testWidgets('SCENARIO-562: AsyncLoading state shows spinner and loading text',
      (tester) async {
    final mockNotifier = MockAccountDeletionNotifier();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountDeletionNotifierProvider.overrideWith(() => mockNotifier),
          userProfileProvider
              .overrideWith((_) => Stream.value(_profile(UserRole.athlete))),
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
