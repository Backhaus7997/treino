import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/presentation/widgets/level_filter_pills.dart';

Widget _wrap(Widget w, {List<Override> overrides = const []}) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: w),
      ),
    );

void main() {
  group('LevelFilterPills', () {
    testWidgets(
        'renders exactly 4 pills: Todas, Principiante, Intermedio, Avanzado',
        (tester) async {
      await tester.pumpWidget(_wrap(const LevelFilterPills()));
      await tester.pump();

      expect(find.text('Todas'), findsOneWidget);
      expect(find.text('Principiante'), findsOneWidget);
      expect(find.text('Intermedio'), findsOneWidget);
      expect(find.text('Avanzado'), findsOneWidget);
    });

    testWidgets('default active pill is "Todas" (filter == null)',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: LevelFilterPills()),
          ),
        ),
      );
      await tester.pump();

      // routinesLevelFilterProvider should still be null (default)
      expect(container.read(routinesLevelFilterProvider), isNull);
    });

    testWidgets(
        'tapping "Principiante" sets filter to ExperienceLevel.beginner',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: LevelFilterPills()),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Principiante'));
      await tester.pump();

      expect(
        container.read(routinesLevelFilterProvider),
        equals(ExperienceLevel.beginner),
      );
    });

    testWidgets('tapping "Avanzado" sets filter to ExperienceLevel.advanced',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: LevelFilterPills()),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Avanzado'));
      await tester.pump();

      expect(
        container.read(routinesLevelFilterProvider),
        equals(ExperienceLevel.advanced),
      );
    });

    testWidgets('tapping "Todas" sets filter to null', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Start with a non-null filter
      container.read(routinesLevelFilterProvider.notifier).state =
          ExperienceLevel.intermediate;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: LevelFilterPills()),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Todas'));
      await tester.pump();

      expect(container.read(routinesLevelFilterProvider), isNull);
    });

    testWidgets('only one pill is active at a time', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: LevelFilterPills()),
          ),
        ),
      );
      await tester.pump();

      // Tap Intermedio
      await tester.tap(find.text('Intermedio'));
      await tester.pump();

      // Filter is intermediate, not null
      expect(
        container.read(routinesLevelFilterProvider),
        equals(ExperienceLevel.intermediate),
      );
      // Todas is no longer selected (filter != null)
      expect(container.read(routinesLevelFilterProvider), isNot(isNull));
    });
  });
}
