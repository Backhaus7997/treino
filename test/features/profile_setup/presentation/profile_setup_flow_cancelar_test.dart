// «Cancelar cuenta» en el alta, contra el reintento de `users/{uid}`.
//
// Hallazgo P1 de Codex en #1232: un intento de `createIfAbsent` que ya salió no
// se puede frenar, y si escribía DESPUÉS de borrar la cuenta de Auth el doc
// quedaba huérfano, con el mail. La pantalla ahora frena los reintentos y
// ESPERA al que está en vuelo antes de borrar. Esto mide el orden.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart'
    show authNotifierProvider, authStateChangesProvider;
import 'package:treino/features/profile/application/user_providers.dart'
    show userRepositoryProvider;
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile_setup/application/perfil_asegurado_provider.dart';
import 'package:treino/features/profile_setup/application/profile_setup_notifier.dart';
import 'package:treino/features/profile_setup/application/profile_setup_providers.dart';
import 'package:treino/features/profile_setup/application/terms_consent_provider.dart';
import 'package:treino/features/profile_setup/domain/profile_setup_draft.dart';
import 'package:treino/features/profile_setup/presentation/profile_setup_flow.dart';
import 'package:treino/l10n/app_l10n.dart';

/// El alta en el paso 0, el único que ofrece «Cancelar cuenta».
class _PasoCero extends ProfileSetupNotifier {
  @override
  ProfileSetupState build() =>
      const ProfileSetupState(draft: ProfileSetupDraft(), currentStep: 0);
}

class _AuthFalso extends AuthNotifier {
  _AuthFalso(this.alCancelar);

  final Future<void> Function() alCancelar;

  @override
  Future<User?> build() async => null;

  @override
  Future<void> cancelOnboarding() => alCancelar();
}

class _MockUser extends Mock implements User {}

class _MockUserRepository extends Mock implements UserRepository {}

/// [reintento] reemplaza el reintento de `users/{uid}`. Si es null, corre el
/// provider REAL, y hay que pasar en [extra] el repo y el auth que usa.
Widget _app({
  required Future<void> Function() alCancelar,
  Future<void>? reintentoEnVuelo,
  List<Override> extra = const [],
}) {
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => const ProfileSetupFlow()),
    GoRoute(
      path: '/welcome',
      builder: (_, __) => const Scaffold(body: Text('WELCOME')),
    ),
  ]);
  return ProviderScope(
    overrides: [
      profileSetupNotifierProvider.overrideWith(_PasoCero.new),
      termsConsentRequiredProvider.overrideWithValue(false),
      authNotifierProvider.overrideWith(() => _AuthFalso(alCancelar)),
      if (reintentoEnVuelo != null) ...[
        perfilAseguradoProvider.overrideWith((ref) async {}),
        intentoDelPerfilProvider
            .overrideWith((ref) => IntentoDelPerfil.enVuelo(reintentoEnVuelo)),
      ],
      ...extra,
    ],
    child: MaterialApp.router(
      routerConfig: router,
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
    ),
  );
}

Future<void> _confirmarCancelacion(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('profile_setup_cancel_button')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Cancelar cuenta'));
  await tester.pump();
}

void main() {
  testWidgets('espera el intento en vuelo ANTES de borrar la cuenta',
      (tester) async {
    final enVuelo = Completer<void>();
    var cancelo = false;
    var intentoTerminadoAlCancelar = false;
    await tester.pumpWidget(_app(
      reintentoEnVuelo: enVuelo.future,
      alCancelar: () async {
        cancelo = true;
        intentoTerminadoAlCancelar = enVuelo.isCompleted;
      },
    ));
    await tester.pump();

    await _confirmarCancelacion(tester);
    // El intento sigue en vuelo: todavía no se borró nada.
    expect(cancelo, isFalse);

    enVuelo.complete();
    await tester.pumpAndSettle();

    expect(cancelo, isTrue);
    expect(intentoTerminadoAlCancelar, isTrue);
    expect(find.text('WELCOME'), findsOneWidget);
  });

  // Sugerencia de la revisión: el test de arriba reemplaza el reintento y el
  // objeto del intento, así que no prueba que la pantalla espere al intento
  // que el reintento REAL registró. Éste corre el provider de verdad, con un
  // repo cuyo primer create queda colgado.
  testWidgets('con el reintento real: espera su intento antes de borrar',
      (tester) async {
    final create = Completer<void>();
    final repo = _MockUserRepository();
    when(
      () => repo.createIfAbsent(
        uid: any(named: 'uid'),
        email: any(named: 'email'),
      ),
    ).thenAnswer((_) => create.future);
    final usuario = _MockUser();
    when(() => usuario.uid).thenReturn('u1');
    when(() => usuario.email).thenReturn('a@b.com');

    var cancelo = false;
    var createTerminadoAlCancelar = false;
    await tester.pumpWidget(_app(
      alCancelar: () async {
        cancelo = true;
        createTerminadoAlCancelar = create.isCompleted;
      },
      extra: [
        userRepositoryProvider.overrideWithValue(repo),
        authStateChangesProvider.overrideWith((ref) => Stream.value(usuario)),
      ],
    ));
    await tester.pump();
    await tester.pump();
    verify(
      () => repo.createIfAbsent(uid: 'u1', email: 'a@b.com'),
    ).called(1);

    await _confirmarCancelacion(tester);
    expect(cancelo, isFalse);

    create.complete();
    await tester.pumpAndSettle();

    expect(cancelo, isTrue);
    expect(createTerminadoAlCancelar, isTrue);
  });

  // Hallazgo de la revisión: sin guarda, un segundo «Cancelar cuenta» durante
  // la espera disparaba otra baja, y si ésa fallaba volvía a habilitar los
  // reintentos con la primera todavía en curso.
  testWidgets('un segundo «Cancelar cuenta» durante la espera no hace nada',
      (tester) async {
    final enVuelo = Completer<void>();
    var cancelaciones = 0;
    await tester.pumpWidget(_app(
      reintentoEnVuelo: enVuelo.future,
      alCancelar: () async => cancelaciones++,
    ));
    await tester.pump();

    await _confirmarCancelacion(tester);
    await tester.tap(find.byKey(const Key('profile_setup_cancel_button')));
    await tester.pumpAndSettle();
    // No abre otro diálogo.
    expect(find.text('Cancelar cuenta'), findsNothing);

    enVuelo.complete();
    await tester.pumpAndSettle();

    expect(cancelaciones, 1);
  });

  testWidgets('si cancelar falla, el reintento vuelve a quedar habilitado',
      (tester) async {
    await tester.pumpWidget(_app(
      reintentoEnVuelo: Future<void>.value(),
      alCancelar: () async => throw Exception('requires-recent-login'),
    ));
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ProfileSetupFlow)),
    );
    // Lo mantiene vivo (en la app lo mantiene el reintento) y registra cada
    // valor que toma.
    final valores = <bool>[];
    container.listen<bool>(altaCanceladaProvider, (_, v) => valores.add(v));

    await _confirmarCancelacion(tester);
    await tester.pumpAndSettle();

    expect(valores, [true, false]);
    expect(find.text('WELCOME'), findsNothing);
  });
}
