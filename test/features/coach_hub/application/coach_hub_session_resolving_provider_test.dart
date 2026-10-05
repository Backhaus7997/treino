import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/coach_hub/application/coach_hub_session_resolving_provider.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

import '../../../helpers/coach_hub_profiles.dart';
import '../../../helpers/onboarding_test_helpers.dart';

class _MockUser extends Mock implements User {}

/// Auth que queda en `AsyncLoading` hasta que el test completa [result]: el
/// estado que tiene el provider real mientras Firebase todavía no emitió.
class _ControlledAuth extends AuthNotifier {
  _ControlledAuth(this.result);

  final Completer<User?> result;

  @override
  Future<User?> build() => result.future;
}

/// El PF sale de `trainerCompleto()` (etapa `done`): estos tests miden la
/// resolución de la sesión, no el onboarding.
UserProfile _profile(UserRole role) => role == UserRole.trainer
    ? trainerCompleto(
        uid: 'test-uid',
        email: 'pf@example.com',
        onboardingSeen: allSurfacesSeen(),
      )
    : UserProfile(
        onboardingSeen: allSurfacesSeen(),
        uid: 'test-uid',
        email: 'pf@example.com',
        displayName: 'Mateo',
        role: role,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );

ProviderContainer _container({
  required Completer<User?> auth,
  required Stream<UserProfile?> profile,
}) {
  final container = ProviderContainer(overrides: [
    authNotifierProvider.overrideWith(() => _ControlledAuth(auth)),
    userProfileProvider.overrideWith((ref) => profile),
  ]);
  addTearDown(container.dispose);
  return container;
}

/// Deja correr los microtasks pendientes: el `Future` de auth y el primer
/// evento del stream del perfil llegan por ahí.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  // La regla espeja las dos esperas de `coachHubRedirect` (auth y perfil): ver
  // el dartdoc del provider.
  group('coachHubSessionResolvingProvider', () {
    test(
        'sesión de auth cargando → resolviendo, aunque el perfil ya tenga dato',
        () async {
      final auth = Completer<User?>();
      final container = _container(
        auth: auth,
        profile: Stream.value(_profile(UserRole.trainer)),
      );
      // Mantiene vivo el provider de auth: sin listener se descartaría.
      container.listen(authNotifierProvider, (_, __) {});
      await _settle();

      expect(container.read(coachHubSessionResolvingProvider), isTrue);
    });

    test('con sesión y perfil cargando → resolviendo', () async {
      final auth = Completer<User?>()..complete(_MockUser());
      // `Stream.empty()` es lo que `userProfileProvider` usa mientras auth
      // carga: nunca emite, así que el provider queda en `AsyncLoading`.
      final container = _container(auth: auth, profile: const Stream.empty());
      container.listen(authNotifierProvider, (_, __) {});
      container.listen(userProfileProvider, (_, __) {});
      await _settle();

      expect(container.read(coachHubSessionResolvingProvider), isTrue);
    });

    test(
        'con sesión de PF y perfil resuelto → NO resolviendo: se queda en el '
        'shell', () async {
      final auth = Completer<User?>()..complete(_MockUser());
      final container = _container(
        auth: auth,
        profile: Stream.value(_profile(UserRole.trainer)),
      );
      container.listen(authNotifierProvider, (_, __) {});
      container.listen(userProfileProvider, (_, __) {});
      await _settle();

      expect(container.read(coachHubSessionResolvingProvider), isFalse);
    });

    // El shell NO puede mostrar el banner para una sesión que el router está
    // sacando de ahí: su página sigue dibujándose debajo de la que entra
    // durante la transición de ruta (ver el dartdoc del provider).
    test(
        'con sesión de atleta → resolviendo: el redirect lo manda a '
        '/not-allowed', () async {
      final auth = Completer<User?>()..complete(_MockUser());
      final container = _container(
        auth: auth,
        profile: Stream.value(_profile(UserRole.athlete)),
      );
      container.listen(authNotifierProvider, (_, __) {});
      container.listen(userProfileProvider, (_, __) {});
      await _settle();

      expect(container.read(coachHubSessionResolvingProvider), isTrue);
    });

    test('con sesión y perfil ausente → resolviendo (defensivo: /not-allowed)',
        () async {
      final auth = Completer<User?>()..complete(_MockUser());
      final container = _container(auth: auth, profile: Stream.value(null));
      container.listen(authNotifierProvider, (_, __) {});
      container.listen(userProfileProvider, (_, __) {});
      await _settle();

      expect(container.read(coachHubSessionResolvingProvider), isTrue);
    });

    test(
        'sin sesión → resolviendo, sin mirar el perfil: el redirect manda a '
        '/login', () async {
      final auth = Completer<User?>()..complete(null);
      // Un estado incoherente a propósito —sin sesión pero con el perfil de un
      // PF—: la respuesta no puede depender del perfil, que para un anónimo no
      // significa nada.
      final container = _container(
        auth: auth,
        profile: Stream.value(_profile(UserRole.trainer)),
      );
      container.listen(authNotifierProvider, (_, __) {});
      container.listen(userProfileProvider, (_, __) {});
      await _settle();

      expect(container.read(coachHubSessionResolvingProvider), isTrue);
    });

    test('error de auth → NO resolviendo: es un estado terminal, no una espera',
        () async {
      final auth = Completer<User?>()..completeError(StateError('auth rota'));
      final container = _container(auth: auth, profile: const Stream.empty());
      container.listen(authNotifierProvider, (_, __) {});
      await _settle();

      expect(container.read(authNotifierProvider).hasError, isTrue);
      expect(container.read(coachHubSessionResolvingProvider), isFalse);
    });

    // El caso real, de punta a punta: el flag tiene que pasar de true a false
    // UNA vez, cuando llega el perfil — no parpadear en el medio, y no
    // quedarse en true.
    test('sigue en true al llegar la sesión y baja a false al llegar el perfil',
        () async {
      final auth = Completer<User?>();
      final profile = StreamController<UserProfile?>();
      addTearDown(profile.close);
      final container = _container(auth: auth, profile: profile.stream);
      container.listen(authNotifierProvider, (_, __) {});
      container.listen(userProfileProvider, (_, __) {});

      final cambios = <bool>[];
      container.listen<bool>(
        coachHubSessionResolvingProvider,
        (_, next) => cambios.add(next),
      );

      await _settle();
      expect(container.read(coachHubSessionResolvingProvider), isTrue);

      auth.complete(_MockUser());
      await _settle();
      expect(
        container.read(coachHubSessionResolvingProvider),
        isTrue,
        reason: 'con sesión pero sin perfil todavía se sigue esperando',
      );

      profile.add(_profile(UserRole.trainer));
      await _settle();
      expect(container.read(coachHubSessionResolvingProvider), isFalse);

      // Un solo cambio observable: true → false.
      expect(cambios, [false]);
    });
  });
}
