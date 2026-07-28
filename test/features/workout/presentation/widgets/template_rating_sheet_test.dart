import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/features/reviews/presentation/widgets/star_rating_input.dart';
import 'package:treino/features/workout/domain/template_rating.dart';
import 'package:treino/features/workout/presentation/widgets/template_rating_sheet.dart';
import 'package:treino/l10n/app_l10n.dart';

class _FakeUser extends Mock implements User {}

const _routineId = 'tpl-1';
const _uid = 'rater-1';

User _user() {
  final user = _FakeUser();
  when(() => user.uid).thenReturn(_uid);
  return user;
}

Widget _wrap(FakeFirebaseFirestore firestore, {TemplateRating? existing}) =>
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(firestore),
        authStateChangesProvider.overrideWith((ref) => Stream.value(_user())),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(
          body: TemplateRatingSheet(
            routineId: _routineId,
            existing: existing,
          ),
        ),
      ),
    );

Future<Map<String, Object?>?> storedRating(
  FakeFirebaseFirestore firestore,
) async {
  final snap = await firestore
      .collection('routines')
      .doc(_routineId)
      .collection('ratings')
      .doc(_uid)
      .get();
  return snap.data();
}

void main() {
  testWidgets('submit is disabled until a star is picked', (tester) async {
    await tester.pumpWidget(_wrap(FakeFirebaseFirestore()));
    await tester.pumpAndSettle();

    final button = tester.widget<ElevatedButton>(
      find.byKey(const Key('template_rating_submit')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('rating with a comment writes it under my uid', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await tester.pumpWidget(_wrap(firestore));
    await tester.pumpAndSettle();

    // Tap the 4th star.
    await tester.tap(
      find
          .descendant(
            of: find.byType(StarRatingInput),
            matching: find.byType(GestureDetector),
          )
          .at(3),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Muy buena progresión');
    await tester.tap(find.byKey(const Key('template_rating_submit')));
    await tester.pumpAndSettle();

    final data = await storedRating(firestore);
    expect(data, isNotNull);
    expect(data!['rating'], 4);
    expect(data['comment'], 'Muy buena progresión');
    expect(data['userId'], _uid);
  });

  testWidgets('an empty comment is stored as null, not as a blank string',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    await tester.pumpWidget(_wrap(firestore));
    await tester.pumpAndSettle();

    await tester.tap(
      find
          .descendant(
            of: find.byType(StarRatingInput),
            matching: find.byType(GestureDetector),
          )
          .at(4),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.byKey(const Key('template_rating_submit')));
    await tester.pumpAndSettle();

    final data = await storedRating(firestore);
    expect(data!['rating'], 5);
    expect(data['comment'], isNull);
  });

  testWidgets('editing pre-loads my previous rating and comment',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    await tester.pumpWidget(
      _wrap(
        firestore,
        existing: TemplateRating(
          userId: _uid,
          rating: 2,
          comment: 'Me costó',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Editá tu calificación'), findsOneWidget);
    expect(find.text('Me costó'), findsOneWidget);
    final input = tester.widget<StarRatingInput>(find.byType(StarRatingInput));
    expect(input.rating, 2);
  });
}
