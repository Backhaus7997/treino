import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/friendship_providers.dart';
import 'package:treino/features/profile/application/profile_stats_providers.dart';
import 'package:treino/features/profile/domain/user_session_stats.dart';
import 'package:treino/features/profile/presentation/widgets/profile_friend_requests_tile.dart';
import 'package:treino/features/profile/profile_screen.dart';

/// Minimal [AuthNotifier] stub that does not call Firebase.
class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier({User? user}) : _user = user;
  final User? _user;

  @override
  Future<User?> build() async => _user;

  @override
  Future<void> signOut() async {}
}

Widget _buildScreen({required List<Override> overrides}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(body: ProfileScreen()),
    ),
  );
}

void main() {
  group('ProfileScreen — stats row (SCENARIO-316..319)', () {
    // SCENARIO-317: Stats row shows dashes while loading
    testWidgets('SCENARIO-317: loading state shows "--" for all stats',
        (tester) async {
      // Use a Completer that never completes to keep the provider in loading.
      final completer = Completer<UserSessionStats>();

      await tester.pumpWidget(
        _buildScreen(overrides: [
          authNotifierProvider.overrideWith(_StubAuthNotifier.new),
          userSessionStatsProvider.overrideWith((_) => completer.future),
        ]),
      );

      // Pump once — still in loading state.
      await tester.pump();

      // All three stat labels should be visible.
      expect(find.text('SESIONES'), findsOneWidget);
      expect(find.text('VOLUMEN KG'), findsOneWidget);
      expect(find.text('RACHA'), findsOneWidget);

      // All three values should be '--'.
      expect(find.text('--'), findsNWidgets(3));

      // Complete the future before disposal to avoid pending timer assertion.
      completer.completeError(Exception('cleanup'));
    });

    // SCENARIO-316: Stats row renders with data
    testWidgets('SCENARIO-316: data state renders real stat values',
        (tester) async {
      await tester.pumpWidget(
        _buildScreen(overrides: [
          authNotifierProvider.overrideWith(_StubAuthNotifier.new),
          userSessionStatsProvider.overrideWith((_) async =>
              const UserSessionStats(
                  totalSessions: 42, totalVolumeKg: 15000.0, streak: 7)),
        ]),
      );

      await tester.pump(); // provider resolves synchronously in tests

      expect(find.text('SESIONES'), findsOneWidget);
      expect(find.text('42'), findsOneWidget); // totalSessions
      expect(find.text('VOLUMEN KG'), findsOneWidget);
      expect(find.text('15k'), findsOneWidget); // kFormat(15000)
      expect(find.text('RACHA'), findsOneWidget);
      expect(find.text('7'), findsOneWidget); // streak
    });

    // SCENARIO-318: Stats row shows dashes on error
    testWidgets('SCENARIO-318: error state shows "--" for all stats',
        (tester) async {
      await tester.pumpWidget(
        _buildScreen(overrides: [
          authNotifierProvider.overrideWith(_StubAuthNotifier.new),
          userSessionStatsProvider.overrideWith((_) async {
            throw Exception('Firestore unavailable');
          }),
        ]),
      );

      await tester.pump(); // let error propagate

      expect(find.text('SESIONES'), findsOneWidget);
      expect(find.text('VOLUMEN KG'), findsOneWidget);
      expect(find.text('RACHA'), findsOneWidget);
      expect(find.text('--'), findsNWidgets(3));
    });

    // SCENARIO-319: Existing ProfileScreen content is preserved
    testWidgets(
        'SCENARIO-319: PERFIL text and sign-out button are always visible',
        (tester) async {
      await tester.pumpWidget(
        _buildScreen(overrides: [
          authNotifierProvider.overrideWith(_StubAuthNotifier.new),
          userSessionStatsProvider.overrideWith((_) async =>
              const UserSessionStats(
                  totalSessions: 0, totalVolumeKg: 0, streak: 0)),
        ]),
      );

      await tester.pump();

      // PERFIL heading and sign-out button must survive regardless of stats.
      expect(find.text('PERFIL'), findsOneWidget);
      expect(find.text('Cerrar sesión'), findsOneWidget);
    });

    // Additional: color semantics — RACHA uses highlight (magenta), SESIONES uses accent
    testWidgets('color semantics: stats row uses AppPalette correctly',
        (tester) async {
      await tester.pumpWidget(
        _buildScreen(overrides: [
          authNotifierProvider.overrideWith(_StubAuthNotifier.new),
          userSessionStatsProvider.overrideWith((_) async =>
              const UserSessionStats(
                  totalSessions: 10, totalVolumeKg: 2000, streak: 5)),
        ]),
      );

      await tester.pump();

      // Verify that data state renders — color assertions are via palette
      // constants since building context to call AppPalette.of() is complex.
      // The palette is minted via AppPalette.mintMagenta = the dark theme.
      // SESIONES + VOLUMEN KG value → mint accent (#2CE5A2)
      // RACHA value → magenta highlight (#C123E0)
      final sesionesValue = tester.widgetList<Text>(find.text('10')).first;
      expect(sesionesValue.style?.color, AppPalette.mintMagenta.accent);

      final rachaValue = tester.widgetList<Text>(find.text('5')).first;
      expect(rachaValue.style?.color, AppPalette.mintMagenta.highlight);
    });

    // SCENARIO-319 extension: sign-out button present even in loading state
    testWidgets('sign-out preserved in loading state', (tester) async {
      final completer = Completer<UserSessionStats>();

      await tester.pumpWidget(
        _buildScreen(overrides: [
          authNotifierProvider.overrideWith(_StubAuthNotifier.new),
          userSessionStatsProvider.overrideWith((_) => completer.future),
        ]),
      );

      await tester.pump();

      expect(find.text('PERFIL'), findsOneWidget);
      expect(find.text('Cerrar sesión'), findsOneWidget);

      completer.completeError(Exception('cleanup'));
    });
  });

  // ---------------------------------------------------------------------------
  // T14 RED: SCENARIO-468a — ProfileFriendRequestsTile is in the ProfileScreen
  // ---------------------------------------------------------------------------
  group('ProfileScreen — friend requests tile (SCENARIO-468a)', () {
    testWidgets(
        'SCENARIO-468a: ProfileScreen widget tree contains ProfileFriendRequestsTile',
        (tester) async {
      await tester.pumpWidget(
        _buildScreen(overrides: [
          authNotifierProvider.overrideWith(_StubAuthNotifier.new),
          authStateChangesProvider.overrideWith((_) => Stream.value(null)),
          userSessionStatsProvider.overrideWith((_) async =>
              const UserSessionStats(
                  totalSessions: 0, totalVolumeKg: 0, streak: 0)),
          pendingRequestCountProvider('').overrideWith((_) => 0),
        ]),
      );

      await tester.pump();

      expect(find.byType(ProfileFriendRequestsTile), findsOneWidget);
    });
  });
}
