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
}
