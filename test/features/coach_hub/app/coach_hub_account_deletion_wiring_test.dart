// Cableado de producción de la baja de cuenta del Coach Hub (#1334).
//
// Los tests del diálogo inyectan un notifier falso y los de `coachHubReauth`
// pasan el AuthService a mano: ninguno prueba que los overrides REALES que
// monta `main_coach_hub.dart` lleguen a `FirebaseAuth.signOut()` y a los
// `reauthenticateWith*Popup`.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treino/core/persistence/shared_prefs_provider.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/auth/data/auth_service.dart';
import 'package:treino/features/coach_hub/presentation/sections/ajustes/tabs/eliminar_cuenta_dialog.dart';
import 'package:treino/features/profile/application/account_deletion_notifier.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/main_coach_hub.dart';

import '../../../helpers/test_app_wrapper.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

class _MockUserInfo extends Mock implements UserInfo {}

class _MockUserCredential extends Mock implements UserCredential {}

class _MockUserRepository extends Mock implements UserRepository {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _FakeAuthCredential extends Fake implements AuthCredential {
  @override
  String get providerId => 'password';
}

void main() {
  late _MockFirebaseAuth fbAuth;
  late _MockUser user;
  late _MockGoogleSignIn googleSignIn;
  late SharedPreferences prefs;

  setUpAll(() {
    registerFallbackValue(GoogleAuthProvider());
    registerFallbackValue(_FakeAuthCredential());
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    fbAuth = _MockFirebaseAuth();
    user = _MockUser();
    googleSignIn = _MockGoogleSignIn();
    when(() => fbAuth.currentUser).thenReturn(user);
    when(() => fbAuth.signOut()).thenAnswer((_) async {});
    when(() => user.email).thenReturn('pf@treino.app');
  });

  void providerIs(String id) {
    final info = _MockUserInfo();
    when(() => info.providerId).thenReturn(id);
    when(() => user.providerData).thenReturn([info]);
  }

  /// Los overrides de producción del Hub + sólo el borde de Firebase mockeado.
  ProviderContainer hubContainer() {
    final container = ProviderContainer(overrides: [
      ...coachHubProviderOverrides(prefs),
      firebaseAuthProvider.overrideWithValue(fbAuth),
      authServiceProvider.overrideWithValue(
        AuthService(
          firebaseAuth: fbAuth,
          userRepository: _MockUserRepository(),
          googleSignIn: googleSignIn,
        ),
      ),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  group('coachHubProviderOverrides (lo que monta main_coach_hub.dart)', () {
    test('incluye SharedPreferences y la baja de cuenta', () {
      final container = hubContainer();

      expect(container.read(accountDeletionReauthProvider), isNotNull);
      expect(
        container.read(sharedPreferencesProvider).requireValue,
        same(prefs),
      );
    });

    test('sign-out: FirebaseAuth.signOut directo, sin tocar GoogleSignIn',
        () async {
      final container = hubContainer();

      await container.read(accountDeletionSignOutProvider)();

      verify(() => fbAuth.signOut()).called(1);
      verifyZeroInteractions(googleSignIn);
    });

    test('re-auth Google: llega a user.reauthenticateWithPopup(Google)',
        () async {
      providerIs('google.com');
      when(() => user.reauthenticateWithPopup(any()))
          .thenAnswer((_) async => _MockUserCredential());
      final container = hubContainer();

      final ok = await container.read(accountDeletionReauthProvider)!(null);

      expect(ok, isTrue);
      final provider = verify(() => user.reauthenticateWithPopup(captureAny()))
          .captured
          .single;
      expect(provider, isA<GoogleAuthProvider>());
      verifyZeroInteractions(googleSignIn);
    });

    test('re-auth Apple: llega a user.reauthenticateWithPopup(apple.com)',
        () async {
      providerIs('apple.com');
      when(() => user.reauthenticateWithPopup(any()))
          .thenAnswer((_) async => _MockUserCredential());
      final container = hubContainer();

      final ok = await container.read(accountDeletionReauthProvider)!(null);

      expect(ok, isTrue);
      final provider = verify(() => user.reauthenticateWithPopup(captureAny()))
          .captured
          .single as OAuthProvider;
      expect(provider.providerId, 'apple.com');
    });

    testWidgets(
        're-auth con contraseña: diálogo → reauthenticateWithCredential',
        (tester) async {
      providerIs('password');
      when(() => user.reauthenticateWithCredential(any()))
          .thenAnswer((_) async => _MockUserCredential());
      final container = hubContainer();

      late Future<bool> result;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: TestAppWrapper(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => result =
                    container.read(accountDeletionReauthProvider)!(context),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'secreta123');
      await tester.tap(find.byKey(const Key('dialog_primary_button')));
      await tester.pumpAndSettle();

      expect(await result, isTrue);
      verify(() => user.reauthenticateWithCredential(any())).called(1);
      verifyNever(() => user.reauthenticateWithPopup(any()));
    });
  });

  test('coachHubAccountDeletionOverrides sigue exportado para el Hub', () {
    expect(coachHubAccountDeletionOverrides, hasLength(2));
  });
}
