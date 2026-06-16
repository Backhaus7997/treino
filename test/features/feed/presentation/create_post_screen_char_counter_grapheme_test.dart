import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/feed/presentation/create_post_screen.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

// ---------------------------------------------------------------------------
// Regression test for the char counter grapheme/UTF-16 mismatch.
//
// CreatePostState.canSubmit gates on text.characters.length (grapheme
// clusters), but the on-screen counter previously displayed text.length
// (UTF-16 code units). With emoji or composed characters the two disagreed,
// so the counter could show "over limit" red while PUBLICAR stayed enabled
// (or vice versa). The counter must use the same grapheme count as canSubmit.
// ---------------------------------------------------------------------------

UserProfile _makeProfile() => UserProfile(
      uid: 'u1',
      email: 'tincho@test.com',
      displayName: 'Tincho',
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

Widget _wrapWithRouter() {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () => ctx.push('/create'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/create',
        builder: (_, __) => const Scaffold(body: CreatePostScreen()),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      userProfileProvider.overrideWith((ref) => Stream.value(_makeProfile())),
    ],
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      routerConfig: router,
    ),
  );
}

Future<void> _openCreatePost(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'char counter counts grapheme clusters (emoji = 1), matching canSubmit',
      (tester) async {
    await tester.pumpWidget(_wrapWithRouter());
    await _openCreatePost(tester);

    // 👍 is a single grapheme cluster but 2 UTF-16 code units.
    await tester.enterText(find.byType(TextField), '👍');
    await tester.pump();

    // Counter must report the grapheme count (1), not UTF-16 length (2).
    expect(find.text('1 / 280'), findsOneWidget);
    expect(find.text('2 / 280'), findsNothing);
  });
}
