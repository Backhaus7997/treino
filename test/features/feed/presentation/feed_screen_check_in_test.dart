import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/check_in/application/check_in_providers.dart';
import 'package:treino/features/check_in/domain/check_in.dart';
import 'package:treino/features/check_in/presentation/check_in_dialog.dart';
import 'package:treino/features/feed/application/feed_screen_providers.dart';
import 'package:treino/features/feed/application/post_providers.dart';
import 'package:treino/features/feed/domain/feed_segment.dart';
import 'package:treino/features/feed/domain/post.dart';
import 'package:treino/features/feed/feed_screen.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/session_providers.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

UserProfile _makeProfile({String? gymId}) => UserProfile(
      uid: 'u1',
      email: 'tincho@test.com',
      displayName: 'Tincho',
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      gymId: gymId,
    );

List<Override> _baseOverrides({
  required AsyncValue<CheckIn?> todayCheckIn,
  UserProfile? profile,
}) =>
    [
      feedSegmentProvider.overrideWith((ref) => FeedSegment.amigos),
      myFriendsFeedProvider.overrideWith((ref) async => const <Post>[]),
      myGymFeedProvider.overrideWith((ref) async => null),
      feedPublicProvider.overrideWith((ref) async => const <Post>[]),
      currentUidProvider.overrideWithValue('u1'),
      userProfileProvider.overrideWith(
        (ref) => Stream.value(profile ?? _makeProfile()),
      ),
      todayCheckInProvider.overrideWith(
        (ref) async {
          if (todayCheckIn is AsyncData<CheckIn?>) {
            return todayCheckIn.value;
          }
          // Never resolve for pending case
          await Completer<CheckIn?>().future;
          return null;
        },
      ),
    ];

Widget _wrapFeed(List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: FeedScreen()),
      ),
    );

// ── Tests ──────────────────────────────────────────────────────────────────────

void main() {
  group('FeedScreen check-in dialog trigger', () {
    testWidgets(
        'SCENARIO-335: dialog shown when todayCheckInProvider is null and dialog not yet shown',
        (tester) async {
      await tester.pumpWidget(
        _wrapFeed(
          _baseOverrides(
            todayCheckIn: const AsyncData(null),
          ),
        ),
      );

      // Pump once to allow initState + addPostFrameCallback to fire
      await tester.pump();
      // Pump again to allow showDialog to complete
      await tester.pumpAndSettle();

      expect(find.byType(CheckInDialog), findsOneWidget);
      expect(find.text('¿ESTÁS EN EL GYM HOY?'), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-336: dialog NOT shown when todayCheckInProvider has existing CheckIn',
        (tester) async {
      final existingCheckIn = CheckIn(
        uid: 'u1',
        date: CheckIn.dateKey(DateTime.now().toLocal()),
        checkedInAt: DateTime.now().toUtc(),
      );

      await tester.pumpWidget(
        _wrapFeed(
          _baseOverrides(
            todayCheckIn: AsyncData(existingCheckIn),
          ),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(CheckInDialog), findsNothing);
    });

    testWidgets(
        'once-per-session guard: dialog not shown again after dismissal',
        (tester) async {
      // Create a shared ProviderContainer so the session flag persists
      final container = ProviderContainer(
        overrides: _baseOverrides(
          todayCheckIn: const AsyncData(null),
        ),
      );
      addTearDown(container.dispose);

      Widget buildFeed() => UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: const Scaffold(body: FeedScreen()),
            ),
          );

      // First mount — dialog should appear
      await tester.pumpWidget(buildFeed());
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(CheckInDialog), findsOneWidget);

      // Dismiss dialog by tapping NO
      await tester.tap(find.text('NO'));
      await tester.pumpAndSettle();

      expect(find.byType(CheckInDialog), findsNothing);

      // Remount FeedScreen (simulates tab switch) — dialog should NOT appear again
      await tester.pumpWidget(buildFeed());
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(CheckInDialog), findsNothing);
    });
  });
}
