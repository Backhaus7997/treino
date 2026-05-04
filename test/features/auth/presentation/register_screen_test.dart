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
import 'package:treino/features/auth/presentation/widgets/auth_pill_button.dart';
import 'package:treino/features/auth/presentation/widgets/auth_secondary_button.dart';
import 'package:treino/features/auth/presentation/widgets/password_strength_bar.dart';
import 'package:treino/features/auth/presentation/widgets/terms_checkbox.dart';

class MockUser extends Mock implements User {}

class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier({User? initialUser}) : _initialUser = initialUser;

  final User? _initialUser;
  Future<void> Function(String email, String password, {String? displayName})?
      onSignUp;

  @override
  Future<User?> build() async => _initialUser;

  @override
  Future<void> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    if (onSignUp != null) {
      await onSignUp!(email, password, displayName: displayName);
    }
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
  // REQ-AUTH-001 (rework): exactly 3 fields — name, email, password
  // ---------------------------------------------------------------------------
  testWidgets('REQ-AUTH-001 — exactly 3 fields rendered (name/email/password)',
      (tester) async {
    await tester.pumpWidget(_buildApp(notifier: _TestAuthNotifier()));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(3));
  });

  // ---------------------------------------------------------------------------
  // PasswordStrengthBar is visible
  // ---------------------------------------------------------------------------
  testWidgets('PasswordStrengthBar is rendered', (tester) async {
    await tester.pumpWidget(_buildApp(notifier: _TestAuthNotifier()));
    await tester.pumpAndSettle();
    expect(find.byType(PasswordStrengthBar), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // TermsCheckbox is visible
  // ---------------------------------------------------------------------------
  testWidgets('TermsCheckbox is rendered', (tester) async {
    await tester.pumpWidget(_buildApp(notifier: _TestAuthNotifier()));
    await tester.pumpAndSettle();
    expect(find.byType(TermsCheckbox), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // Google and Apple buttons are disabled
  // ---------------------------------------------------------------------------
  testWidgets('Google and Apple social buttons are present and disabled',
      (tester) async {
    await tester.pumpWidget(_buildApp(notifier: _TestAuthNotifier()));
    await tester.pumpAndSettle();

    expect(find.byType(AuthSecondaryButton), findsNWidgets(2));
    final buttons =
        tester.widgetList<OutlinedButton>(find.byType(OutlinedButton)).toList();
    expect(buttons.every((b) => b.onPressed == null), isTrue);
  });

  // ---------------------------------------------------------------------------
  // REQ-AUTH-002: submit disabled when fields empty
  // ---------------------------------------------------------------------------
  testWidgets('submit disabled with empty fields', (tester) async {
    await tester.pumpWidget(_buildApp(notifier: _TestAuthNotifier()));
    await tester.pumpAndSettle();
    final btn = tester.widget<ElevatedButton>(
      find.descendant(
        of: find.byType(AuthPillButton),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(btn.onPressed, isNull);
  });

  // ---------------------------------------------------------------------------
  // CTA disabled until terms accepted
  // ---------------------------------------------------------------------------
  testWidgets('CTA disabled until terms checkbox is checked', (tester) async {
    await tester.pumpWidget(_buildApp(notifier: _TestAuthNotifier()));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Ana Núñez');
    await tester.enterText(fields.at(1), 'test@example.com');
    await tester.enterText(fields.at(2), 'Pass1234');
    await tester.pump();

    // Terms not checked → CTA still disabled
    final btnBefore = tester.widget<ElevatedButton>(
      find.descendant(
        of: find.byType(AuthPillButton),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(btnBefore.onPressed, isNull);

    // Tap the checkbox
    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    // Now CTA should be enabled
    final btnAfter = tester.widget<ElevatedButton>(
      find.descendant(
        of: find.byType(AuthPillButton),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(btnAfter.onPressed, isNotNull);
  });

  // ---------------------------------------------------------------------------
  // Scenario 1.1: happy path → /home
  // ---------------------------------------------------------------------------
  testWidgets('scenario 1.1 — happy path navigates to /home', (tester) async {
    final notifier = _TestAuthNotifier();
    notifier.onSignUp = (email, password, {String? displayName}) async {
      notifier.state = AsyncData(mockUser);
    };

    await tester.pumpWidget(_buildApp(notifier: notifier));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Ana Núñez');
    await tester.enterText(fields.at(1), 'test@example.com');
    await tester.enterText(fields.at(2), 'Pass1234');
    await tester.pump();

    // Accept terms
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    await tester.ensureVisible(find.byType(AuthPillButton));
    await tester.tap(find.byType(AuthPillButton));
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
    await tester.enterText(fields.at(0), 'Ana Núñez');
    await tester.enterText(fields.at(1), 'not-an-email');
    await tester.enterText(fields.at(2), 'Pass1234');
    await tester.pump();

    // Accept terms then submit to trigger validation
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.ensureVisible(find.byType(AuthPillButton));
    await tester.tap(find.byType(AuthPillButton));
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
    await tester.enterText(fields.at(0), 'Ana Núñez');
    await tester.enterText(fields.at(1), 'test@example.com');
    await tester.enterText(fields.at(2), 'abc123'); // < 8 chars
    await tester.pump();

    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.ensureVisible(find.byType(AuthPillButton));
    await tester.tap(find.byType(AuthPillButton));
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
    await tester.enterText(fields.at(0), 'Ana Núñez');
    await tester.enterText(fields.at(1), 'test@example.com');
    await tester.enterText(fields.at(2), 'abcdefgh'); // no numbers
    await tester.pump();

    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.ensureVisible(find.byType(AuthPillButton));
    await tester.tap(find.byType(AuthPillButton));
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
    await tester.enterText(fields.at(0), 'Ana Núñez');
    await tester.enterText(fields.at(1), 'test@example.com');
    await tester.enterText(fields.at(2), '12345678'); // no letters
    await tester.pump();

    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.ensureVisible(find.byType(AuthPillButton));
    await tester.tap(find.byType(AuthPillButton));
    await tester.pump();

    expect(
      find.text(
        'La contraseña debe tener al menos 8 caracteres, una letra y un número',
      ),
      findsWidgets,
    );
  });

  // ---------------------------------------------------------------------------
  // Scenario 5.1: email already in use → banner
  // ---------------------------------------------------------------------------
  testWidgets('scenario 5.1 — email-already-in-use shows error banner',
      (tester) async {
    final notifier = _TestAuthNotifier();
    notifier.onSignUp = (email, password, {String? displayName}) async {
      notifier.state = const AsyncError(
        AuthFailure.emailAlreadyInUse(),
        StackTrace.empty,
      );
    };

    await tester.pumpWidget(_buildApp(notifier: notifier));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Ana Núñez');
    await tester.enterText(fields.at(1), 'existing@example.com');
    await tester.enterText(fields.at(2), 'Pass1234');
    await tester.pump();

    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.ensureVisible(find.byType(AuthPillButton));
    await tester.tap(find.byType(AuthPillButton));
    await tester.pumpAndSettle();

    expect(find.text('Ya existe una cuenta con ese email'), findsOneWidget);
  });
}
