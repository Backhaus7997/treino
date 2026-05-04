import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/auth/domain/auth_failure.dart';
import 'package:treino/features/auth/presentation/register_screen.dart';
import 'package:treino/features/auth/presentation/widgets/auth_primary_button.dart';

class MockUser extends Mock implements User {}

class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier({User? initialUser}) : _initialUser = initialUser;

  final User? _initialUser;
  Future<void> Function(String email, String password)? onSignUp;

  @override
  Future<User?> build() async => _initialUser;

  @override
  Future<void> signUp({required String email, required String password}) async {
    if (onSignUp != null) await onSignUp!(email, password);
  }
}

GoRouter _makeRouter(Widget home) => GoRouter(
      initialLocation: '/register',
      routes: [
        GoRoute(path: '/register', builder: (_, __) => home),
        GoRoute(
          path: '/home',
          builder: (_, __) => const Scaffold(body: Text('HOME')),
        ),
        GoRoute(
          path: '/login',
          builder: (_, __) => const Scaffold(body: Text('LOGIN')),
        ),
      ],
    );

Widget _buildApp({required _TestAuthNotifier notifier}) {
  const screen = RegisterScreen();
  final router = _makeRouter(screen);
  return ProviderScope(
    overrides: [authNotifierProvider.overrideWith(() => notifier)],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  late MockUser mockUser;

  setUp(() {
    mockUser = MockUser();
    when(() => mockUser.emailVerified).thenReturn(false);
  });

  // ---------------------------------------------------------------------------
  // REQ-AUTH-001: exactly 3 fields
  // ---------------------------------------------------------------------------
  testWidgets('REQ-AUTH-001 — exactly 3 fields rendered', (tester) async {
    await tester.pumpWidget(_buildApp(notifier: _TestAuthNotifier()));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(3));
  });

  // ---------------------------------------------------------------------------
  // REQ-AUTH-002: submit disabled when fields empty
  // ---------------------------------------------------------------------------
  testWidgets('submit disabled with empty fields', (tester) async {
    await tester.pumpWidget(_buildApp(notifier: _TestAuthNotifier()));
    await tester.pumpAndSettle();
    final btn = tester.widget<ElevatedButton>(
      find.descendant(
        of: find.byType(AuthPrimaryButton),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(btn.onPressed, isNull);
  });

  // ---------------------------------------------------------------------------
  // Scenario 1.1: happy path → /home
  // ---------------------------------------------------------------------------
  testWidgets('scenario 1.1 — happy path navigates to /home', (tester) async {
    final notifier = _TestAuthNotifier();
    notifier.onSignUp = (email, password) async {
      notifier.state = AsyncData(mockUser);
    };

    await tester.pumpWidget(_buildApp(notifier: notifier));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'test@example.com');
    await tester.enterText(fields.at(1), 'Pass1234');
    await tester.enterText(fields.at(2), 'Pass1234');
    await tester.pump();

    await tester.tap(find.byType(AuthPrimaryButton));
    await tester.pumpAndSettle();

    expect(find.text('HOME'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // Scenario 2.1: invalid email validation
  // ---------------------------------------------------------------------------
  testWidgets('scenario 2.1 — invalid email shows validation message',
      (tester) async {
    await tester.pumpWidget(_buildApp(notifier: _TestAuthNotifier()));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'not-an-email');
    await tester.enterText(fields.at(1), 'Pass1234');
    await tester.enterText(fields.at(2), 'Pass1234');
    await tester.pump();

    // Try to submit to trigger validation
    await tester.tap(find.byType(AuthPrimaryButton));
    await tester.pump();

    expect(find.text('El email no es válido'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // Scenario 3.1: too short password
  // ---------------------------------------------------------------------------
  testWidgets('scenario 3.1 — short password shows validation message',
      (tester) async {
    await tester.pumpWidget(_buildApp(notifier: _TestAuthNotifier()));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'test@example.com');
    await tester.enterText(fields.at(1), 'abc123'); // < 8 chars
    await tester.enterText(fields.at(2), 'abc123');
    await tester.pump();

    await tester.tap(find.byType(AuthPrimaryButton));
    await tester.pump();

    expect(
      find.text(
        'La contraseña debe tener al menos 8 caracteres, una letra y un número',
      ),
      findsWidgets,
    );
  });

  // ---------------------------------------------------------------------------
  // Scenario 3.2: password without numbers
  // ---------------------------------------------------------------------------
  testWidgets('scenario 3.2 — password without numbers shows validation',
      (tester) async {
    await tester.pumpWidget(_buildApp(notifier: _TestAuthNotifier()));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'test@example.com');
    await tester.enterText(fields.at(1), 'abcdefgh'); // no numbers
    await tester.enterText(fields.at(2), 'abcdefgh');
    await tester.pump();

    await tester.tap(find.byType(AuthPrimaryButton));
    await tester.pump();

    expect(
      find.text(
        'La contraseña debe tener al menos 8 caracteres, una letra y un número',
      ),
      findsWidgets,
    );
  });

  // ---------------------------------------------------------------------------
  // Scenario 3.3: password without letters
  // ---------------------------------------------------------------------------
  testWidgets('scenario 3.3 — password without letters shows validation',
      (tester) async {
    await tester.pumpWidget(_buildApp(notifier: _TestAuthNotifier()));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'test@example.com');
    await tester.enterText(fields.at(1), '12345678'); // no letters
    await tester.enterText(fields.at(2), '12345678');
    await tester.pump();

    await tester.tap(find.byType(AuthPrimaryButton));
    await tester.pump();

    expect(
      find.text(
        'La contraseña debe tener al menos 8 caracteres, una letra y un número',
      ),
      findsWidgets,
    );
  });

  // ---------------------------------------------------------------------------
  // Scenario 4.1: passwords don't match
  // ---------------------------------------------------------------------------
  testWidgets('scenario 4.1 — passwords mismatch shows validation message',
      (tester) async {
    await tester.pumpWidget(_buildApp(notifier: _TestAuthNotifier()));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'test@example.com');
    await tester.enterText(fields.at(1), 'Pass1234');
    await tester.enterText(fields.at(2), 'Pass5678'); // mismatch
    await tester.pump();

    await tester.tap(find.byType(AuthPrimaryButton));
    await tester.pump();

    expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // Scenario 5.1: email already in use → banner
  // ---------------------------------------------------------------------------
  testWidgets('scenario 5.1 — email-already-in-use shows error banner',
      (tester) async {
    final notifier = _TestAuthNotifier();
    notifier.onSignUp = (email, password) async {
      notifier.state = const AsyncError(
        AuthFailure.emailAlreadyInUse(),
        StackTrace.empty,
      );
    };

    await tester.pumpWidget(_buildApp(notifier: notifier));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'existing@example.com');
    await tester.enterText(fields.at(1), 'Pass1234');
    await tester.enterText(fields.at(2), 'Pass1234');
    await tester.pump();

    await tester.tap(find.byType(AuthPrimaryButton));
    await tester.pumpAndSettle();

    expect(find.text('Ya existe una cuenta con ese email'), findsOneWidget);
  });
}
