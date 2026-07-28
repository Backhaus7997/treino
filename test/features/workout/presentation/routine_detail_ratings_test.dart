import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/analytics/analytics_service.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/template_rating_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/features/workout/domain/template_rating.dart';
import 'package:treino/features/workout/presentation/routine_detail_screen.dart';
import 'package:treino/features/workout/presentation/widgets/template_ratings_section.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../../helpers/fake_analytics_service.dart';

class _FakeUser extends Mock implements User {}

const _routineId = 'tpl-1';

RoutineDay _day() => const RoutineDay(
      dayNumber: 1,
      name: 'Push',
      slots: [
        RoutineSlot(
          exerciseId: 'bench-press',
          exerciseName: 'Bench Press',
          muscleGroup: 'chest',
          targetSets: 4,
          targetRepsMin: 8,
          targetRepsMax: 12,
          restSeconds: 90,
        ),
      ],
      estimatedMinutes: 45,
    );

Routine _template({
  required RoutineSource source,
  required RoutineVisibility visibility,
  double? ratingAvg,
  int? ratingsCount,
}) =>
    Routine(
      id: _routineId,
      name: 'PPL de Juan',
      split: 'PPL',
      level: ExperienceLevel.beginner,
      days: [_day()],
      source: source,
      assignedBy: source == RoutineSource.system ? null : 'trainer-9',
      visibility: visibility,
      ratingAvg: ratingAvg,
      ratingsCount: ratingsCount,
    );

User _user() {
  final user = _FakeUser();
  when(() => user.uid).thenReturn('viewer-1');
  return user;
}

Widget _wrap(Routine routine, {List<TemplateRating> ratings = const []}) =>
    ProviderScope(
      overrides: [
        analyticsServiceProvider.overrideWithValue(FakeAnalyticsService()),
        authStateChangesProvider.overrideWith((ref) => Stream.value(_user())),
        routineByIdStreamProvider(_routineId)
            .overrideWith((ref) => Stream.value(routine)),
        templateRatingsProvider(_routineId)
            .overrideWith((ref) => Stream.value(ratings)),
        myTemplateRatingProvider(_routineId)
            .overrideWith((ref) => Stream.value(null)),
        userPublicProfilesBatchProvider(
          (ratings.map((r) => r.userId).toSet().toList()..sort()).join(','),
        ).overrideWith((ref) async => const {}),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const Scaffold(
          body: RoutineDetailScreen(routineId: _routineId),
        ),
      ),
    );

void main() {
  testWidgets('a PUBLISHED trainer template shows the ratings block',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        _template(
          source: RoutineSource.trainerTemplate,
          visibility: RoutineVisibility.public,
          ratingAvg: 4.5,
          ratingsCount: 2,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byType(TemplateRatingsSection),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.byType(TemplateRatingsSection), findsOneWidget);
    expect(find.text('CALIFICACIONES'), findsOneWidget);
    expect(find.text('4.5'), findsOneWidget);
  });

  testWidgets('a PRIVATE trainer template shows no ratings block',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        _template(
          source: RoutineSource.trainerTemplate,
          visibility: RoutineVisibility.private,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TemplateRatingsSection), findsNothing);
  });

  testWidgets('a system catalogue routine shows no ratings block',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        _template(
          source: RoutineSource.system,
          visibility: RoutineVisibility.public,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TemplateRatingsSection), findsNothing);
  });

  testWidgets('a published template with zero ratings keeps its empty state',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        _template(
          source: RoutineSource.trainerTemplate,
          visibility: RoutineVisibility.public,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byType(TemplateRatingsSection),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    // Genuinely zero ratings: both empty states are the honest answer here
    // (unlike "aggregate missing but ratings exist", covered in
    // template_ratings_section_test.dart).
    expect(
      find.text('Todavía nadie calificó esta plantilla. ¡Sé el primero!'),
      findsOneWidget,
    );
    expect(find.text('Todavía no hay comentarios.'), findsOneWidget);
  });
}
