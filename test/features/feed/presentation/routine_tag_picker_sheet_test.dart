import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/feed/presentation/routine_tag_picker_sheet.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/application/user_routines_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';

Routine _makeRoutine({String id = 'r1', String name = 'Push A'}) => Routine(
      id: id,
      name: name,
      level: ExperienceLevel.beginner,
      days: const [],
    );

Widget _wrap({required Stream<List<Routine>> stream}) => ProviderScope(
      overrides: [
        userCreatedRoutinesProvider.overrideWith((ref, uid) => stream),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: RoutineTagPickerSheet(uid: 'u1')),
      ),
    );

void main() {
  testWidgets('shows a spinner while the routines load', (tester) async {
    final completer = Completer<List<Routine>>();
    await tester.pumpWidget(_wrap(stream: Stream.fromFuture(completer.future)));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Let it settle so the indeterminate spinner's timer is disposed.
    completer.complete(const []);
    await tester.pumpAndSettle();
  });

  testWidgets('shows an error message when the stream errors', (tester) async {
    await tester.pumpWidget(
      _wrap(stream: Stream<List<Routine>>.error(Exception('boom'))),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('No pudimos cargar tus rutinas. Intentá de nuevo.'),
      findsOneWidget,
    );
  });

  testWidgets('lists the athlete routines', (tester) async {
    await tester.pumpWidget(
      _wrap(
        stream: Stream.value([
          _makeRoutine(id: 'r1', name: 'Push A'),
          _makeRoutine(id: 'r2', name: 'Pull B'),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ELEGÍ UNA RUTINA'), findsOneWidget);
    expect(find.text('Push A'), findsOneWidget);
    expect(find.text('Pull B'), findsOneWidget);
  });

  testWidgets('shows the empty state when there are no routines',
      (tester) async {
    await tester.pumpWidget(_wrap(stream: Stream.value(const <Routine>[])));
    await tester.pumpAndSettle();

    expect(
      find.text('Todavía no tenés rutinas propias para etiquetar.'),
      findsOneWidget,
    );
  });
}
