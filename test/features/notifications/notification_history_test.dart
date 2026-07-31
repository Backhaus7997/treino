import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';
import 'package:treino/features/feed/application/friendship_providers.dart';
import 'package:treino/features/notifications/application/notification_history_providers.dart';
import 'package:treino/features/notifications/data/notification_history_repository.dart';
import 'package:treino/features/notifications/domain/notification_history_item.dart';
import 'package:treino/features/notifications/presentation/notification_history_screen.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

NotificationHistoryItem _item({
  String id = 'n1',
  DateTime? createdAt,
  String deepLink = '/target',
}) =>
    NotificationHistoryItem(
      id: id,
      kind: NotificationKind.reaction,
      title: 'Nueva reacción',
      body: 'A alguien le gustó tu post',
      deepLink: deepLink,
      createdAt: createdAt ?? DateTime.utc(2026, 7, 31, 12),
    );

class _FakeRepository implements NotificationHistoryRepository {
  int markSeenCalls = 0;

  @override
  Future<void> markSeen(String uid) async {
    markSeenCalls++;
  }

  @override
  Stream<DateTime?> watchLastSeenAt(String uid) => Stream.value(null);

  @override
  Stream<List<NotificationHistoryItem>> watchLatest(String uid) =>
      Stream.value(const []);
}

Widget _app({
  required _FakeRepository repository,
  required Stream<List<NotificationHistoryItem>> notifications,
  Stream<DateTime?>? lastSeen,
  int pending = 0,
}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const NotificationHistoryScreen(),
      ),
      GoRoute(
        path: '/target',
        builder: (_, __) => const Scaffold(body: Text('TARGET')),
      ),
      GoRoute(
        path: '/feed/friend-requests',
        builder: (_, __) => const Scaffold(body: Text('REQUESTS')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      currentUidProvider.overrideWithValue('u1'),
      notificationHistoryRepositoryProvider.overrideWithValue(repository),
      notificationHistoryProvider.overrideWith((ref) => notifications),
      notificationLastSeenAtProvider.overrideWith(
        (ref) => lastSeen ?? Stream.value(null),
      ),
      pendingRequestCountProvider.overrideWith((ref, uid) => pending),
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
  test('newer createdAt than lastSeenAt is unread', () {
    final notification = _item(createdAt: DateTime.utc(2026, 7, 31, 12));
    expect(
      notificationIsUnread(notification, DateTime.utc(2026, 7, 31, 11)),
      isTrue,
    );
  });

  test('absent lastSeenAt makes every notification unread', () {
    final notifications = [_item(), _item(id: 'n2')];
    expect(
      notifications.where((item) => notificationIsUnread(item, null)).length,
      notifications.length,
    );
  });

  test('unknown kind parses without crashing', () {
    final item = NotificationHistoryItem.fromJson(
      {
        'kind': 'added-by-new-backend',
        'title': 'Title',
        'body': 'Body',
        'deepLink': '/feed',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026)),
      },
      id: 'n1',
    );
    expect(item.kind, NotificationKind.unknown);
  });

  test('badge sums unread notifications and pending requests', () async {
    final container = ProviderContainer(
      overrides: [
        currentUidProvider.overrideWithValue('u1'),
        notificationHistoryProvider.overrideWith(
          (ref) => Stream.value([_item(), _item(id: 'n2')]),
        ),
        notificationLastSeenAtProvider.overrideWith(
          (ref) => Stream.value(null),
        ),
        pendingRequestCountProvider.overrideWith((ref, uid) => 3),
      ],
    );
    addTearDown(container.dispose);
    await container.read(notificationHistoryProvider.future);
    await container.read(notificationLastSeenAtProvider.future);
    expect(container.read(notificationHeaderBadgeProvider('u1')), 5);
  });

  testWidgets('opening screen marks last seen exactly once', (tester) async {
    final repository = _FakeRepository();
    await tester.pumpWidget(
      _app(repository: repository, notifications: Stream.value(const [])),
    );
    await tester.pump();
    await tester.pump();
    expect(repository.markSeenCalls, 1);
  });

  testWidgets('tapping an item navigates to its deepLink', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final repository = _FakeRepository();
    await tester.pumpWidget(
      _app(repository: repository, notifications: Stream.value([_item()])),
    );
    await tester.pumpAndSettle();
    final semantics = tester.getSemantics(
      find.byKey(const Key('notificationItem-n1')),
    );
    expect(semantics.label, contains('Nueva reacción'));
    await tester.tap(find.byKey(const Key('notificationItem-n1')));
    await tester.pumpAndSettle();
    expect(find.text('TARGET'), findsOneWidget);
    semanticsHandle.dispose();
  });

  // Cada estado va en su propio test y no en pumpWidget sucesivos sobre el
  // mismo tester: Flutter reusa el elemento del ProviderScope en vez de
  // recrearlo, así que Riverpod conserva los overrides del primer pump y los
  // nuevos nunca entran. El segundo estado que se probara así siempre
  // fallaría, aunque el widget esté bien.

  testWidgets('renders the loading state while the stream has no value',
      (tester) async {
    await tester.pumpWidget(
      _app(repository: _FakeRepository(), notifications: const Stream.empty()),
    );

    expect(find.byKey(const Key('notificationHistoryLoading')), findsOneWidget);
  });

  testWidgets('renders the error state when the stream fails', (tester) async {
    await tester.pumpWidget(
      _app(
        repository: _FakeRepository(),
        notifications: Stream.error(StateError('boom')),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('notificationHistoryError')), findsOneWidget);
  });

  testWidgets('renders the empty state when there are no notifications',
      (tester) async {
    await tester.pumpWidget(
      _app(
          repository: _FakeRepository(), notifications: Stream.value(const [])),
    );
    await tester.pump();

    expect(find.byKey(const Key('notificationHistoryEmpty')), findsOneWidget);
  });

  testWidgets('hides the pending requests section when the count is zero',
      (tester) async {
    await tester.pumpWidget(
      _app(
          repository: _FakeRepository(), notifications: Stream.value(const [])),
    );
    await tester.pump();

    expect(find.byKey(const Key('notificationPendingRequests')), findsNothing);
  });

  testWidgets('shows the pending requests section when the count is positive',
      (tester) async {
    await tester.pumpWidget(
      _app(
        repository: _FakeRepository(),
        notifications: Stream.value(const []),
        pending: 2,
      ),
    );
    await tester.pump();

    expect(
        find.byKey(const Key('notificationPendingRequests')), findsOneWidget);
  });

  testWidgets('lazy list subtree has no TreinoFadeSlideIn', (tester) async {
    final repository = _FakeRepository();
    await tester.pumpWidget(
      _app(repository: repository, notifications: Stream.value([_item()])),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TreinoFadeSlideIn), findsNothing);
  });
}
