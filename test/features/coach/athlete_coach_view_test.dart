import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_discovery_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/athlete_coach_view.dart';
import 'package:treino/features/coach/data/trainer_link_repository.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach/presentation/trainers_list_screen.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';

class _MockTrainerLinkRepository extends Mock
    implements TrainerLinkRepository {}

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
  bool sharedWithTrainer = false,
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
      sharedWithTrainer: sharedWithTrainer,
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
              .overrideWith((ref) => Stream.value(_makePub())),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('TU PERSONAL TRAINER'), findsOneWidget);
      expect(find.text('Coach Joe'), findsOneWidget);
      expect(find.text('TERMINAR VÍNCULO'), findsOneWidget);
    });

    testWidgets('Fase B: status active → muestra botón MENSAJE',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const AthleteCoachView(),
        overrides: [
          currentAthleteLinkProvider.overrideWith((ref) async => _makeLink()),
          userPublicProfileProvider('trainer-1')
              .overrideWith((ref) => Stream.value(_makePub())),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('MENSAJE'), findsOneWidget);
    });

    testWidgets('Fase B: status pending → NO muestra botón MENSAJE',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const AthleteCoachView(),
        overrides: [
          currentAthleteLinkProvider.overrideWith(
              (ref) async => _makeLink(status: TrainerLinkStatus.pending)),
          userPublicProfileProvider('trainer-1')
              .overrideWith((ref) => Stream.value(_makePub())),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('MENSAJE'), findsNothing);
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
              .overrideWith((ref) => Stream.value(_makePub())),
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

  // ── sharedWithTrainer toggle (Fase 5 · Tech Debt) ─────────────────────────

  group('sharedWithTrainer toggle', () {
    setUpAll(() {
      // Required by mocktail.any() for non-primitive types if needed.
    });

    testWidgets(
      'SCENARIO-469: toggle visible cuando status == active',
      (tester) async {
        final mockRepo = _MockTrainerLinkRepository();
        await tester.pumpWidget(_wrap(
          const AthleteCoachView(),
          overrides: [
            currentAthleteLinkProvider.overrideWith(
                (ref) async => _makeLink(sharedWithTrainer: false)),
            userPublicProfileProvider('trainer-1')
                .overrideWith((ref) => Stream.value(_makePub())),
            trainerLinkRepositoryProvider.overrideWithValue(mockRepo),
          ],
        ));
        await tester.pumpAndSettle();

        expect(
          find.text('Compartir historial con mi PF'),
          findsOneWidget,
        );
        expect(find.byType(SwitchListTile), findsOneWidget);
      },
    );

    testWidgets(
      'SCENARIO-470: toggle ausente cuando status == pending',
      (tester) async {
        final mockRepo = _MockTrainerLinkRepository();
        await tester.pumpWidget(_wrap(
          const AthleteCoachView(),
          overrides: [
            currentAthleteLinkProvider.overrideWith(
                (ref) async => _makeLink(status: TrainerLinkStatus.pending)),
            userPublicProfileProvider('trainer-1')
                .overrideWith((ref) => Stream.value(_makePub())),
            trainerLinkRepositoryProvider.overrideWithValue(mockRepo),
          ],
        ));
        await tester.pumpAndSettle();

        expect(find.text('Compartir historial con mi PF'), findsNothing);
        expect(find.byType(SwitchListTile), findsNothing);
      },
    );

    testWidgets(
      'SCENARIO-471: toggle.value == true cuando link.sharedWithTrainer == true',
      (tester) async {
        final mockRepo = _MockTrainerLinkRepository();
        await tester.pumpWidget(_wrap(
          const AthleteCoachView(),
          overrides: [
            currentAthleteLinkProvider.overrideWith(
                (ref) async => _makeLink(sharedWithTrainer: true)),
            userPublicProfileProvider('trainer-1')
                .overrideWith((ref) => Stream.value(_makePub())),
            trainerLinkRepositoryProvider.overrideWithValue(mockRepo),
          ],
        ));
        await tester.pumpAndSettle();

        final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
        expect(tile.value, isTrue);
      },
    );

    testWidgets(
      'SCENARIO-472: tap toggle (off → on) muestra dialog y NO llama repo aún',
      (tester) async {
        final mockRepo = _MockTrainerLinkRepository();
        when(() => mockRepo.setSharedWithTrainer(any(), any()))
            .thenAnswer((_) async {});

        await tester.pumpWidget(_wrap(
          const AthleteCoachView(),
          overrides: [
            currentAthleteLinkProvider.overrideWith(
                (ref) async => _makeLink(sharedWithTrainer: false)),
            userPublicProfileProvider('trainer-1')
                .overrideWith((ref) => Stream.value(_makePub())),
            trainerLinkRepositoryProvider.overrideWithValue(mockRepo),
          ],
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();

        // Dialog body debe contener la frase clave del copy.
        expect(
          find.textContaining('sesiones, volumen y racha'),
          findsOneWidget,
        );
        // Repo aún NO se llamó.
        verifyNever(() => mockRepo.setSharedWithTrainer(any(), any()));
      },
    );

    testWidgets(
      'SCENARIO-473: confirmar dialog → llama repo(true) e invalida provider',
      (tester) async {
        final mockRepo = _MockTrainerLinkRepository();
        when(() => mockRepo.setSharedWithTrainer(any(), any()))
            .thenAnswer((_) async {});

        // Track invalidaciones del provider: contamos cuántas veces fue refetcheado.
        var resolveCount = 0;
        await tester.pumpWidget(_wrap(
          const AthleteCoachView(),
          overrides: [
            currentAthleteLinkProvider.overrideWith((ref) async {
              resolveCount++;
              return _makeLink(sharedWithTrainer: false);
            }),
            userPublicProfileProvider('trainer-1')
                .overrideWith((ref) => Stream.value(_makePub())),
            trainerLinkRepositoryProvider.overrideWithValue(mockRepo),
          ],
        ));
        await tester.pumpAndSettle();
        final resolveCountBefore = resolveCount;

        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(ElevatedButton, 'Compartir'));
        await tester.pumpAndSettle();

        verify(() => mockRepo.setSharedWithTrainer('link-1', true)).called(1);
        // Provider invalidado → re-resolvió al menos una vez más.
        expect(resolveCount, greaterThan(resolveCountBefore));
      },
    );

    testWidgets(
      'SCENARIO-474: tap toggle (on → off) NO muestra dialog y llama repo(false)',
      (tester) async {
        final mockRepo = _MockTrainerLinkRepository();
        when(() => mockRepo.setSharedWithTrainer(any(), any()))
            .thenAnswer((_) async {});

        var resolveCount = 0;
        await tester.pumpWidget(_wrap(
          const AthleteCoachView(),
          overrides: [
            currentAthleteLinkProvider.overrideWith((ref) async {
              resolveCount++;
              return _makeLink(sharedWithTrainer: true);
            }),
            userPublicProfileProvider('trainer-1')
                .overrideWith((ref) => Stream.value(_makePub())),
            trainerLinkRepositoryProvider.overrideWithValue(mockRepo),
          ],
        ));
        await tester.pumpAndSettle();
        final resolveCountBefore = resolveCount;

        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();

        // NO debe aparecer el dialog → el body del confirm no está en el árbol.
        expect(find.textContaining('sesiones, volumen y racha'), findsNothing);
        verify(() => mockRepo.setSharedWithTrainer('link-1', false)).called(1);
        expect(resolveCount, greaterThan(resolveCountBefore));
      },
    );
  });
}
