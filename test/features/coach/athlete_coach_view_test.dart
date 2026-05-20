import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_discovery_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/athlete_coach_view.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach/presentation/trainers_list_screen.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';

Widget _wrap(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: child),
      ),
    );

TrainerLink _makeLink({
  TrainerLinkStatus status = TrainerLinkStatus.active,
  String trainerId = 'trainer-1',
}) =>
    TrainerLink(
      id: 'link-1',
      trainerId: trainerId,
      athleteId: 'athlete-1',
      status: status,
      requestedAt: DateTime.utc(2026, 5, 18, 10, 0),
      acceptedAt: status == TrainerLinkStatus.active
          ? DateTime.utc(2026, 5, 18, 12, 0)
          : null,
    );

UserPublicProfile _makePub({String displayName = 'Coach Joe'}) =>
    UserPublicProfile(
      uid: 'trainer-1',
      displayName: displayName,
      displayNameLowercase: displayName.toLowerCase(),
    );

void main() {
  group('AthleteCoachView', () {
    testWidgets(
        'REQ-COACH-LINK-001: sin link → renderiza TrainersListScreen (discovery)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const AthleteCoachView(),
        overrides: [
          currentAthleteLinkProvider.overrideWith((ref) async => null),
          trainerDiscoveryProvider.overrideWith((_) async => []),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.byType(TrainersListScreen), findsOneWidget);
    });

    testWidgets(
        'REQ-COACH-LINK-002: status active → muestra info del PF + terminar',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const AthleteCoachView(),
        overrides: [
          currentAthleteLinkProvider.overrideWith((ref) async => _makeLink()),
          userPublicProfileProvider('trainer-1')
              .overrideWith((ref) async => _makePub()),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('TU PERSONAL TRAINER'), findsOneWidget);
      expect(find.text('Coach Joe'), findsOneWidget);
      expect(find.text('TERMINAR VÍNCULO'), findsOneWidget);
    });

    testWidgets(
        'REQ-COACH-LINK-003: status pending → muestra esperando + cancelar',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const AthleteCoachView(),
        overrides: [
          currentAthleteLinkProvider.overrideWith(
              (ref) async => _makeLink(status: TrainerLinkStatus.pending)),
          userPublicProfileProvider('trainer-1')
              .overrideWith((ref) async => _makePub()),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('SOLICITUD ENVIADA'), findsOneWidget);
      expect(find.text('Esperando confirmación'), findsOneWidget);
      expect(find.text('CANCELAR SOLICITUD'), findsOneWidget);
    });

    testWidgets(
        'REQ-COACH-LINK-004: loading state → spinner mientras provider resuelve',
        (tester) async {
      final completer = Completer<TrainerLink?>();
      addTearDown(() {
        if (!completer.isCompleted) completer.complete(null);
      });
      await tester.pumpWidget(_wrap(
        const AthleteCoachView(),
        overrides: [
          currentAthleteLinkProvider.overrideWith((ref) => completer.future),
        ],
      ));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
