// Rutas `/coach/nutricion` y `/coach/archivos` — el contenido que el PF carga
// y el alumno ahora sí ve.
//
// Los botones que llevan acá viven en `LinkStateCard`, que sólo se monta con
// un vínculo activo. Pero las rutas existen igual y hay que fijar su contrato:
//
//   - `/coach/nutricion` depende de DOS ids. El del alumno sale de la sesión;
//     el del PF, del vínculo. Sin vínculo, `trainerId` queda vacío y el doc
//     `nutrition_plans/_{athleteId}` no matchea ninguna rama del `allow read`:
//     la pantalla dispararía una query condenada a permission-denied y el
//     alumno leería "no pudimos cargar tu plan" cuando el problema real es que
//     no tiene PF. Por eso el host corta ANTES de montar la pantalla, y el
//     tercer test fija justamente eso.
//
//   - `/coach/archivos` NO depende del vínculo a propósito: el alumno ve lo
//     que le compartieron sin importar cuál de sus PFs se lo cargó, ni si ese
//     vínculo sigue vivo. Mismo criterio que MeasurementsScreen.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/coach/application/athlete_file_providers.dart';
import 'package:treino/features/coach/application/nutrition_plan_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/athlete_file.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach/presentation/athlete_files_screen.dart';
import 'package:treino/features/coach/presentation/athlete_nutrition_plan_screen.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../helpers/onboarding_test_helpers.dart';

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

const _athleteUid = 'a1';
const _trainerUid = 't1';
final DateTime _kDate = DateTime.utc(2026, 1, 1);

UserProfile _athleteProfile() => UserProfile(
      uid: _athleteUid,
      email: 'athlete@example.com',
      displayName: 'sporty',
      role: UserRole.athlete,
      createdAt: _kDate,
      updatedAt: _kDate,
      // No es un test de onboarding — que las cards del tour no entren al
      // layout (mismo motivo que en router_coach_agenda_test).
      onboardingSeen: allSurfacesSeen(),
    );

TrainerLink _activeLink() => TrainerLink(
      id: '${_trainerUid}_$_athleteUid',
      trainerId: _trainerUid,
      athleteId: _athleteUid,
      status: TrainerLinkStatus.active,
      requestedAt: _kDate,
      acceptedAt: _kDate,
    );

Future<void> _pumpRoute(
  WidgetTester tester, {
  required String location,
  required TrainerLink? link,
}) async {
  final container = ProviderContainer(
    overrides: [
      authNotifierProvider.overrideWith(
        () => _StubAuthNotifier(AsyncData(_MockUser())),
      ),
      userProfileProvider.overrideWith(
        (ref) => Stream<UserProfile?>.value(_athleteProfile()),
      ),
      authStateChangesProvider.overrideWith((_) => Stream.value(null)),
      currentUidProvider.overrideWithValue(_athleteUid),
      currentAthleteLinkProvider.overrideWith((ref) async => link),
      // Las dos pantallas watchean Firestore apenas montan: sin estos
      // overrides el test pegaría contra la instancia real.
      nutritionPlanProvider.overrideWith((ref, key) => Stream.value(null)),
      sharedAthleteFilesProvider.overrideWith(
        (ref, id) => Stream.value(const <AthleteFile>[]),
      ),
      // Badges del shell (bottom nav).
      unreadFromCoachProvider.overrideWith((ref) => 0),
      unreadFromFriendsProvider.overrideWith((ref) => 0),
    ],
  );
  addTearDown(container.dispose);
  await container.read(authNotifierProvider.future);
  await container.read(userProfileProvider.future);

  final router = buildRouter(
    refreshListenable: ValueNotifier<int>(0),
    read: container.read,
  );
  router.go(location);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        // Explícito: sin esto el test resuelve al inglés y el assert sobre el
        // copy rioplatense falla por idioma, no por comportamiento.
        locale: const Locale('es', 'AR'),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      '/coach/nutricion monta la pantalla con el trainerId del vínculo activo',
      (tester) async {
    await _pumpRoute(
      tester,
      location: '/coach/nutricion',
      link: _activeLink(),
    );

    final screen = tester.widget<AthleteNutritionPlanScreen>(
      find.byType(AthleteNutritionPlanScreen),
    );
    // El par completo: sin el trainerId del vínculo no hay doc que leer.
    expect(screen.trainerId, _trainerUid);
    expect(screen.athleteId, _athleteUid);
  });

  testWidgets('/coach/nutricion sin vínculo activo no monta la pantalla',
      (tester) async {
    await _pumpRoute(tester, location: '/coach/nutricion', link: null);

    expect(find.byType(AthleteNutritionPlanScreen), findsNothing);
    expect(
      find.text(
        'Necesitás un vínculo activo con un PF para ver tu plan nutricional.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('/coach/archivos monta la pantalla aun sin vínculo activo',
      (tester) async {
    await _pumpRoute(tester, location: '/coach/archivos', link: null);

    final screen =
        tester.widget<AthleteFilesScreen>(find.byType(AthleteFilesScreen));
    expect(screen.athleteId, _athleteUid);
  });
}
