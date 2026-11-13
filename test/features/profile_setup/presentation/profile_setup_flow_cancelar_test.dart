// «Cancelar cuenta» en el alta, contra el reintento de `users/{uid}`.
//
// Hallazgo P1 de Codex en #1232: un intento de `createIfAbsent` que ya salió no
// se puede frenar, y si escribía DESPUÉS de borrar la cuenta de Auth el doc
// quedaba huérfano, con el mail. La pantalla ahora frena los reintentos y
// ESPERA al que está en vuelo antes de borrar. Esto mide el orden.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall, SystemChannels;
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
import 'package:treino/features/profile_setup/presentation/widgets/profile_setup_footer.dart';
import 'package:treino/l10n/app_l10n.dart';

/// El alta en el paso 0, el único que ofrece «Cancelar cuenta».
class _PasoCero extends ProfileSetupNotifier {
  @override
  ProfileSetupState build() =>
      const ProfileSetupState(draft: ProfileSetupDraft(), currentStep: 0);
}

/// El paso 0 completo: con esto `canGoNext` es true y «SIGUIENTE» anda.
class _PasoCeroListo extends ProfileSetupNotifier {
  @override
  ProfileSetupState build() => const ProfileSetupState(
        draft: ProfileSetupDraft(username: 'ana_fit'),
        currentStep: 0,
        usernameAvailability: UsernameAvailability.available,
      );

  // El paso monta con el username precargado y lo vuelve a verificar contra
  // Firestore (debounce de 450 ms). Acá la disponibilidad queda fija.
  @override
  void updateUsername(String value) {}
}

/// Los pasos 0 y 1 completos: con SIGUIENTE de verdad se llega hasta el del
/// gimnasio (el 2), que sin tocar nada no lee ningún provider.
class _HastaElGym extends ProfileSetupNotifier {
  @override
  ProfileSetupState build() => ProfileSetupState(
        draft: ProfileSetupDraft(
          username: 'ana_fit',
          bornAt: DateTime(1995, 1, 1),
        ),
        currentStep: 0,
        usernameAvailability: UsernameAvailability.available,
      );

  @override
  void updateUsername(String value) {}
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

GoRouter _router() => GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const ProfileSetupFlow()),
      GoRoute(
        path: '/welcome',
        builder: (_, __) => const Scaffold(body: Text('WELCOME')),
      ),
    ]);

/// [reintento] reemplaza el reintento de `users/{uid}`. Si es null, corre el
/// provider REAL, y hay que pasar en [extra] el repo y el auth que usa.
Widget _app({
  required Future<void> Function() alCancelar,
  Future<void>? reintentoEnVuelo,
  ProfileSetupNotifier Function() paso = _PasoCero.new,
  List<Override> extra = const [],
  GoRouter? router,
}) {
  router ??= _router();
  return ProviderScope(
    overrides: [
      profileSetupNotifierProvider.overrideWith(paso),
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

/// Anota cada `SystemNavigator.pop`: lo que pasa cuando nadie atiende el atrás
/// del sistema, o sea que Android CIERRA LA APP.
List<MethodCall> _salidasDeLaApp(WidgetTester tester) {
  final llamadas = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'SystemNavigator.pop') llamadas.add(call);
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return llamadas;
}

/// El botón o el gesto de atrás de Android: la notificación `popRoute` del
/// engine. NO pasa por ningún botón de la pantalla, así que sólo un `PopScope`
/// lo puede frenar.
Future<void> _atrasDelSistema(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
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

  // Hallazgo de Codex en #1233: con la pantalla viva durante la baja, alguien
  // que se arrepiente podía avanzar y hacer submit en el medio de la cascada,
  // y recrear el perfil justo antes de que se borre la cuenta de Auth.
  testWidgets('mientras se cancela no se puede avanzar', (tester) async {
    final baja = Completer<void>();
    await tester.pumpWidget(_app(
      reintentoEnVuelo: Future<void>.value(),
      paso: _PasoCeroListo.new,
      alCancelar: () => baja.future,
    ));
    await tester.pump();

    VoidCallback? siguiente() => tester
        .widget<ProfileSetupFooter>(find.byType(ProfileSetupFooter))
        .onPrimary;
    // Sin esto el test pasaría de vacío: un paso 0 incompleto ya tiene el
    // botón apagado.
    expect(siguiente(), isNotNull);

    await _confirmarCancelacion(tester);
    await tester.pump();

    expect(siguiente(), isNull);

    baja.complete();
    await tester.pumpAndSettle();
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
  // Android 2/2 en la QA del 2026-11-06 (#1698): el alta es la raíz del stack,
  // y atrás cerraba la app y tiraba lo cargado. Los tres primeros prueban el
  // paso 1; el resto, que desde el segundo atrás vuelve un paso.
  group('atrás del sistema', () {
    testWidgets('en el paso 1 pregunta y NO cierra la app', (tester) async {
      final salidas = _salidasDeLaApp(tester);
      var cancelo = false;
      await tester.pumpWidget(_app(
        reintentoEnVuelo: Future<void>.value(),
        alCancelar: () async => cancelo = true,
      ));
      await tester.pump();

      await _atrasDelSistema(tester);

      expect(find.text('¿Cancelar la creación de tu cuenta?'), findsOneWidget);
      expect(salidas, isEmpty);
      expect(cancelo, isFalse);
    });

    testWidgets('«Volver al setup» deja el alta como estaba', (tester) async {
      final salidas = _salidasDeLaApp(tester);
      var cancelo = false;
      await tester.pumpWidget(_app(
        reintentoEnVuelo: Future<void>.value(),
        alCancelar: () async => cancelo = true,
      ));
      await tester.pump();
      await _atrasDelSistema(tester);

      await tester.tap(find.text('Volver al setup'));
      await tester.pumpAndSettle();

      expect(find.text('Volver al setup'), findsNothing);
      expect(find.byType(ProfileSetupFlow), findsOneWidget);
      expect(cancelo, isFalse);
      expect(salidas, isEmpty);
    });

    // El diálogo queda arriba de la pantalla: el segundo atrás es SUYO y lo
    // cierra. Si lo atendiera la pantalla, dos atrás seguidos —un gesto
    // casual— borrarían la cuenta.
    testWidgets('un segundo atrás cierra el diálogo y no borra nada',
        (tester) async {
      final salidas = _salidasDeLaApp(tester);
      var cancelo = false;
      await tester.pumpWidget(_app(
        reintentoEnVuelo: Future<void>.value(),
        alCancelar: () async => cancelo = true,
      ));
      await tester.pump();

      await _atrasDelSistema(tester);
      expect(find.text('Volver al setup'), findsOneWidget);
      await _atrasDelSistema(tester);

      expect(find.text('Volver al setup'), findsNothing);
      expect(find.byType(ProfileSetupFlow), findsOneWidget);
      expect(cancelo, isFalse);
      expect(salidas, isEmpty);
    });

    testWidgets('confirmar «Cancelar cuenta» sale igual que con la X',
        (tester) async {
      var cancelo = false;
      await tester.pumpWidget(_app(
        reintentoEnVuelo: Future<void>.value(),
        alCancelar: () async => cancelo = true,
      ));
      await tester.pump();
      await _atrasDelSistema(tester);

      await tester.tap(find.text('Cancelar cuenta'));
      await tester.pumpAndSettle();

      expect(cancelo, isTrue);
      expect(find.text('WELCOME'), findsOneWidget);
    });

    testWidgets('con la baja en curso no abre otro diálogo ni cierra la app',
        (tester) async {
      final salidas = _salidasDeLaApp(tester);
      final baja = Completer<void>();
      await tester.pumpWidget(_app(
        reintentoEnVuelo: Future<void>.value(),
        alCancelar: () => baja.future,
      ));
      await tester.pump();
      await _confirmarCancelacion(tester);

      await _atrasDelSistema(tester);

      expect(find.text('Volver al setup'), findsNothing);
      expect(salidas, isEmpty);

      baja.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('desde el paso 3 vuelve de a un paso, sin diálogo ni cierre',
        (tester) async {
      final salidas = _salidasDeLaApp(tester);
      await tester.pumpWidget(_app(
        reintentoEnVuelo: Future<void>.value(),
        paso: _HastaElGym.new,
        alCancelar: () async {},
      ));
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ProfileSetupFlow)),
      );
      int paso() => container.read(profileSetupNotifierProvider).currentStep;

      await tester.tap(find.text('SIGUIENTE'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SIGUIENTE'));
      await tester.pumpAndSettle();
      expect(paso(), 2);
      expect(find.text('¿DÓNDE ENTRENÁS?'), findsOneWidget);

      await _atrasDelSistema(tester);
      expect(paso(), 1);
      expect(find.text('¿CUÁNDO NACISTE?'), findsOneWidget);

      await _atrasDelSistema(tester);
      expect(paso(), 0);
      expect(find.text('¿CÓMO TE LLAMÁS?'), findsOneWidget);

      expect(find.text('Volver al setup'), findsNothing);
      expect(salidas, isEmpty);
    });

    // El submit exitoso no navega a mano: el redirect del router saca la
    // pantalla. Eso no es un atrás, y no puede retroceder un paso ni abrir el
    // diálogo mientras la pantalla se va.
    testWidgets('una navegación del router no cuenta como atrás',
        (tester) async {
      final router = _router();
      await tester.pumpWidget(_app(
        reintentoEnVuelo: Future<void>.value(),
        paso: _HastaElGym.new,
        alCancelar: () async {},
        router: router,
      ));
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ProfileSetupFlow)),
      );
      await tester.tap(find.text('SIGUIENTE'));
      await tester.pumpAndSettle();
      expect(container.read(profileSetupNotifierProvider).currentStep, 1);

      router.go('/welcome');
      await tester.pumpAndSettle();

      expect(find.text('WELCOME'), findsOneWidget);
      expect(container.read(profileSetupNotifierProvider).currentStep, 1);
      expect(find.text('Volver al setup'), findsNothing);
    });
  });
}
