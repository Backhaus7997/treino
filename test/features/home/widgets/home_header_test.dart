import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/home/widgets/home_header.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

Widget _wrap(Widget w) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: w),
    );

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

void main() {
  group('HomeHeader', () {
    testWidgets(
        'REQ-HOME-HEADER-001: named greeting uppercased "HOLA, MARTÍN!"',
        (tester) async {
      await tester.pumpWidget(_wrap(
        HomeHeader(profile: makeProfile(displayName: 'Martín')),
      ));
      await tester.pump();
      expect(find.text('HOLA, MARTÍN!'), findsOneWidget);
    });

    testWidgets(
        'REQ-HOME-HEADER-001: lowercase displayName is uppercased "HOLA, ANA!"',
        (tester) async {
      await tester.pumpWidget(_wrap(
        HomeHeader(profile: makeProfile(displayName: 'ana')),
      ));
      await tester.pump();
      expect(find.text('HOLA, ANA!'), findsOneWidget);
    });

    testWidgets(
        'REQ-HOME-HEADER-002: null profile → "HOLA!" fallback, no "HOLA, "',
        (tester) async {
      await tester.pumpWidget(_wrap(const HomeHeader(profile: null)));
      await tester.pump();
      expect(find.text('HOLA!'), findsOneWidget);
      expect(find.textContaining(RegExp(r'HOLA, ')), findsNothing);
    });

    testWidgets(
        'REQ-HOME-HEADER-002: profile with null displayName → "HOLA!" fallback',
        (tester) async {
      await tester.pumpWidget(_wrap(
        HomeHeader(profile: makeProfile(displayName: null)),
      ));
      await tester.pump();
      expect(find.text('HOLA!'), findsOneWidget);
      expect(find.textContaining(RegExp(r'HOLA, ')), findsNothing);
    });

    testWidgets(
        'REQ-HOME-HEADER-003: non-null avatarUrl → CachedNetworkImage found',
        (tester) async {
      await tester.pumpWidget(_wrap(
        HomeHeader(
          profile: makeProfile(
            displayName: 'Ana',
            avatarUrl: 'https://example.com/avatar.jpg',
          ),
        ),
      ));
      await tester.pump();
      expect(find.byType(CachedNetworkImage), findsAtLeastNWidgets(1));
    });

    testWidgets(
        'REQ-HOME-HEADER-004: null avatarUrl with displayName → initials "M", no CachedNetworkImage',
        (tester) async {
      await tester.pumpWidget(_wrap(
        HomeHeader(
            profile: makeProfile(displayName: 'Martín', avatarUrl: null)),
      ));
      await tester.pump();
      expect(find.text('M'), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets(
        'REQ-HOME-HEADER-004: null profile → initials "?", no CachedNetworkImage',
        (tester) async {
      await tester.pumpWidget(_wrap(const HomeHeader(profile: null)));
      await tester.pump();
      expect(find.text('?'), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });
  });
}
