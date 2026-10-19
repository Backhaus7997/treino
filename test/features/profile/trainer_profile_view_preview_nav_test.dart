// #1498 (a) — VER PREVIEW abre la gemela /profile/trainer-preview/:uid y no
// /coach/trainer/:uid: bajo /coach la barra inferior saltaba a COACH aunque el
// PF viniera de PERFIL. (Que esa ruta mantenga PERFIL resaltado se testea
// contra el router real en `test/app/router_tab_highlight_test.dart`.)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_discovery_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_public_profile.dart';
import 'package:treino/features/notifications/application/notification_router.dart'
    show locationActualDe;
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/trainer_profile_view.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

const _uid = 'trainer-uid';

void main() {
  testWidgets('VER PREVIEW hace push a la gemela bajo /profile',
      (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: TrainerProfileView()),
        ),
        GoRoute(
          path: '/profile/trainer-preview/:uid',
          builder: (_, state) => Scaffold(
            body: Text('PREVIEW ${state.pathParameters['uid']}'),
          ),
        ),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue(_uid),
        userProfileProvider.overrideWith(
          (_) => Stream.value(UserProfile(
            uid: _uid,
            email: 'pf@test.com',
            displayName: 'Coach Ana',
            role: UserRole.trainer,
            createdAt: DateTime(2025),
            updatedAt: DateTime(2025),
          )),
        ),
        trainerLinksStreamProvider.overrideWith((_) => Stream.value(const [])),
        // Perfil público creado → VER PREVIEW habilitado.
        trainerByIdProvider(_uid).overrideWith(
          (_) async => const TrainerPublicProfile(uid: _uid),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        routerConfig: router,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('VER PREVIEW'));
    await tester.pumpAndSettle();

    expect(locationActualDe(router), '/profile/trainer-preview/$_uid');
    expect(find.text('PREVIEW $_uid'), findsOneWidget);
  });
}
