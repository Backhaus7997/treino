// El modal del paywall (`showPlanLimitPaywall`) se dispara TAMBIEN desde la app
// movil: `TrainerDashboardTab` (home del PF) y `trainer_coach_view` viven en
// lib/features/coach/, no en el Coach Hub web. Su CTA "VER PLANES" hace
// context.push('/facturacion/planes').
//
// Esa ruta existia SOLO en el router del Coach Hub. En movil el push caia en el
// errorBuilder (NotFoundScreen): el modal decia lo correcto y el boton no
// llevaba a ningun lado. Este test pinea que la ruta este registrada en el
// router movil, para que un refactor no la vuelva a dejar afuera.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/pricing_screen.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/l10n/app_l10n.dart';

class _MockUser extends Mock implements User {}

class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._fixedState);
  final AsyncValue<User?> _fixedState;

  @override
  Future<User?> build() async {
    state = _fixedState;
    return _fixedState.valueOrNull;
  }
}

final DateTime _kDate = DateTime.utc(2026, 1, 1);

/// Trainer con perfil COMPLETO (ADR-TPO-003): sin bio/specialty/rate el
/// authRedirect lo desvia al onboarding y nunca se llega a la pricing page.
UserProfile _trainerProfile() => UserProfile(
      uid: 't1',
      email: 'trainer@example.com',
      displayName: 'Lautaro PF',
      role: UserRole.trainer,
      createdAt: _kDate,
      updatedAt: _kDate,
      trainerBio: 'Powerlifting coach',
      trainerSpecialty: 'Fuerza',
      trainerMonthlyRate: 50000,
      trainerOffersOnline: true,
    );

Iterable<String> _paths(List<RouteBase> routes) sync* {
  for (final r in routes) {
    if (r is GoRoute) yield r.path;
    yield* _paths(r.routes);
  }
}

void main() {
  test('el router movil registra /facturacion/planes (CTA del paywall)', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final router = buildRouter(
      refreshListenable: ValueNotifier<int>(0),
      read: container.read,
    );

    expect(
      _paths(router.configuration.routes),
      contains('/facturacion/planes'),
      reason: 'sin esta ruta, "VER PLANES" del paywall muere en NotFoundScreen '
          'en toda la app movil',
    );
  });
  // Que la ruta EXISTA no alcanza: montaba un `Scaffold(body: PricingScreen())`
  // pelado. Sin AppBar no habia flecha de volver, y sin SafeArea el titulo se
  // dibujaba DEBAJO de la barra de estado en cualquier telefono con notch — la
  // unica salida era el gesto del sistema, que en Android con navegacion por
  // botones ni siquiera esta. `PricingRouteScreen` es el host que aporta las dos
  // cosas; este test pinea QUE WIDGET monta la ruta, no solo su path.
  //
  // Verificado por mutacion: volviendo el builder al `Scaffold` pelado, la suite
  // ENTERA (5601 tests) seguia verde. Este es el unico test que se cae.
  testWidgets('/facturacion/planes monta el host con SafeArea y volver',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        authNotifierProvider.overrideWith(
          () => _StubAuthNotifier(AsyncData(_MockUser())),
        ),
        userProfileProvider.overrideWith(
          (ref) => Stream<UserProfile?>.value(_trainerProfile()),
        ),
        authStateChangesProvider.overrideWith((_) => Stream.value(null)),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authNotifierProvider.future);
    await container.read(userProfileProvider.future);

    final router = buildRouter(
      refreshListenable: ValueNotifier<int>(0),
      read: container.read,
    );
    router.go('/facturacion/planes');

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    // Inset del notch: con el `Scaffold` pelado el contenido arrancaba en 0.
    tester.view.padding = const FakeViewPadding(top: 47);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.dark(),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byType(PricingRouteScreen),
      findsOneWidget,
      reason: 'la ruta movil tiene que montar el host, no PricingScreen pelada',
    );
    expect(
      find.byIcon(TreinoIcon.back),
      findsOneWidget,
      reason: 'sin flecha de volver el PF queda encerrado en la pricing page',
    );
    expect(
      tester.getTopLeft(find.byType(PricingScreen)).dy,
      greaterThanOrEqualTo(47.0),
      reason: 'el contenido se dibuja debajo de la barra de estado',
    );
  });
}
