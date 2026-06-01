// T42 RED — SCENARIO-555, 556, 557, 559
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/data/auth_service.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/profile/presentation/widgets/re_auth_bottom_sheet.dart';

import '../../../../helpers/test_app_wrapper.dart';

// --- Mocks ---
class MockAuthService extends Mock implements AuthService {}

Widget _buildWithProvider({
  required String providerId,
  required MockAuthService authService,
}) {
  return ProviderScope(
    overrides: [
      authServiceProvider.overrideWithValue(authService),
    ],
    child: TestAppWrapper(
      child: ReAuthBottomSheet(providerId: providerId),
    ),
  );
}

void main() {
  late MockAuthService mockAuthService;

  setUp(() {
    mockAuthService = MockAuthService();
  });

  // SCENARIO-555
  testWidgets(
      'SCENARIO-555: renders password input when providerId is "password"',
      (tester) async {
    await tester.pumpWidget(
      _buildWithProvider(
        providerId: 'password',
        authService: mockAuthService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Continuar con Google'), findsNothing);
    expect(find.text('Continuar con Apple'), findsNothing);
  });

  // SCENARIO-556
  testWidgets(
      'SCENARIO-556: renders Google re-auth button when providerId is "google.com"',
      (tester) async {
    await tester.pumpWidget(
      _buildWithProvider(
        providerId: 'google.com',
        authService: mockAuthService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Continuar con Google'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Continuar con Apple'), findsNothing);
  });

  // SCENARIO-557
  testWidgets(
      'SCENARIO-557: renders Apple re-auth button when providerId is "apple.com"',
      (tester) async {
    await tester.pumpWidget(
      _buildWithProvider(
        providerId: 'apple.com',
        authService: mockAuthService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Continuar con Apple'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Continuar con Google'), findsNothing);
  });

  // SCENARIO-559: Cancel button present and pops with null
  testWidgets('Cancel button is present in all branches (password variant)',
      (tester) async {
    await tester.pumpWidget(
      _buildWithProvider(
        providerId: 'password',
        authService: mockAuthService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('CANCELAR'), findsOneWidget);
  });
}
