// QA-NOT-002: /coach/agenda debe ser role-aware. Los pushes de "Nueva
// solicitud de sesión" (anteriores al fix del deepLink en notifyOnAppointment)
// deep-linkean al TRAINER a /coach/agenda — que montaba el host exclusivo de
// atleta y mostraba "Necesitás un vínculo activo con un PF". Ahora un trainer
// aterriza en su propia agenda (CoachScreen tab AGENDA); el flujo de atleta
// queda intacto.

import 'dart:async';

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
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/coach_screen.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/presentation/trainer_agenda_tab.dart';
import 'package:treino/features/coach/trainer_coach_view.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

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

const _kAthleteErrorText =
    'Necesitás un vínculo activo con un PF para ver su agenda.';

/// Trainer con perfil COMPLETO (ADR-TPO-003): sin bio/specialty/rate el
/// authRedirect lo mandaría a /profile/edit-trainer?mode=onboarding y el test
/// nunca llegaría a /coach/agenda.
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
    );

UserProfile _athleteProfile() => UserProfile(
      uid: 'a1',
      email: 'athlete@example.com',
      displayName: 'sporty',
      role: UserRole.athlete,
      createdAt: _kDate,
      updatedAt: _kDate,
    );

Future<ProviderContainer> _pumpCoachAgenda(
  WidgetTester tester, {
  required UserProfile profile,
}) async {
  final container = ProviderContainer(
    overrides: [
      authNotifierProvider.overrideWith(
        () => _StubAuthNotifier(AsyncData(_MockUser())),
      ),
      userProfileProvider.overrideWith(
        (ref) => Stream<UserProfile?>.value(profile),
      ),
      authStateChangesProvider.overrideWith((_) => Stream.value(null)),
      currentUidProvider.overrideWithValue(profile.uid),
      // Vista del trainer: la tab AGENDA watchea el stream de turnos — family-
      // wide override para no depender de la TrainerAppointmentsKey exacta
      // (su ventana rodante se deriva de DateTime.now()).
      trainerAppointmentsStreamProvider.overrideWith(
        (ref, key) => Stream.value(const <Appointment>[]),
      ),
      // Flujo de atleta: sin vínculo activo.
      currentAthleteLinkProvider.overrideWith((ref) async => null),
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
  router.go('/coach/agenda');

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
  return container;
}

void main() {
  testWidgets(
      'QA-NOT-002: a TRAINER on /coach/agenda lands on their own agenda '
      '(CoachScreen tab AGENDA), not the athlete-link error', (tester) async {
    await _pumpCoachAgenda(tester, profile: _trainerProfile());

    // El host role-aware montó la vista del trainer…
    expect(find.byType(CoachScreen), findsOneWidget);
    expect(find.byType(TrainerCoachView), findsOneWidget);
    // …en la tab AGENDA — TabBarView solo monta la página visible, así que
    // esto clava initialTab: 'agenda'. Sin este assert, una regresión a
    // CoachScreen() (tab ALUMNOS) quedaría verde (verificado por mutación).
    expect(find.byType(TrainerAgendaTab), findsOneWidget);
    // …y el mensaje de atleta (el bug) no aparece.
    expect(find.text(_kAthleteErrorText), findsNothing);
  });

  testWidgets(
      'QA-NOT-002 (regresión): an ATHLETE without an active link on '
      '/coach/agenda still sees the link-required message', (tester) async {
    await _pumpCoachAgenda(tester, profile: _athleteProfile());

    expect(find.text(_kAthleteErrorText), findsOneWidget);
    expect(find.byType(CoachScreen), findsNothing);
  });

  testWidgets(
      'QA-NOT-002: while the profile resolves, /coach/agenda shows a spinner '
      '— never a flash of the athlete-link error', (tester) async {
    // Stream que NUNCA emite → userProfileProvider queda en AsyncLoading.
    final profileCtrl = StreamController<UserProfile?>();
    addTearDown(profileCtrl.close);

    final container = ProviderContainer(
      overrides: [
        authNotifierProvider.overrideWith(
          () => _StubAuthNotifier(AsyncData(_MockUser())),
        ),
        userProfileProvider.overrideWith((ref) => profileCtrl.stream),
        authStateChangesProvider.overrideWith((_) => Stream.value(null)),
        currentUidProvider.overrideWithValue('t1'),
        currentAthleteLinkProvider.overrideWith((ref) async => null),
        unreadFromCoachProvider.overrideWith((ref) => 0),
        unreadFromFriendsProvider.overrideWith((ref) => 0),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authNotifierProvider.future);

    final router = buildRouter(
      refreshListenable: ValueNotifier<int>(0),
      read: container.read,
    );
    router.go('/coach/agenda');

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
    // pump (NO pumpAndSettle): el spinner anima indefinidamente.
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(find.text(_kAthleteErrorText), findsNothing);
    expect(find.byType(CoachScreen), findsNothing);
  });
}
