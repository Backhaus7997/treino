import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/presentation/routine_detail_placeholder_screen.dart';

Routine _makeRoutine({String id = 'known-id', String name = 'Fixture Name'}) =>
    Routine(
      id: id,
      name: name,
      split: 'Full Body',
      level: ExperienceLevel.beginner,
      days: const [],
    );

Widget _wrap(
  Widget w, {
  List<Override> overrides = const [],
}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: w,
      ),
    );

void main() {
  group('RoutineDetailPlaceholderScreen', () {
    testWidgets(
        'known id → AppBar title is routine name UPPERCASE + body "Detalle disponible próximamente."',
        (tester) async {
      final routine = _makeRoutine(id: 'known-id', name: 'Fixture Name');

      await tester.pumpWidget(
        _wrap(
          const RoutineDetailPlaceholderScreen(routineId: 'known-id'),
          overrides: [
            routineByIdProvider('known-id').overrideWith((_) async => routine),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('FIXTURE NAME'), findsOneWidget);
      expect(find.text('Detalle disponible próximamente.'), findsOneWidget);
    });

    testWidgets('unknown id → body "No encontramos esta plantilla."',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const RoutineDetailPlaceholderScreen(routineId: 'unknown-id'),
          overrides: [
            routineByIdProvider('unknown-id').overrideWith((_) async => null),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('No encontramos esta plantilla.'), findsOneWidget);
    });

    testWidgets('AsyncLoading state → CircularProgressIndicator in body',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const RoutineDetailPlaceholderScreen(routineId: 'loading-id'),
          overrides: [
            routineByIdProvider('loading-id').overrideWith(
              (_) => Completer<Routine?>().future,
            ),
          ],
        ),
      );
      // Single pump — stays in loading
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('back button (IconButton) present in AppBar', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const RoutineDetailPlaceholderScreen(routineId: 'known-id'),
          overrides: [
            routineByIdProvider('known-id')
                .overrideWith((_) async => _makeRoutine()),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // AppBar should contain a leading IconButton (back)
      expect(find.byType(IconButton), findsOneWidget);
    });

    testWidgets('back button calls Navigator.maybePop', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ProviderScope(
                    overrides: [
                      routineByIdProvider('known-id')
                          .overrideWith((_) async => _makeRoutine()),
                    ],
                    child: const RoutineDetailPlaceholderScreen(
                      routineId: 'known-id',
                    ),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

      // Navigate to the screen
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 50));

      // Now tap the back button
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      // After popping, we should be back on the previous route (text 'open' visible)
      expect(find.text('open'), findsOneWidget);
    });
  });
}
