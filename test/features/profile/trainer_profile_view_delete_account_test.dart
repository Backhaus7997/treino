// Regresión de QA-PRO-001 (CRITICAL) — el rol trainer no tenía ningún entry
// point in-app para eliminar su cuenta (bloquea publicación iOS, Guideline
// 5.1.1(v)). El flujo de borrado (EliminarCuentaSheet → re-auth → CF
// deleteAccount) existe y es role-agnostic, pero solo era alcanzable desde el
// perfil de ATLETA. Este test verifica que TrainerProfileView ahora expone la
// fila "Eliminar cuenta".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_discovery_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/trainer_profile_view.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

UserProfile _trainerProfile() => UserProfile(
      uid: 'trainer-uid',
      email: 'pf@test.com',
      displayName: 'Coach Ana',
      role: UserRole.trainer,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
    );

Widget _wrap() => ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue('trainer-uid'),
        userProfileProvider.overrideWith((_) => Stream.value(_trainerProfile())),
        trainerLinksStreamProvider.overrideWith((_) => Stream.value(const [])),
        trainerByIdProvider('trainer-uid').overrideWith((_) async => null),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const Scaffold(body: TrainerProfileView()),
      ),
    );

void main() {
  testWidgets(
      'QA-PRO-001: el perfil de trainer expone la fila "Eliminar cuenta"',
      (tester) async {
    // Tall viewport so the whole menu ListView lays out its rows (the row sits
    // below "Cerrar sesión", off-screen in the default 600x800 test surface).
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    // El entry point de borrado de cuenta debe ser alcanzable para el trainer.
    expect(find.text('Eliminar cuenta'), findsOneWidget);
    // Sanity: sigue estando "Cerrar sesión" (no reemplazamos, agregamos).
    expect(find.text('Cerrar sesión'), findsOneWidget);
  });
}
