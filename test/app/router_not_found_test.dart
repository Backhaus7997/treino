// QA-NAV-002: una ruta desconocida (o deep-link malformado) para un usuario
// autenticado debe renderizar la NotFoundScreen propia (404 con branding) en
// lugar de la pantalla de error roja default de go_router.

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
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Fecha de nacimiento de un adulto.
///
/// Todo test que monte el router REAL con un usuario logueado la necesita:
/// `authRedirect` tiene un gate de edad mínima que manda a `/birth-date`
/// cuando `bornAt` falta o no llega al piso, así que un perfil "completo" sin
/// este campo nunca llega a la pantalla que el test quiere medir.
final _adultBornAt = DateTime.utc(1990, 5, 20);

class _MockUser extends Mock implements User {}

class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._fixedState);
  final AsyncValue<User?> _fixedState;

  @override
  Future<User?> build() async {
    state = _fixedState;
    return _fixedState.valueOrNull;
  }
}

final DateTime _kDate = DateTime.utc(2026, 1, 1);

UserProfile _athleteProfile() => UserProfile(
      uid: 'u1',
      email: 'athlete@example.com',
      displayName: 'sporty',
      bornAt: _adultBornAt,
      role: UserRole.athlete,
      createdAt: _kDate,
      updatedAt: _kDate,
    );

void main() {
  testWidgets(
      'QA-NAV-002: unknown route renders NotFoundScreen, not the go_router default',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        authNotifierProvider.overrideWith(
          () => _StubAuthNotifier(AsyncData(_MockUser())),
        ),
        userProfileProvider.overrideWith(
          (ref) => Stream<UserProfile?>.value(_athleteProfile()),
        ),
        authStateChangesProvider.overrideWith((_) => Stream.value(null)),
        currentUidProvider.overrideWithValue('u1'),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authNotifierProvider.future);
    await container.read(userProfileProvider.future);

    final router = buildRouter(
      refreshListenable: ValueNotifier<int>(0),
      read: container.read,
    );
    router.go('/ruta-inexistente-xyz');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.dark(),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NotFoundScreen), findsOneWidget);
  });
}
