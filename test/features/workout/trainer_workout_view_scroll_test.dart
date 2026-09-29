import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/trainer_workout_view.dart';

// Regresión: el shell usa `Scaffold(extendBody: true)` y la barra flotante
// pasa POR ENCIMA del body, así que la última plantilla de la biblioteca
// quedaba tapada — `SingleChildScrollView.padding` no incluía el inset
// inferior del sistema (home indicator / barra de navegación). Mismo bug
// que ya resolvieron `workout_screen.dart`, `home_screen.dart` y
// `trainer_coach_view.dart`: el padding inferior tiene que ser
// `20 + MediaQuery.paddingOf(context).bottom`, no un `20` fijo.

const _uid = 'trainer-1';

Widget _wrap({required double bottomInset}) => ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
        currentUidProvider.overrideWith((ref) => _uid),
        trainerTemplatesStreamProvider(_uid)
            .overrideWith((ref) => Stream.value(const <Routine>[])),
        userPublicProfileProvider(_uid)
            .overrideWith((ref) => const Stream.empty()),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: EdgeInsets.only(bottom: bottomInset),
          ),
          child: child!,
        ),
        home: const Scaffold(body: TrainerWorkoutView()),
      ),
    );

void main() {
  testWidgets(
      'el padding inferior del scroll incluye el inset del sistema '
      '(la barra flotante no tapa la última plantilla)', (tester) async {
    const bottomInset = 34.0; // home indicator de un iPhone con notch.
    await tester.pumpWidget(_wrap(bottomInset: bottomInset));
    await tester.pump();

    final scrollView = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView));
    final padding = scrollView.padding! as EdgeInsets;

    expect(
      padding.bottom,
      20 + bottomInset,
      reason: 'sin el inset, la barra flotante del shell tapa la última '
          'plantilla de la biblioteca',
    );
    expect(scrollView.physics, isA<AlwaysScrollableScrollPhysics>());
  });

  testWidgets('sin inset del sistema, el padding inferior es sólo 20',
      (tester) async {
    await tester.pumpWidget(_wrap(bottomInset: 0));
    await tester.pump();

    final scrollView = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView));
    final padding = scrollView.padding! as EdgeInsets;

    expect(padding.bottom, 20);
  });
}
