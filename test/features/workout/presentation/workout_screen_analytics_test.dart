// Issue #666 — que Entrenar esté REALMENTE instrumentado.
//
// `sub_tab_analytics_test.dart` prueba el widget aislado. Este prueba el
// cableado: que `_AthleteWorkout` lo tenga puesto, con la superficie y los
// slugs correctos. Sin este test alguien podría borrar el wrapper de
// `workout_screen.dart` y toda la suite seguiría verde mientras el dato
// desaparece en silencio — que es exactamente el modo de falla que originó la
// issue.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/analytics/analytics_service.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/application/user_routines_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/workout_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../../helpers/fake_analytics_service.dart';

final DateTime _kDate = DateTime.utc(2026, 1, 1);

UserProfile _athlete() => UserProfile(
      uid: 'test-uid',
      email: 'a@example.com',
      displayName: 'sporty',
      role: UserRole.athlete,
      createdAt: _kDate,
      updatedAt: _kDate,
    );

Future<void> _pumpWorkout(
  WidgetTester tester,
  FakeAnalyticsService analytics, {
  String? initialTab,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        analyticsServiceProvider.overrideWithValue(analytics),
        currentUidProvider.overrideWithValue('test-uid'),
        userProfileProvider.overrideWith((ref) => Stream.value(_athlete())),
        sessionsByUidProvider.overrideWith((ref, uid) async => []),
        authStateChangesProvider.overrideWith((ref) => const Stream.empty()),
        currentAthleteLinkProvider.overrideWith((ref) async => null),
        assignedRoutinesProvider('test-uid').overrideWith((ref) async => []),
        userCreatedRoutinesProvider('test-uid')
            .overrideWith((ref) => Stream.value(const <Routine>[])),
        // Sin esto EXPLORAR queda en spinner y nada asienta.
        routinesProvider.overrideWith((ref) async => <Routine>[]),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(
          body: SizedBox(
            height: 800,
            child: WorkoutScreen(initialTab: initialTab),
          ),
        ),
      ),
    ),
  );
  // pump() explícito y NO pumpAndSettle: las secciones usan TreinoFadeSlideIn
  // y el settle nunca llega. Mismo patrón que workout_screen_test.dart.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// Deja que la animación del TabBarView termine sin pedir un settle global.
Future<void> _settleTabs(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late FakeAnalyticsService analytics;

  setUp(() => analytics = FakeAnalyticsService());

  group('Entrenar — analytics de sub-navegación', () {
    testWidgets('al abrir /workout se cuenta TU ENTRENO', (tester) async {
      await _pumpWorkout(tester, analytics);

      expect(analytics.subTabsFor('workout'), ['tu-entreno']);
    });

    testWidgets('entrar por ?tab=plantillas cuenta esa página, no TU ENTRENO',
        (tester) async {
      await _pumpWorkout(tester, analytics, initialTab: 'plantillas');

      // El deep-link es la mitad del uso que la issue quiere medir.
      expect(analytics.subTabsFor('workout'), ['plantillas']);
    });

    testWidgets('cambiar de pill cuenta la página nueva', (tester) async {
      await _pumpWorkout(tester, analytics);

      await tester.tap(find.text('EXPLORAR'));
      await _settleTabs(tester);

      expect(analytics.subTabsFor('workout'), ['tu-entreno', 'plantillas']);
    });

    testWidgets('cambiar por SWIPE también cuenta', (tester) async {
      await _pumpWorkout(tester, analytics);

      // El pill es swipeable a propósito. Si el evento colgara del `onTap`
      // del TabBar, este gesto no dejaría rastro.
      await tester.drag(find.byType(TabBarView), const Offset(-500, 0));
      await _settleTabs(tester);

      expect(analytics.subTabsFor('workout'), ['tu-entreno', 'plantillas']);
    });

    testWidgets('el slug NO es el label visible', (tester) async {
      await _pumpWorkout(tester, analytics, initialTab: 'plantillas');

      // Esto dejó de ser hipótesis: #638 renombró el tab a "EXPLORAR" mientras
      // esta rama esperaba. El label visible cambió y el slug no se movió, que
      // es exactamente para lo que se separaron. Si el evento mandara el label,
      // la serie histórica ya estaría partida en dos.
      expect(analytics.subTabsFor('workout'), isNot(contains('EXPLORAR')));
      expect(analytics.subTabsFor('workout'), isNot(contains('PLANTILLAS')));
      expect(analytics.subTabsFor('workout'), ['plantillas']);
    });
  });
}
