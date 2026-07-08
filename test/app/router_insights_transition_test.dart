// TREINO Motion PR3 — smoke de navegación de las 5 rutas de insights que
// migraron de `builder:` (default de plataforma) a `pageBuilder: _report(...)`
// (CustomTransitionPage con fade + subida sutil, duración AppMotion.slow).
//
// Verifica que cada ruta monta su pantalla a través de la transición custom
// sin excepciones, y que el pop (reverse transition con curva exit) vuelve
// bien. No valida el "feel" — eso es de los widget tests de los motion
// widgets y del ojo humano en device.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/insights/presentation/frequent_exercises_screen.dart';
import 'package:treino/features/insights/presentation/insights_screen.dart';
import 'package:treino/features/insights/presentation/monthly_report_screen.dart';
import 'package:treino/features/insights/presentation/muscle_distribution_screen.dart';
import 'package:treino/features/insights/presentation/volume_by_group_screen.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/l10n/app_l10n.dart';

class _MockUser extends Mock implements User {}

class _MockSessionRepository extends Mock implements SessionRepository {}

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
      role: UserRole.athlete,
      createdAt: _kDate,
      updatedAt: _kDate,
    );

void main() {
  testWidgets(
      'las 5 rutas de insights montan su pantalla vía la transición _report '
      'y el pop reverso no explota', (tester) async {
    final repo = _MockSessionRepository();
    // Sin sesiones: todas las pantallas renderizan su estado vacío estable —
    // suficiente para el smoke de navegación/transición.
    when(() => repo.listByUid('u1')).thenAnswer((_) async => []);

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
        sessionRepositoryProvider.overrideWithValue(repo),
        exercisesProvider.overrideWith((_) async => const []),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authNotifierProvider.future);
    await container.read(userProfileProvider.future);

    final router = buildRouter(
      refreshListenable: ValueNotifier<int>(0),
      read: container.read,
    );
    router.go('/home/insights');

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

    expect(find.byType(InsightsScreen), findsOneWidget);

    const detailRoutes = <String, Type>{
      '/home/insights/monthly': MonthlyReportScreen,
      '/home/insights/muscle-distribution': MuscleDistributionScreen,
      '/home/insights/frequent-exercises': FrequentExercisesScreen,
      '/home/insights/volume-by-group': VolumeByGroupScreen,
    };

    for (final entry in detailRoutes.entries) {
      router.push(entry.key);
      // Atraviesa la transición custom (AppMotion.slow = 320ms) frame a
      // frame — un throw en el transitionsBuilder reventaría acá.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'la transición _report de ${entry.key} no debe tirar');
      // OJO: no se asserta `currentConfiguration.uri` — para pushes
      // imperativos go_router 14.x reporta la uri BASE (por eso el test de
      // transición iOS tampoco la asserta en su caso de push). El smoke
      // real es que la pantalla montó a través de la transición custom.
      expect(find.byType(entry.value), findsOneWidget,
          reason: '${entry.key} debe montar ${entry.value}');

      // Pop: reverse transition (reverseTransitionDuration + curva exit).
      router.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'el pop de ${entry.key} no debe tirar');
      expect(find.byType(entry.value), findsNothing,
          reason: 'el detalle debe desmontarse tras el pop');
      expect(find.byType(InsightsScreen), findsOneWidget,
          reason: 'después del pop se vuelve al hub');
    }
  });
}
