// El push de «Nueva solicitud de vinculación» deep-linkeaba a `/coach`, que en
// mobile abre la pestaña ALUMNOS: la lista de los que YA están vinculados. El
// PF tocaba el aviso y caía en una pantalla que no menciona la solicitud ni le
// deja aceptarla; las pendientes sólo vivían en el bottom sheet de la campana,
// sin ninguna ruta que les apuntara.
//
// Misma familia que QA-NOT-002 (`router_coach_agenda_test.dart`): un push que
// manda al PF a una ruta `/coach/*` que no es la que el aviso promete.

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
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/coach_screen.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach/presentation/solicitudes_screen.dart';
import 'package:treino/features/coach/presentation/trainer_dashboard_tab.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
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

final DateTime _kDate = DateTime.utc(2026, 1, 1);

/// Trainer con perfil COMPLETO (ADR-TPO-003): sin bio/specialty/rate el
/// `authRedirect` lo manda a `/profile/edit-trainer?mode=onboarding` y el test
/// nunca llega a la ruta que quiere probar.
UserProfile _trainerProfile() => UserProfile(
      uid: 't1',
      email: 'trainer@example.com',
      displayName: 'Lautaro PF',
      role: UserRole.trainer,
      createdAt: _kDate,
      updatedAt: _kDate,
      trainerBio: 'Powerlifting coach',
      trainerSpecialty: 'Fuerza',
      trainerMonthlyRate: 50000,
      trainerOffersOnline: true,
      onboardingSeen: allSurfacesSeen(),
    );

TrainerLink _pending(String id) => TrainerLink(
      id: id,
      trainerId: 't1',
      athleteId: 'a1',
      status: TrainerLinkStatus.pending,
      requestedAt: _kDate,
      acceptedAt: null,
      sharedWithTrainer: false,
    );

Future<void> _pumpEnRuta(
  WidgetTester tester,
  String location, {
  List<TrainerLink> links = const <TrainerLink>[],
}) async {
  final container = ProviderContainer(
    overrides: [
      authNotifierProvider.overrideWith(
        () => _StubAuthNotifier(AsyncData(_MockUser())),
      ),
      userProfileProvider.overrideWith(
        (ref) => Stream<UserProfile?>.value(_trainerProfile()),
      ),
      authStateChangesProvider.overrideWith((_) => Stream.value(null)),
      currentUidProvider.overrideWithValue('t1'),
      // Se override SIEMPRE: el provider real toma `keepAlive` y arma un Timer
      // de gracia de 5 minutos que deja el test colgado en `!timersPending`.
      trainerLinksStreamProvider.overrideWith((ref) => Stream.value(links)),
      userPublicProfileProvider.overrideWith(
        (ref, uid) => Stream<UserPublicProfile?>.value(null),
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
        locale: const Locale('es', 'AR'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      '/coach/solicitudes monta la bandeja de pendientes, no la lista de alumnos',
      (tester) async {
    await _pumpEnRuta(tester, '/coach/solicitudes', links: [_pending('l1')]);

    expect(find.byType(SolicitudesScreen), findsOneWidget);
    expect(find.byType(PendingRequestsView), findsOneWidget);
    // La solicitud se puede RESOLVER desde acá — que es lo que el aviso
    // promete y lo que `/coach` no daba.
    expect(find.byType(ElevatedButton), findsOneWidget);
    // Y no montó la vista que tenía el bug.
    expect(find.byType(CoachScreen), findsNothing);
  });

  testWidgets('sin pendientes muestra el vacío y se queda (no rebota)',
      (tester) async {
    await _pumpEnRuta(tester, '/coach/solicitudes');

    expect(find.byType(SolicitudesScreen), findsOneWidget);
    expect(find.text('No tenés solicitudes pendientes.'), findsOneWidget);
  });

  // Control negativo, y la razón de que este archivo exista.
  //
  // Sin él, una ruta `/coach/solicitudes` que por error resolviera al mismo
  // `CoachScreen` que `/coach` pasaría el primer test igual de verde. Esto
  // clava que las dos rutas montan cosas DISTINTAS.
  testWidgets('/coach a secas sigue montando CoachScreen, no la bandeja',
      (tester) async {
    await _pumpEnRuta(tester, '/coach', links: [_pending('l1')]);

    expect(find.byType(CoachScreen), findsOneWidget);
    expect(find.byType(SolicitudesScreen), findsNothing);
  });
}
