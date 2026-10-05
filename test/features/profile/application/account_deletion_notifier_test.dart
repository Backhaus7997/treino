// T40 RED — SCENARIO-554, 558, 559, 563, 564
//
// The AccountDeletionNotifier is an AsyncNotifier<void> that:
//   - Opens ReAuthBottomSheet to get an AuthCredential? from user
//   - Calls AuthService.reauthenticate(credential)
//   - Calls AccountDeletionService.call(uid: uid)
//   - Calls AuthService.signOut()
//   - Emits AsyncData(null) on success, AsyncError on failure
//
// To test this without a full widget tree we inject:
//   - A fake showModalBottomSheet callback (simulating the sheet result)
//   - Mocked providers for AuthService, AccountDeletionService, FirebaseAuth

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/auth/data/auth_service.dart';
import 'package:treino/features/auth/domain/auth_failure.dart';
import 'package:treino/features/profile/application/account_deletion_notifier.dart';
import 'package:treino/features/profile/data/account_deletion_service.dart';

// --- Mocks ---
class MockAuthService extends Mock implements AuthService {}

class MockAccountDeletionService extends Mock
    implements AccountDeletionService {}

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUser extends Mock implements User {}

class FakeAuthCredential extends Fake implements AuthCredential {}

class FakeDeletionResult extends Fake implements DeletionResult {
  FakeDeletionResult({
    required this.status,
    this.deletedCollections = const [],
    this.errors = const [],
  });
  @override
  final String status;
  @override
  final List<String> deletedCollections;
  @override
  final List<String> errors;
}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeAuthCredential());
    // No fallback values needed beyond FakeAuthCredential
  });

  late MockAuthService mockAuthService;
  late MockAccountDeletionService mockDeletionService;
  late MockFirebaseAuth mockFirebaseAuth;
  late MockUser mockUser;

  setUp(() {
    mockAuthService = MockAuthService();
    mockDeletionService = MockAccountDeletionService();
    mockFirebaseAuth = MockFirebaseAuth();
    mockUser = MockUser();

    when(() => mockUser.uid).thenReturn('uid-test');
    when(() => mockFirebaseAuth.currentUser).thenReturn(mockUser);
  });

  /// Build a ProviderContainer with mocked dependencies and an
  /// [AccountDeletionNotifier] whose [openReAuthSheet] callback is injectable.
  ProviderContainer buildContainer({
    required Future<AuthCredential?> Function() sheetResult,
  }) {
    final container = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWithValue(mockAuthService),
        accountDeletionServiceProvider.overrideWithValue(mockDeletionService),
        firebaseAuthProvider.overrideWithValue(mockFirebaseAuth),
        accountDeletionNotifierProvider.overrideWith(
          () => AccountDeletionNotifier.withSheetOpener(sheetResult),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  // SCENARIO-564 initial state
  test('SCENARIO-564: initial state resolves to AsyncData(null)', () async {
    final container = buildContainer(sheetResult: () async => null);
    // Wait for the AsyncNotifier.build() to complete.
    await container.read(accountDeletionNotifierProvider.future);
    final state = container.read(accountDeletionNotifierProvider);
    expect(state, isA<AsyncData<void>>());
    expect(state.hasValue, isTrue);
  });

  // SCENARIO-559 cancelled
  test(
      'SCENARIO-559: when user cancels re-auth sheet (returns null), '
      'reauthenticate and CF are NOT called', () async {
    final container = buildContainer(sheetResult: () async => null);

    await container
        .read(accountDeletionNotifierProvider.notifier)
        .deleteAccount();

    verifyNever(() => mockAuthService.reauthenticate(any()));
    verifyNever(() => mockDeletionService.call(uid: any(named: 'uid')));
  });

  // SCENARIO-554 + SCENARIO-563 happy path.
  // QA-PRO-010: the re-auth sheet already re-authenticated before returning the
  // credential, so the notifier must NOT call reauthenticate again (a second
  // call consumes single-use OAuth tokens and can abort a confirmed deletion).
  // The notifier's job is CF-then-signOut.
  test(
      'SCENARIO-554 + SCENARIO-563: on valid credential the notifier calls CF '
      'then signOut WITHOUT a second reauthenticate; state becomes AsyncData',
      () async {
    final credential = FakeAuthCredential();
    final callOrder = <String>[];

    when(
      () => mockDeletionService.call(uid: any(named: 'uid')),
    ).thenAnswer((_) async {
      callOrder.add('cf');
      return FakeDeletionResult(
          status: 'success', deletedCollections: const ['users-auth']);
    });
    when(() => mockAuthService.signOut()).thenAnswer((_) async {
      callOrder.add('signOut');
    });

    final container = buildContainer(sheetResult: () async => credential);

    await container
        .read(accountDeletionNotifierProvider.notifier)
        .deleteAccount();

    expect(callOrder, ['cf', 'signOut']);
    verifyNever(() => mockAuthService.reauthenticate(any()));
    final state = container.read(accountDeletionNotifierProvider);
    expect(state, isA<AsyncData<void>>());
  });

  // SCENARIO-564 / partial → AsyncError
  test('SCENARIO-564: CF returns partial → state is AsyncError(deletionFailed)',
      () async {
    final credential = FakeAuthCredential();

    when(() => mockAuthService.reauthenticate(any())).thenAnswer((_) async {});
    when(() => mockDeletionService.call(uid: any(named: 'uid')))
        .thenAnswer((_) async => FakeDeletionResult(status: 'partial'));

    final container = buildContainer(sheetResult: () async => credential);

    await container
        .read(accountDeletionNotifierProvider.notifier)
        .deleteAccount();

    final state = container.read(accountDeletionNotifierProvider);
    expect(state, isA<AsyncError<void>>());
    expect(state.error, isA<AuthFailure>());
  });

  // SCENARIO-558: re-auth failure is now handled INSIDE the sheet — it is the
  // single re-auth point (QA-PRO-010). A failed re-auth makes the sheet show its
  // inline error and return null, which is covered by the null-credential test
  // above ("reauthenticate and CF are NOT called"). The notifier no longer
  // re-authenticates, so there is no notifier-level re-auth-failure path.

  // retry within 5 minutes skips re-auth
  test('retry within 5 min skips re-auth sheet and calls CF directly',
      () async {
    final credential = FakeAuthCredential();
    var sheetOpenCount = 0;

    when(() => mockAuthService.reauthenticate(any())).thenAnswer((_) async {});
    when(() => mockDeletionService.call(uid: any(named: 'uid'))).thenAnswer(
        (_) async => FakeDeletionResult(
            status: 'success', deletedCollections: const ['users-auth']));
    when(() => mockAuthService.signOut()).thenAnswer((_) async {});

    final container = buildContainer(sheetResult: () async {
      sheetOpenCount++;
      return credential;
    });

    // First call — opens sheet
    await container
        .read(accountDeletionNotifierProvider.notifier)
        .deleteAccount();
    expect(sheetOpenCount, 1);

    // Reset state to simulate retry scenario (CF failing after reauth)
    when(() => mockDeletionService.call(uid: any(named: 'uid'))).thenAnswer(
        (_) async => FakeDeletionResult(
            status: 'success', deletedCollections: const ['users-auth']));

    // Retry within 5 min — should NOT open sheet again
    await container.read(accountDeletionNotifierProvider.notifier).retry();

    // Sheet was opened only once (on first deleteAccount call)
    expect(sheetOpenCount, 1);
  });

  // REGRESSION: retry() must hold accountDeletionInFlightProvider true for the
  // full CF cascade window so the router defers the loggedIn=true + profile=null
  // → /profile-setup redirect (mirrors deleteAccount). Previously retry() never
  // set the flag, stranding the user mid-deletion on /profile-setup.
  test(
      'retry within 5 min sets accountDeletionInFlightProvider during CF '
      'and resets it after', () async {
    final credential = FakeAuthCredential();
    final cfGate = Completer<void>();
    bool? inFlightDuringCf;

    when(() => mockAuthService.reauthenticate(any())).thenAnswer((_) async {});
    when(() => mockAuthService.signOut()).thenAnswer((_) async {});

    final container = buildContainer(sheetResult: () async => credential);

    // First call establishes the fresh re-auth window.
    when(() => mockDeletionService.call(uid: any(named: 'uid'))).thenAnswer(
        (_) async => FakeDeletionResult(
            status: 'success', deletedCollections: const ['users-auth']));
    await container
        .read(accountDeletionNotifierProvider.notifier)
        .deleteAccount();
    expect(container.read(accountDeletionInFlightProvider), isFalse);

    // Retry: capture the flag value while the CF is mid-flight (gated).
    when(() => mockDeletionService.call(uid: any(named: 'uid')))
        .thenAnswer((_) async {
      inFlightDuringCf = container.read(accountDeletionInFlightProvider);
      await cfGate.future;
      return FakeDeletionResult(
          status: 'success', deletedCollections: const ['users-auth']);
    });

    final retryFuture =
        container.read(accountDeletionNotifierProvider.notifier).retry();

    // Let retry() run up to the gated CF call.
    await Future<void>.delayed(Duration.zero);
    expect(inFlightDuringCf, isTrue,
        reason: 'flag must be true while the CF cascade is in flight');

    cfGate.complete();
    await retryFuture;

    expect(container.read(accountDeletionInFlightProvider), isFalse,
        reason: 'flag must be reset after the cascade completes');
  });

  // SC-PSD-27..30: el mapeo de errores corre en deleteAccount Y en retry, y
  // contra lo que el servicio REALMENTE tira (AccountDeletionFailure$Server),
  // no contra una FirebaseFunctionsException que nunca llega hasta acá.
  group('mapeo de errores del callable (SC-PSD-27..30)', () {
    final casos = <String, (Object, Matcher)>{
      'permission-denied (servidor viejo rechaza al PF)': (
        const AccountDeletionFailure$Server(
          code: 'permission-denied',
          message: 'trainers cannot self-delete',
        ),
        isA<AuthFailure>().having(
          (f) => f.userMessage,
          'userMessage',
          const AuthFailure.deletionNotAllowed().userMessage,
        ),
      ),
      'permission-denied con recent-login': (
        const AccountDeletionFailure$Server(
          code: 'permission-denied',
          message: 'requires recent-login',
        ),
        isA<AuthFailure>().having(
          (f) => f.userMessage,
          'userMessage',
          const AuthFailure.requiresRecentLogin().userMessage,
        ),
      ),
      'unavailable (no se pudo cancelar la suscripción)': (
        const AccountDeletionFailure$Server(
          code: 'unavailable',
          message: 'No pudimos cancelar tu suscripción',
        ),
        isA<AuthFailure>().having(
          (f) => f.userMessage,
          'userMessage',
          const AuthFailure.subscriptionCancelFailed().userMessage,
        ),
      ),
      'unavailable como FirebaseFunctionsException cruda': (
        FirebaseFunctionsException(code: 'unavailable', message: 'x'),
        isA<AuthFailure>().having(
          (f) => f.userMessage,
          'userMessage',
          const AuthFailure.subscriptionCancelFailed().userMessage,
        ),
      ),
      'otro código': (
        const AccountDeletionFailure$Server(
          code: 'internal',
          message: 'boom',
        ),
        isA<AuthFailure>().having(
          (f) => f.userMessage,
          'userMessage',
          const AuthFailure.deletionFailed().userMessage,
        ),
      ),
      'error desconocido': (
        const AccountDeletionFailure$Unknown(),
        isA<AuthFailure>().having(
          (f) => f.userMessage,
          'userMessage',
          const AuthFailure.deletionFailed().userMessage,
        ),
      ),
    };

    for (final entry in casos.entries) {
      test('deleteAccount: ${entry.key}', () async {
        when(() => mockDeletionService.call(uid: any(named: 'uid')))
            .thenThrow(entry.value.$1);
        final container =
            buildContainer(sheetResult: () async => FakeAuthCredential());

        await container
            .read(accountDeletionNotifierProvider.notifier)
            .deleteAccount();

        final state = container.read(accountDeletionNotifierProvider);
        expect(state, isA<AsyncError<void>>());
        expect(state.error, entry.value.$2);
        expect(container.read(accountDeletionInFlightProvider), isFalse);
      });

      test('retry: ${entry.key}', () async {
        // Primer intento fresco para abrir la ventana de 5 min y que el retry
        // NO reabra el sheet de re-auth.
        when(() => mockDeletionService.call(uid: any(named: 'uid')))
            .thenAnswer((_) async => FakeDeletionResult(status: 'partial'));
        final container =
            buildContainer(sheetResult: () async => FakeAuthCredential());
        await container
            .read(accountDeletionNotifierProvider.notifier)
            .deleteAccount();

        when(() => mockDeletionService.call(uid: any(named: 'uid')))
            .thenThrow(entry.value.$1);
        await container.read(accountDeletionNotifierProvider.notifier).retry();

        final state = container.read(accountDeletionNotifierProvider);
        expect(state, isA<AsyncError<void>>());
        expect(state.error, entry.value.$2);
      });
    }
  });

  // Revisión: un requiresRecentLogin con la ventana de 5 min fresca hacía que
  // Reintentar se saltara la re-auth y repitiera el mismo error en loop.
  group('retry tras requiresRecentLogin', () {
    test('reabre la re-auth aunque la ventana de 5 min esté fresca', () async {
      var sheets = 0;
      final container = buildContainer(
        sheetResult: () async {
          sheets++;
          return FakeAuthCredential();
        },
      );
      when(() => mockDeletionService.call(uid: any(named: 'uid'))).thenThrow(
        const AccountDeletionFailure$Server(
          code: 'permission-denied',
          message: 'requires recent-login',
        ),
      );
      final notifier = container.read(accountDeletionNotifierProvider.notifier);
      await notifier.deleteAccount();
      expect(sheets, 1);

      await notifier.retry();

      expect(sheets, 2, reason: 'retry debe pasar por la re-auth');
    });
  });

  // Revisión: el sheet de re-auth se abre ANTES de AsyncLoading, o sea que un
  // segundo tap en ese tramo disparaba un segundo flujo.
  group('guarda anti doble tap', () {
    test('un segundo deleteAccount en vuelo es no-op', () async {
      var sheets = 0;
      final gate = Completer<AuthCredential?>();
      final container = buildContainer(
        sheetResult: () {
          sheets++;
          return gate.future;
        },
      );
      final notifier = container.read(accountDeletionNotifierProvider.notifier);

      final first = notifier.deleteAccount();
      await notifier.deleteAccount();
      await notifier.retry();

      expect(sheets, 1);
      expect(container.read(accountDeletionBusyProvider), isTrue);

      gate.complete(null);
      await first;
      expect(container.read(accountDeletionBusyProvider), isFalse);
    });

    test('libera el busy aunque el flujo falle', () async {
      when(() => mockDeletionService.call(uid: any(named: 'uid'))).thenThrow(
        const AccountDeletionFailure$Server(code: 'internal', message: 'x'),
      );
      final container =
          buildContainer(sheetResult: () async => FakeAuthCredential());
      await container
          .read(accountDeletionNotifierProvider.notifier)
          .deleteAccount();
      expect(container.read(accountDeletionBusyProvider), isFalse);
    });
  });

  group('estrategia de re-auth y sign-out inyectables (Coach Hub web)', () {
    ProviderContainer webContainer({
      required AccountDeletionReauth reauth,
      required Future<void> Function() signOut,
    }) {
      final container = ProviderContainer(
        overrides: [
          authServiceProvider.overrideWithValue(mockAuthService),
          accountDeletionServiceProvider.overrideWithValue(mockDeletionService),
          firebaseAuthProvider.overrideWithValue(mockFirebaseAuth),
          accountDeletionReauthProvider.overrideWithValue(reauth),
          accountDeletionSignOutProvider.overrideWithValue(signOut),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    void stubCfOk() {
      when(() => mockDeletionService.call(uid: any(named: 'uid'))).thenAnswer(
        (_) async => FakeDeletionResult(
          status: 'success',
          deletedCollections: const ['users-auth'],
        ),
      );
    }

    test(
        'con estrategia: re-auth -> CF -> sign-out inyectado, y NUNCA '
        'AuthService.signOut (se cuelga en web)', () async {
      final order = <String>[];
      stubCfOk();
      final container = webContainer(
        reauth: (_) async {
          order.add('reauth');
          return true;
        },
        signOut: () async => order.add('signOut'),
      );

      await container
          .read(accountDeletionNotifierProvider.notifier)
          .deleteAccount();

      expect(order, ['reauth', 'signOut']);
      verify(() => mockDeletionService.call(uid: 'uid-test')).called(1);
      verifyNever(() => mockAuthService.signOut());
      expect(container.read(accountDeletedFlagProvider), isTrue);
    });

    test('estrategia devuelve false (cancelo): no llama al CF', () async {
      final container = webContainer(
        reauth: (_) async => false,
        signOut: () async {},
      );

      await container
          .read(accountDeletionNotifierProvider.notifier)
          .deleteAccount();

      verifyNever(() => mockDeletionService.call(uid: any(named: 'uid')));
      expect(container.read(accountDeletedFlagProvider), isFalse);
    });

    test('estrategia tira AuthFailure: queda en AsyncError, sin CF', () async {
      final container = webContainer(
        reauth: (_) async => throw const AuthFailure.popupBlocked(),
        signOut: () async {},
      );

      await container
          .read(accountDeletionNotifierProvider.notifier)
          .deleteAccount();

      final state = container.read(accountDeletionNotifierProvider);
      expect(state.error, const AuthFailure.popupBlocked());
      verifyNever(() => mockDeletionService.call(uid: any(named: 'uid')));
      expect(container.read(accountDeletionBusyProvider), isFalse);
    });
  });
}
