// QA H3 (cola): la card de identidad del perfil del PF mostraba el stat
// ALUMNOS con `'$activeAlumnos'` sobre `linksAsync.valueOrNull ?? []` — un
// fallo de lectura colapsaba a "0 alumnos" (un stat falso). Ahora, ante error,
// el stat muestra "—" (desconocido), igual que el stat RATING ya lo hace.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_discovery_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
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

TrainerLink _activeLink(String id) => TrainerLink(
      id: id,
      trainerId: 'trainer-uid',
      athleteId: 'athlete-$id',
      status: TrainerLinkStatus.active,
      requestedAt: DateTime(2026, 1, 1),
    );

Widget _wrap({required Override linksOverride}) => ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue('trainer-uid'),
        userProfileProvider
            .overrideWith((_) => Stream.value(_trainerProfile())),
        linksOverride,
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
  testWidgets('active links → ALUMNOS shows the real count', (tester) async {
    await tester.pumpWidget(_wrap(
      linksOverride: trainerLinksStreamProvider.overrideWith(
        (_) => Stream.value([_activeLink('l1'), _activeLink('l2')]),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('ALUMNOS'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('links error → ALUMNOS shows "—", never a false "0"',
      (tester) async {
    await tester.pumpWidget(_wrap(
      linksOverride: trainerLinksStreamProvider.overrideWith(
        (_) => Stream<List<TrainerLink>>.error(Exception('boom')),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('ALUMNOS'), findsOneWidget);
    // ALUMNOS + RATING both read "—" (unknown) on this path.
    expect(find.text('—'), findsWidgets);
    // The stat must never claim "0 alumnos" when the read simply failed.
    expect(find.text('0'), findsNothing);
  });
}
