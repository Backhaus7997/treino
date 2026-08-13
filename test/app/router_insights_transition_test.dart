// Smoke de navegación de las 5 rutas de insights, que usan
// `pageBuilder: _report(...)` — ahora una CupertinoPageRoute (slide nativo +
// gesto de swipe-back) con un fade encima. El swipe-back se había perdido
// cuando _report era un CustomTransitionPage (TREINO Motion PR3); se restauró
// extendiendo CupertinoPageRoute (opción B).
//
// Verifica que cada ruta monta su pantalla a través de la transición sin
// excepciones, que el pop vuelve bien, y que la transición nativa de Cupertino
// (que aporta el back-gesture) está presente — un CustomTransitionPage NO
// produciría un CupertinoPageTransition.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
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

      // Swipe-back: la ruta es una CupertinoPageRoute (opción B) → produce un
      // CupertinoPageTransition, que trae el back-gesture. El viejo _report
      // (CustomTransitionPage) no lo producía.
      expect(find.byType(CupertinoPageTransition), findsWidgets,
          reason: '${entry.key} debe usar la transición nativa de Cupertino '
              '(swipe-back)');
      final route = ModalRoute.of(tester.element(find.byType(entry.value)))!;
      expect(route, isA<CupertinoRouteTransitionMixin>(),
          reason: '${entry.key} debe ser una ruta Cupertino con back-gesture');
      expect((route as CupertinoRouteTransitionMixin).popGestureEnabled, isTrue,
          reason: 'el gesto de volver-deslizando debe estar habilitado en '
              '${entry.key}');

      // Pop: reverse transition.
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
