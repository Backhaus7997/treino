// Baja de cuenta del Coach Hub (#1334): diálogo + re-auth web.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/auth/data/auth_service.dart';
import 'package:treino/features/auth/domain/auth_failure.dart';
import 'package:treino/features/coach_hub/presentation/sections/ajustes/tabs/eliminar_cuenta_dialog.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';
import 'package:treino/features/profile/application/account_deletion_notifier.dart';
import 'package:treino/features/profile/application/trainer_unlink_impact_provider.dart';

import '../../../../../../helpers/test_app_wrapper.dart';

class _MockAuthService extends Mock implements AuthService {}

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

class _MockUserInfo extends Mock implements UserInfo {}

class _FakeCredential extends Fake implements AuthCredential {}

/// Notifier de verdad (un Mock no sirve: Riverpod le llama `_setElement`).
class _FakeNotifier extends AccountDeletionNotifier {
  _FakeNotifier({this.failure, this.loading = false});
  final AuthFailure? failure;
  final bool loading;
  final gate = Completer<void>();
  int deletes = 0;
  int retries = 0;

  @override
  Future<void> build() async {
    if (failure != null) throw failure!;
    if (loading) await gate.future;
  }

  @override
  Future<void> deleteAccount([BuildContext? context]) async => deletes++;

  @override
  Future<void> retry([BuildContext? context]) async => retries++;
}

User _userWith(String providerId) {
  final info = _MockUserInfo();
  when(() => info.providerId).thenReturn(providerId);
  final user = _MockUser();
  when(() => user.providerData).thenReturn([info]);
  return user;
}

FirebaseAuth _authFor(String providerId) {
  final auth = _MockFirebaseAuth();
  final user = _userWith(providerId);
  when(() => auth.currentUser).thenReturn(user);
  return auth;
}

Widget _dialogHarness({
  required _FakeNotifier notifier,
  String providerId = 'password',
  AsyncValue<int> impact = const AsyncData(0),
  bool busy = false,
}) =>
    ProviderScope(
      overrides: [
        accountDeletionNotifierProvider.overrideWith(() => notifier),
        accountDeletionBusyProvider.overrideWith((_) => busy),
        trainerUnlinkImpactProvider.overrideWithValue(impact),
        firebaseAuthProvider.overrideWithValue(_authFor(providerId)),
      ],
      child: const TestAppWrapper(child: EliminarCuentaDialog()),
    );

void main() {
  setUpAll(() => registerFallbackValue(_FakeCredential()));

  group('EliminarCuentaDialog', () {
    testWidgets('ya no es «Próximamente»: ofrece ELIMINAR y CANCELAR',
        (tester) async {
      await tester.pumpWidget(_dialogHarness(notifier: _FakeNotifier()));
      await tester.pumpAndSettle();

      expect(find.text('Eliminar cuenta'), findsOneWidget);
      expect(find.text('ELIMINAR'), findsOneWidget);
      expect(find.text('CANCELAR'), findsOneWidget);
      expect(find.textContaining('Próximamente'), findsNothing);
      expect(find.textContaining('No se devuelve el dinero'), findsOneWidget);
    });

    testWidgets('ELIMINAR dispara la baja una vez', (tester) async {
      final notifier = _FakeNotifier();
      await tester.pumpWidget(_dialogHarness(notifier: notifier));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('dialog_primary_button')));
      await tester.pump();

      expect(notifier.deletes, 1);
      expect(notifier.retries, 0);
    });

    testWidgets('muestra «Se van a desvincular N alumnos» si hay vínculos',
        (tester) async {
      await tester.pumpWidget(
        _dialogHarness(notifier: _FakeNotifier(), impact: const AsyncData(3)),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Se van a desvincular 3 alumnos'),
          findsOneWidget);
    });

    testWidgets('sin conteo (cargando) o con 0 no afirma ningún número',
        (tester) async {
      await tester.pumpWidget(
        _dialogHarness(
          notifier: _FakeNotifier(),
          impact: const AsyncLoading(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('desvincular'), findsNothing);

      await tester.pumpWidget(
        _dialogHarness(notifier: _FakeNotifier(), impact: const AsyncData(0)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('desvincular'), findsNothing);
    });

    testWidgets('Google: avisa que se abre una ventana de Google',
        (tester) async {
      await tester.pumpWidget(
        _dialogHarness(notifier: _FakeNotifier(), providerId: 'google.com'),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('ventana de Google'), findsOneWidget);
    });

    testWidgets('Apple: avisa que se abre una ventana de Apple',
        (tester) async {
      await tester.pumpWidget(
        _dialogHarness(notifier: _FakeNotifier(), providerId: 'apple.com'),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('ventana de Apple'), findsOneWidget);
    });

    testWidgets('email: no menciona ventanas', (tester) async {
      await tester.pumpWidget(_dialogHarness(notifier: _FakeNotifier()));
      await tester.pumpAndSettle();

      expect(find.textContaining('ventana de'), findsNothing);
    });

    testWidgets(
        'error de suscripción: mensaje inline y «Reintentar» que reintenta',
        (tester) async {
      final notifier =
          _FakeNotifier(failure: const AuthFailure.subscriptionCancelFailed());
      await tester.pumpWidget(_dialogHarness(notifier: notifier));
      await tester.pumpAndSettle();

      expect(find.textContaining('No pudimos cancelar tu suscripción'),
          findsOneWidget);
      expect(find.text('ELIMINAR'), findsNothing);
      expect(find.text('Reintentar'), findsOneWidget);

      await tester.tap(find.byKey(const Key('dialog_primary_button')));
      await tester.pump();

      expect(notifier.retries, 1);
      expect(notifier.deletes, 0);
    });

    testWidgets('deletionNotAllowed: mensaje y SIN «Reintentar»',
        (tester) async {
      final notifier =
          _FakeNotifier(failure: const AuthFailure.deletionNotAllowed());
      await tester.pumpWidget(_dialogHarness(notifier: notifier));
      await tester.pumpAndSettle();

      expect(find.textContaining('Escribinos y lo resolvemos'), findsOneWidget);
      expect(find.text('Reintentar'), findsNothing);
      expect(find.text('ELIMINAR'), findsNothing);
      expect(find.byKey(const Key('dialog_primary_button')), findsNothing);
    });

    testWidgets('error de popup bloqueado se ve inline con «Reintentar»',
        (tester) async {
      final notifier = _FakeNotifier(failure: const AuthFailure.popupBlocked());
      await tester.pumpWidget(_dialogHarness(notifier: notifier));
      await tester.pumpAndSettle();

      expect(find.text(const AuthFailure.popupBlocked().userMessage),
          findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    });

    testWidgets('cargando: muestra el progreso y bloquea ELIMINAR',
        (tester) async {
      final notifier = _FakeNotifier(loading: true);
      addTearDown(() {
        if (!notifier.gate.isCompleted) notifier.gate.complete();
      });
      await tester.pumpWidget(_dialogHarness(notifier: notifier));
      await tester.pump();
      await tester.pump();

      expect(find.text('Eliminando tu cuenta...'), findsOneWidget);
      await tester.tap(find.byKey(const Key('dialog_primary_button')));
      await tester.pump();
      expect(notifier.deletes, 0);
    });

    testWidgets('busy (popup de re-auth abierto) bloquea el segundo tap',
        (tester) async {
      final notifier = _FakeNotifier();
      await tester.pumpWidget(_dialogHarness(notifier: notifier, busy: true));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('dialog_primary_button')));
      await tester.pump();

      expect(notifier.deletes, 0);
    });

    testWidgets(
        'éxito: la bandera de cuenta eliminada cierra el diálogo y se baja',
        (tester) async {
      final container = ProviderContainer(overrides: [
        accountDeletionNotifierProvider.overrideWith(() => _FakeNotifier()),
        trainerUnlinkImpactProvider.overrideWithValue(const AsyncData(0)),
        firebaseAuthProvider.overrideWithValue(_authFor('password')),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: TestAppWrapper(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => showEliminarCuentaDialog(context),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.byType(EliminarCuentaDialog), findsOneWidget);

      container.read(accountDeletedFlagProvider.notifier).state = true;
      await tester.pumpAndSettle();

      expect(find.byType(EliminarCuentaDialog), findsNothing);
      expect(container.read(accountDeletedFlagProvider), isFalse);
    });
  });

  group('coachHubReauth', () {
    late _MockAuthService auth;

    setUp(() {
      auth = _MockAuthService();
      when(() => auth.reauthenticateWithGooglePopup()).thenAnswer((_) async {});
      when(() => auth.reauthenticateWithApplePopup()).thenAnswer((_) async {});
    });

    test('Google: popup de Google, sin GoogleSignIn ni credencial móvil',
        () async {
      final ok = await coachHubReauth(
        authService: auth,
        user: _userWith('google.com'),
        context: null,
      );

      expect(ok, isTrue);
      verify(() => auth.reauthenticateWithGooglePopup()).called(1);
      verifyNever(() => auth.getGoogleCredential());
      verifyNever(() => auth.reauthenticateWithApplePopup());
    });

    test('Apple: popup de Apple', () async {
      final ok = await coachHubReauth(
        authService: auth,
        user: _userWith('apple.com'),
        context: null,
      );

      expect(ok, isTrue);
      verify(() => auth.reauthenticateWithApplePopup()).called(1);
      verifyNever(() => auth.getAppleCredential());
    });

    test('popup cerrado por la persona: false, no es un error', () async {
      when(() => auth.reauthenticateWithGooglePopup())
          .thenThrow(const AuthFailure.signInCancelled());

      expect(
        await coachHubReauth(
          authService: auth,
          user: _userWith('google.com'),
          context: null,
        ),
        isFalse,
      );
    });

    test('popup bloqueado: la falla sube para mostrarse inline', () async {
      when(() => auth.reauthenticateWithGooglePopup())
          .thenThrow(const AuthFailure.popupBlocked());

      await expectLater(
        coachHubReauth(
          authService: auth,
          user: _userWith('google.com'),
          context: null,
        ),
        throwsA(const AuthFailure.popupBlocked()),
      );
    });

    group('email y contraseña', () {
      Widget host(void Function(Future<bool>) onResult) => ProviderScope(
            overrides: [authServiceProvider.overrideWithValue(auth)],
            child: TestAppWrapper(
              child: Builder(
                builder: (context) => TextButton(
                  onPressed: () => onResult(
                    coachHubReauth(
                      authService: auth,
                      user: _userWith('password'),
                      context: context,
                    ),
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          );

      testWidgets('pide la contraseña y re-autentica con ella', (tester) async {
        when(() => auth.getPasswordCredential(password: any(named: 'password')))
            .thenAnswer((_) async => _FakeCredential());
        when(() => auth.reauthenticate(any())).thenAnswer((_) async {});
        late Future<bool> result;
        await tester.pumpWidget(host((f) => result = f));
        await tester.tap(find.text('go'));
        await tester.pumpAndSettle();

        expect(find.text('Confirmá tu identidad'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'secreta123');
        await tester.tap(find.byKey(const Key('dialog_primary_button')));
        await tester.pumpAndSettle();

        expect(await result, isTrue);
        verify(() => auth.getPasswordCredential(password: 'secreta123'))
            .called(1);
        verify(() => auth.reauthenticate(any())).called(1);
        verifyNever(() => auth.reauthenticateWithGooglePopup());
      });

      testWidgets('contraseña incorrecta: error inline y el diálogo sigue',
          (tester) async {
        when(() => auth.getPasswordCredential(password: any(named: 'password')))
            .thenAnswer((_) async => _FakeCredential());
        when(() => auth.reauthenticate(any()))
            .thenThrow(const AuthFailure.reAuthFailed());
        await tester.pumpWidget(host((_) {}));
        await tester.tap(find.text('go'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'mala');
        await tester.tap(find.byKey(const Key('dialog_primary_button')));
        await tester.pumpAndSettle();

        expect(find.text(const AuthFailure.reAuthFailed().userMessage),
            findsOneWidget);
        expect(find.byType(TreinoDialog), findsOneWidget);
      });

      testWidgets('CANCELAR devuelve false sin re-autenticar', (tester) async {
        late Future<bool> result;
        await tester.pumpWidget(host((f) => result = f));
        await tester.tap(find.text('go'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('dialog_secondary_button')));
        await tester.pumpAndSettle();

        expect(await result, isFalse);
        verifyNever(() => auth.reauthenticate(any()));
      });
    });
  });
}
