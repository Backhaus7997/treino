import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/post_providers.dart';
import 'package:treino/features/feed/application/reaction_providers.dart';
import 'package:treino/features/feed/domain/post.dart';
import 'package:treino/features/feed/domain/post_privacy.dart';
import 'package:treino/features/feed/domain/reaction_type.dart';
import 'package:treino/features/feed/presentation/post_detail_screen.dart';
import 'package:treino/features/feed/presentation/widgets/post_card.dart';
import 'package:treino/l10n/app_l10n.dart';

Post _post() => Post(
      id: 'post-42',
      authorUid: 'author-1',
      authorDisplayName: 'Sofía',
      authorAvatarUrl: null,
      authorGymId: null,
      text: 'Entreno terminado',
      routineTag: null,
      privacy: PostPrivacy.public,
      createdAt: DateTime.utc(2026, 7, 31),
    );

Widget _subject(Stream<Post?> Function(String postId) streamForPost) {
  return ProviderScope(
    overrides: [
      authStateChangesProvider.overrideWith((_) => Stream.value(null)),
      postByIdProvider.overrideWith(
        (_, postId) => streamForPost(postId),
      ),
      reactionCountsProvider.overrideWith(
        (_, __) => Stream.value(const <ReactionType, int>{}),
      ),
      myReactionProvider.overrideWith((_, __) => Stream.value(null)),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      locale: const Locale('es', 'AR'),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      home: const Scaffold(
        body: PostDetailScreen(postId: 'post-42'),
      ),
    ),
  );
}

void main() {
  testWidgets('renders the requested post when it exists', (tester) async {
    String? requestedId;

    await tester.pumpWidget(_subject((postId) {
      requestedId = postId;
      return Stream.value(_post());
    }));
    await tester.pumpAndSettle();

    expect(requestedId, equals('post-42'));
    expect(find.byType(PostCard), findsOneWidget);
    expect(find.text('Entreno terminado'), findsOneWidget);
  });

  testWidgets('missing post renders the unavailable state', (tester) async {
    await tester.pumpWidget(_subject((_) => Stream.value(null)));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('post-detail-unavailable')),
      findsOneWidget,
    );
    expect(find.text('Este post ya no está disponible.'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('stream error renders the same unavailable state with retry',
      (tester) async {
    await tester.pumpWidget(
      _subject(
        (_) => Stream<Post?>.error(Exception('permission-denied')),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('post-detail-unavailable')),
      findsOneWidget,
    );
    expect(find.text('Este post ya no está disponible.'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.textContaining('permission-denied'), findsNothing);
  });

  testWidgets('renders loading while the post stream has not emitted',
      (tester) async {
    final controller = StreamController<Post?>();

    await tester.pumpWidget(_subject((_) => controller.stream));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('post-detail-loading')),
      findsOneWidget,
    );

    await controller.close();
  });
}
