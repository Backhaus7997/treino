// La ruta del import de PDF en el router REAL: `/workout/import-pdf/:id`
// monta la pantalla de subida con el alumno del path.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/not_found_screen.dart';
import 'package:treino/app/router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/coach/presentation/plan_pdf_import_upload_screen.dart';
import 'package:treino/features/coach_hub/application/pdf_import_quota_provider.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../helpers/mail_test_helpers.dart';

class _MockUser extends Mock implements User {}

class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<User?> build() async {
    final user = _MockUser();
    state = AsyncData(user);
    return user;
  }
}

UserProfile _profile() => UserProfile(
      uid: 'u1',
      email: 'athlete@example.com',
      displayName: 'sporty',
      bornAt: DateTime.utc(1990, 5, 20),
      emailVerification:
          mailConfirmadoPara(UserRole.athlete, 'athlete@example.com'),
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

Future<void> _go(WidgetTester tester, String location) async {
  final container = ProviderContainer(overrides: [
    authNotifierProvider.overrideWith(_StubAuthNotifier.new),
    userProfileProvider.overrideWith((ref) => Stream.value(_profile())),
    authStateChangesProvider.overrideWith((_) => Stream.value(null)),
    currentUidProvider.overrideWithValue('u1'),
    pdfImportRemainingProvider.overrideWithValue(null),
  ]);
  addTearDown(container.dispose);
  await container.read(authNotifierProvider.future);
  await container.read(userProfileProvider.future);

  final router = buildRouter(
      refreshListenable: ValueNotifier<int>(0), read: container.read);
  router.go(location);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('/workout/import-pdf/:athleteId monta la subida de ese alumno',
      (tester) async {
    await _go(tester, '/workout/import-pdf/ath-42');

    final screen = tester.widget<PlanPdfImportUploadScreen>(
        find.byType(PlanPdfImportUploadScreen));
    expect(screen.athleteId, 'ath-42');
    expect(planPdfImportPath('ath-42'), '/workout/import-pdf/ath-42');
  });

  testWidgets('sin alumno en el path no matchea (control)', (tester) async {
    await _go(tester, '/workout/import-pdf');

    expect(find.byType(PlanPdfImportUploadScreen), findsNothing);
    expect(find.byType(NotFoundScreen), findsOneWidget);
  });
}
