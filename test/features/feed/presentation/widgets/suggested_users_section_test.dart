import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/feed/application/suggested_users_providers.dart';
import 'package:treino/features/feed/presentation/widgets/feed_empty_state.dart';
import 'package:treino/features/feed/presentation/widgets/suggested_users_section.dart';
import 'package:treino/features/gyms/domain/gym.dart' show kNoGymId;
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/l10n/app_l10n.dart';

const _emptyMessage = 'Todavía no hay posts de a quienes seguís';

UserPublicProfile profile({
  required String uid,
  required String displayName,
}) =>
    UserPublicProfile(
      uid: uid,
      displayName: displayName,
      displayNameLowercase: displayName.toLowerCase(),
      gymId: 'gym-a',
    );

Widget wrap({
  required String? gymId,
  required List<UserPublicProfile> suggestions,
}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                const FeedEmptyState(message: _emptyMessage),
                SuggestedUsersSection(gymId: gymId),
              ],
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/feed/profile/:uid',
        builder: (_, state) => Scaffold(
          body: Text('profile-${state.pathParameters['uid']}'),
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      if (gymId != null && gymId.isNotEmpty && gymId != kNoGymId)
        suggestedUsersProvider(gymId).overrideWith(
          (ref) async => suggestions,
        ),
    ],
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      locale: const Locale('es', 'AR'),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      routerConfig: router,
    ),
  );
}

void main() {
  testWidgets('no-gym users do not render the suggestions section', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        gymId: null,
        suggestions: [profile(uid: 'candidate', displayName: 'Ana')],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('suggested_users_section')), findsNothing);

    await tester.pumpWidget(
      wrap(
        gymId: kNoGymId,
        suggestions: [profile(uid: 'candidate', displayName: 'Ana')],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('suggested_users_section')), findsNothing);
  });

  testWidgets(
      'zero suggestions render no section and no empty-suggestions copy',
      (tester) async {
    await tester.pumpWidget(
      wrap(gymId: 'gym-a', suggestions: const []),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('suggested_users_section')), findsNothing);
    expect(find.text('PERSONAS DE TU GYM'), findsNothing);
  });

  testWidgets('tapping a suggestion opens the matching public profile', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      wrap(
        gymId: 'gym-a',
        suggestions: [profile(uid: 'ana-uid', displayName: 'Ana Pérez')],
      ),
    );
    await tester.pumpAndSettle();

    final row = find.byKey(const Key('suggested_user_ana-uid'));
    expect(row, findsOneWidget);
    expect(tester.getSemantics(row).label, contains('Ana Pérez'));

    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.text('profile-ana-uid'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('keeps the existing Friends empty state above suggestions', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        gymId: 'gym-a',
        suggestions: [profile(uid: 'candidate', displayName: 'Ana')],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FeedEmptyState), findsOneWidget);
    expect(find.text(_emptyMessage), findsOneWidget);
    expect(find.byKey(const Key('suggested_users_section')), findsOneWidget);
  });

  testWidgets('renders suggestions in a horizontal carousel', (
    tester,
  ) async {
    final suggestions = [
      for (var index = 0; index < kSuggestedUsersLimit; index++)
        profile(uid: 'uid-$index', displayName: 'Persona $index'),
    ];

    await tester.pumpWidget(
      wrap(gymId: 'gym-a', suggestions: suggestions),
    );
    await tester.pumpAndSettle();

    final listView = tester.widget<ListView>(find.byType(ListView));
    expect(listView.scrollDirection, Axis.horizontal);
    for (final suggestion in suggestions.take(2)) {
      expect(
        find.byKey(Key('suggested_user_${suggestion.uid}')),
        findsOneWidget,
      );
    }
  });
}
