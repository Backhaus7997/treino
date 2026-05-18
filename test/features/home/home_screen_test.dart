import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_background.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/home/home_screen.dart';
import 'package:treino/features/home/widgets/empezar_entrenamiento_card.dart';
import 'package:treino/features/home/widgets/esta_semana_card.dart';
import 'package:treino/features/home/widgets/home_header.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/features/workout/domain/set_log.dart';

UserProfile makeProfile({
  String? displayName = 'Martín',
  String? avatarUrl,
  String uid = 'u1',
  String email = 'u1@test.com',
}) =>
    UserProfile(
      uid: uid,
      email: email,
      displayName: displayName,
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026, 5, 12),
      updatedAt: DateTime.utc(2026, 5, 12),
      avatarUrl: avatarUrl,
    );

Session makeStubSession({DateTime? startedAt}) => Session(
      id: 'stub-session-001',
      uid: 'u1',
      routineId: 'r1',
      routineName: 'Push',
      startedAt: startedAt ?? DateTime.utc(2026, 5, 18, 18, 42),
      status: SessionStatus.active,
      dayNumber: 1,
    );

Widget _wrapWithOverrides(Widget w, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: w),
      ),
    );

void main() {
  group('HomeScreen', () {
    testWidgets(
        'REQ-HOME-SCREEN-001: AsyncData(profile) → HomeHeader, EmpezarEntrenamientoCard, EstaSemanaCard each found once',
        (tester) async {
      final profile = makeProfile();
      await tester.pumpWidget(_wrapWithOverrides(
        const HomeScreen(),
        [
          userProfileProvider.overrideWith(
            (ref) => Stream.value(profile),
          ),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(HomeHeader), findsOneWidget);
      expect(find.byType(EmpezarEntrenamientoCard), findsOneWidget);
      expect(find.byType(EstaSemanaCard), findsOneWidget);
    });

    testWidgets(
        'REQ-HOME-SCREEN-001 / REQ-HOME-PROVIDER-003: AsyncLoading → no HomeHeader, skeleton present, cards still visible',
        (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const HomeScreen(),
        [
          userProfileProvider.overrideWith(
            (ref) => const Stream<UserProfile?>.empty(),
          ),
        ],
      ));
      // Single pump — do NOT settle so the provider stays in AsyncLoading
      await tester.pump();

      expect(find.byType(HomeHeader), findsNothing);
      // Skeleton is a SizedBox(height: 56)
      expect(
        find.byWidgetPredicate(
          (w) => w is SizedBox && (w.height ?? 0) > 0,
        ),
        findsAtLeastNWidgets(1),
      );
      expect(find.byType(EmpezarEntrenamientoCard), findsOneWidget);
      expect(find.byType(EstaSemanaCard), findsOneWidget);
    });

    testWidgets(
        'REQ-HOME-SCREEN-001 / REQ-HOME-PROVIDER-004: AsyncError → no FlutterError, "HOLA!" shown, no error text',
        (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const HomeScreen(),
        [
          userProfileProvider.overrideWith(
            (ref) => Stream<UserProfile?>.error(Exception('network')),
          ),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('HOLA!'), findsOneWidget);
      expect(
        find.textContaining(RegExp(r'[Ee]rror|[Ee]xcepci')),
        findsNothing,
      );
    });

    testWidgets(
        'REQ-HOME-SCREEN-002: no Scaffold/AppBackground/SafeArea inside HomeScreen',
        (tester) async {
      final profile = makeProfile();
      await tester.pumpWidget(_wrapWithOverrides(
        const HomeScreen(),
        [
          userProfileProvider.overrideWith(
            (ref) => Stream.value(profile),
          ),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));

      // Exactly 1 Scaffold — the outer test wrapper's
      expect(find.byType(Scaffold), findsOneWidget);
      // Zero AppBackground inside HomeScreen's subtree
      expect(find.byType(AppBackground), findsNothing);
      // Zero SafeArea
      expect(find.byType(SafeArea), findsNothing);
    });

    testWidgets(
        'REQ-HOME-SCREEN-003: AsyncData(profile) → HomeHeader.profile equals overridden profile',
        (tester) async {
      final profile = makeProfile();
      await tester.pumpWidget(_wrapWithOverrides(
        const HomeScreen(),
        [
          userProfileProvider.overrideWith(
            (ref) => Stream.value(profile),
          ),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));

      final header = tester.widget<HomeHeader>(find.byType(HomeHeader));
      expect(header.profile, equals(profile));
    });

    testWidgets(
        'REQ-HOME-SCREEN-003: AsyncData(null) → HomeHeader.profile is null + "HOLA!" + no CachedNetworkImage',
        (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const HomeScreen(),
        [
          userProfileProvider.overrideWith(
            (ref) => Stream<UserProfile?>.value(null),
          ),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));

      final header = tester.widget<HomeHeader>(find.byType(HomeHeader));
      expect(header.profile, isNull);
      expect(find.text('HOLA!'), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets(
        'REQ-HOME-PROVIDER-001: AsyncData with displayName+avatarUrl → correct greeting + CachedNetworkImage',
        (tester) async {
      final profile = makeProfile(
        displayName: 'Martín',
        avatarUrl: 'https://example.com/avatar.jpg',
      );
      await tester.pumpWidget(_wrapWithOverrides(
        const HomeScreen(),
        [
          userProfileProvider.overrideWith(
            (ref) => Stream.value(profile),
          ),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('HOLA, MARTÍN!'), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsAtLeastNWidgets(1));
    });

    // ── Resume listener (REQ-SESSION-RESUME-002) ─────────────────────────────

    testWidgets(
        'SCENARIO-325: activeSessionForUidProvider returns non-null → ResumeSessionModal aparece',
        (tester) async {
      final profile = makeProfile();
      await tester.pumpWidget(_wrapWithOverrides(
        const HomeScreen(),
        [
          userProfileProvider.overrideWith((ref) => Stream.value(profile)),
          activeSessionForUidProvider.overrideWith(
            (ref) async => (session: makeStubSession(), setLogs: <SetLog>[]),
          ),
        ],
      ));
      // Initial pump + extra pumps to let the FutureProvider resolve and
      // the post-frame callback fire.
      await tester.pumpAndSettle();

      expect(find.text('Entrenamiento en curso'), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-326: activeSessionForUidProvider returns null → sin modal, Home normal',
        (tester) async {
      final profile = makeProfile();
      await tester.pumpWidget(_wrapWithOverrides(
        const HomeScreen(),
        [
          userProfileProvider.overrideWith((ref) => Stream.value(profile)),
          activeSessionForUidProvider.overrideWith((ref) async => null),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Entrenamiento en curso'), findsNothing);
      expect(find.byType(EmpezarEntrenamientoCard), findsOneWidget);
      expect(find.byType(EstaSemanaCard), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-327: activeSessionForUidProvider AsyncLoading → Home renderiza sin modal',
        (tester) async {
      final profile = makeProfile();
      // Override with a Future that never completes during this pump.
      final completer = Completer<({Session session, List<SetLog> setLogs})?>();
      addTearDown(() {
        if (!completer.isCompleted) completer.complete(null);
      });
      await tester.pumpWidget(_wrapWithOverrides(
        const HomeScreen(),
        [
          userProfileProvider.overrideWith((ref) => Stream.value(profile)),
          activeSessionForUidProvider.overrideWith((ref) => completer.future),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Entrenamiento en curso'), findsNothing);
      expect(find.byType(HomeHeader), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-328: activeSessionForUidProvider AsyncError → Home renderiza sin modal',
        (tester) async {
      final profile = makeProfile();
      await tester.pumpWidget(_wrapWithOverrides(
        const HomeScreen(),
        [
          userProfileProvider.overrideWith((ref) => Stream.value(profile)),
          activeSessionForUidProvider.overrideWith(
            (ref) => Future.error(Exception('network')),
          ),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Entrenamiento en curso'), findsNothing);
      expect(find.byType(HomeHeader), findsOneWidget);
    });
  });
}
