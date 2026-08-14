import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/features/workout/presentation/widgets/plantillas_tab.dart';
import 'package:treino/features/workout/presentation/widgets/level_filter_pills.dart';
import 'package:treino/features/workout/presentation/widgets/routine_card.dart';
import 'package:treino/l10n/app_l10n.dart';

/// PLANTILLAS grid — the community source added in workout redesign slice 3.
/// The coach/system behaviour of slice 2 is locked by plantillas_tab_test.dart.

Routine makeSystem({String id = 'sys-1', String name = 'Full Body'}) => Routine(
      id: id,
      name: name,
      split: 'Full Body',
      level: ExperienceLevel.beginner,
      days: const [],
    );

Routine makeTemplate({
  required String id,
  String name = 'Plantilla',
  String assignedBy = 'trainer-9',
  ExperienceLevel level = ExperienceLevel.beginner,
}) =>
    Routine(
      id: id,
      name: name,
      split: 'PPL',
      level: level,
      days: const [],
      source: RoutineSource.trainerTemplate,
      assignedBy: assignedBy,
      visibility: RoutineVisibility.public,
    );

TrainerLink makeLink({String trainerId = 'trainer-1'}) => TrainerLink(
      id: 'link-1',
      trainerId: trainerId,
      athleteId: 'athlete-1',
      status: TrainerLinkStatus.active,
      requestedAt: DateTime.utc(2026, 1, 1),
      acceptedAt: DateTime.utc(2026, 1, 2),
    );

List<Override> coachOverrides(List<Routine> templates) => [
      userPublicProfileProvider('trainer-1').overrideWith(
        (ref) => Stream.value(
          const UserPublicProfile(
            uid: 'trainer-1',
            displayName: 'Coach Vic',
            displayNameLowercase: 'coach vic',
            sharedTemplatesWithAthletes: true,
          ),
        ),
      ),
      trainerTemplatesStreamProvider('trainer-1').overrideWith(
        (ref) => Stream.value(templates),
      ),
    ];

Widget _wrap(
  Widget w, {
  List<Override> overrides = const [],
  TrainerLink? link,
}) =>
    ProviderScope(
      overrides: [
        currentAthleteLinkProvider.overrideWith((ref) async => link),
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(body: SizedBox(height: 800, child: w)),
      ),
    );

void main() {
  group('PlantillasTab — plantillas publicadas de la comunidad', () {
    testWidgets('renders community templates with the ENTRENADOR badge',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PlantillasTab(),
          overrides: [
            routinesProvider.overrideWith((ref) async => [makeSystem()]),
            publishedTemplatesProvider.overrideWith(
              (ref) async => [makeTemplate(id: 'pub-1', name: 'PPL de Juan')],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PPL DE JUAN'), findsOneWidget);
      expect(
        find.byKey(const Key('routine_trainer_chip_pub-1')),
        findsOneWidget,
      );
      expect(find.text('ENTRENADOR'), findsOneWidget);
      // The community badge is NOT the coach badge.
      expect(find.text('DE TU COACH'), findsNothing);
    });

    testWidgets('system templates keep rendering without any badge',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PlantillasTab(),
          overrides: [
            routinesProvider.overrideWith((ref) async => [makeSystem()]),
            publishedTemplatesProvider.overrideWith(
              (ref) async => [makeTemplate(id: 'pub-1')],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RoutineCard), findsNWidgets(2));
      expect(find.text('ENTRENADOR'), findsOneWidget);
    });

    testWidgets('a template from MY coach shows DE TU COACH, never twice',
        (tester) async {
      // The linked coach's own published template matches BOTH queries —
      // it must appear once, badged as my coach.
      final shared = makeTemplate(
        id: 'shared-1',
        name: 'Plan de Vic',
        assignedBy: 'trainer-1',
      );
      await tester.pumpWidget(
        _wrap(
          const PlantillasTab(),
          link: makeLink(),
          overrides: [
            ...coachOverrides([shared]),
            routinesProvider.overrideWith((ref) async => const <Routine>[]),
            publishedTemplatesProvider.overrideWith((ref) async => [shared]),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RoutineCard), findsOneWidget);
      expect(find.text('DE TU COACH'), findsOneWidget);
      expect(find.text('ENTRENADOR'), findsNothing);
    });

    testWidgets('coach templates come before community ones', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PlantillasTab(),
          link: makeLink(),
          overrides: [
            ...coachOverrides([
              makeTemplate(
                id: 'coach-1',
                name: 'Del Coach',
                assignedBy: 'trainer-1',
              ),
            ]),
            routinesProvider.overrideWith((ref) async => const <Routine>[]),
            publishedTemplatesProvider.overrideWith(
              (ref) async =>
                  [makeTemplate(id: 'pub-1', name: 'De La Comunidad')],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Both land in the same 2-up row, so compare tree order (which drives
      // the grid's fill order) rather than vertical offset.
      final ids = tester
          .widgetList<RoutineCard>(find.byType(RoutineCard))
          .map((c) => c.routine.id)
          .toList();
      expect(ids, ['coach-1', 'pub-1']);
    });

    testWidgets('the level filter also applies to community templates',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PlantillasTab(),
          overrides: [
            routinesProvider.overrideWith((ref) async => const <Routine>[]),
            publishedTemplatesProvider.overrideWith(
              (ref) async => [
                makeTemplate(id: 'pub-beg', name: 'Principiante'),
                makeTemplate(
                  id: 'pub-adv',
                  name: 'Avanzada',
                  level: ExperienceLevel.advanced,
                ),
              ],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RoutineCard), findsNWidgets(2));

      // Scoped to the filter pills on purpose: since #639 the card caption
      // leads with the routine's level, so a bare find.text('Avanzado')
      // matches the card too and the tap goes ambiguous.
      await tester.tap(
        find.descendant(
          of: find.byType(LevelFilterPills),
          matching: find.text('Avanzado'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('AVANZADA'), findsOneWidget);
      expect(find.text('PRINCIPIANTE'), findsNothing);
    });

    testWidgets('a failing community query never takes down the grid',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PlantillasTab(),
          overrides: [
            routinesProvider.overrideWith((ref) async => [makeSystem()]),
            publishedTemplatesProvider
                .overrideWith((ref) async => throw Exception('boom')),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // The system catalogue still renders; the community part just
      // contributes nothing (enrichment contract).
      expect(find.byType(RoutineCard), findsOneWidget);
      expect(find.text('FULL BODY'), findsOneWidget);
    });

    testWidgets(
        'when the CATALOG fails, community templates survive above the error',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PlantillasTab(),
          overrides: [
            routinesProvider
                .overrideWith((ref) async => throw Exception('nope')),
            publishedTemplatesProvider.overrideWith(
              (ref) async => [makeTemplate(id: 'pub-1', name: 'Sobreviviente')],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SOBREVIVIENTE'), findsOneWidget);
      expect(
          find.text('Hubo un error cargando las plantillas.'), findsOneWidget);
    });
  });
}
