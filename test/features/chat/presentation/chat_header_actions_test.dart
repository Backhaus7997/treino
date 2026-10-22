import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/chat/domain/message.dart';
import 'package:treino/features/chat/presentation/chat_screen.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

// Header del chat: tocar a la persona abre su perfil, y el ⋮ ofrece Ver
// perfil, Archivar y Eliminar chat. Las escrituras van contra un Firestore
// falso con el repo REAL: un repo mockeado tapa lo que escribe de verdad.

const _chatPath = '/coach/chat/aaa_bbb?other=bbb';
const _profilePath = '/coach/chat/aaa_bbb/profile/bbb';

late FakeFirebaseFirestore _firestore;

Future<Map<String, Object?>> _chatDoc() async =>
    (await _firestore.collection('chats').doc('aaa_bbb').get()).data()!;

/// Router con la bandeja debajo y el chat empujado encima, como llega en la
/// app. La ruta del perfil replica la que cuelga del chat en `router.dart`.
GoRouter _router() {
  final router = GoRouter(
    initialLocation: '/feed/messages',
    routes: [
      GoRoute(
        path: '/feed/messages',
        builder: (_, __) => const Scaffold(body: Text('BANDEJA')),
      ),
      GoRoute(
        path: '/coach/chat/:chatId',
        builder: (_, state) => ChatScreen(
          chatId: state.pathParameters['chatId']!,
          otherUid: state.uri.queryParameters['other'] ?? '',
        ),
        routes: [
          GoRoute(
            path: 'profile/:uid',
            builder: (_, state) =>
                Scaffold(body: Text('PERFIL ${state.pathParameters['uid']}')),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  return router;
}

Future<GoRouter> _pumpChat(
  WidgetTester tester, {
  UserPublicProfile? other,
}) async {
  final router = _router();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(_firestore),
        currentUidProvider.overrideWith((_) => 'aaa'),
        messagesProvider('aaa_bbb').overrideWith(
          (_) => Stream.value(const <Message>[]),
        ),
        userPublicProfileProvider('bbb').overrideWith(
          (_) => Stream.value(other),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        locale: const Locale('es', 'AR'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  router.push(_chatPath);
  await tester.pumpAndSettle();
  return router;
}

const _nicolas = UserPublicProfile(
  uid: 'bbb',
  displayName: 'Nicolas',
  displayNameLowercase: 'nicolas',
  gymName: 'Megatlon Palermo',
);

String _location(GoRouter router) => router.state.uri.toString();

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Opciones del chat'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    _firestore = FakeFirebaseFirestore();
    await _firestore.collection('chats').doc('aaa_bbb').set({
      'chatId': 'aaa_bbb',
      'members': ['aaa', 'bbb'],
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 9, 1)),
      'lastMessageAt': Timestamp.fromDate(DateTime.utc(2026, 10, 1)),
    });
  });

  group('header', () {
    testWidgets('nombre, y el gym como línea secundaria sin relación',
        (tester) async {
      await _pumpChat(tester, other: _nicolas);

      expect(find.text('NICOLAS'), findsOneWidget);
      expect(find.text('Megatlon Palermo'), findsOneWidget);
    });

    testWidgets('«Lo seguís» le gana al gym si lo sigo', (tester) async {
      await _firestore.collection('follows').doc('aaa_bbb').set({
        'id': 'aaa_bbb',
        'followerUid': 'aaa',
        'followeeUid': 'bbb',
        'status': 'accepted',
        'members': ['aaa', 'bbb'],
        'createdAt': Timestamp.now(),
      });
      await _pumpChat(tester, other: _nicolas);

      expect(find.text('Lo seguís'), findsOneWidget);
      expect(find.text('Megatlon Palermo'), findsNothing);
    });

    testWidgets('tocar a la persona abre su perfil público', (tester) async {
      final router = await _pumpChat(tester, other: _nicolas);

      await tester.tap(find.text('NICOLAS'));
      await tester.pumpAndSettle();

      expect(_location(router), _profilePath);
      expect(find.text('PERFIL bbb'), findsOneWidget);

      // Volver deja el chat donde estaba, no la bandeja.
      router.pop();
      await tester.pumpAndSettle();
      expect(_location(router), _chatPath);
    });

    testWidgets('control negativo: cuenta eliminada no abre ningún perfil',
        (tester) async {
      final router = await _pumpChat(tester, other: null);

      await tester.tap(find.text('USUARIO ELIMINADO'));
      await tester.pumpAndSettle();
      expect(_location(router), _chatPath);

      await _openMenu(tester);
      expect(find.text('Ver perfil'), findsNothing);
      expect(find.text('Archivar'), findsOneWidget);
    });
  });

  group('menú ⋮', () {
    testWidgets('muestra Ver perfil, Archivar y Eliminar chat', (tester) async {
      await _pumpChat(tester, other: _nicolas);
      await _openMenu(tester);

      expect(find.text('Ver perfil'), findsOneWidget);
      expect(find.text('Archivar'), findsOneWidget);
      expect(find.text('Eliminar chat'), findsOneWidget);
    });

    testWidgets('Ver perfil navega al perfil del otro', (tester) async {
      final router = await _pumpChat(tester, other: _nicolas);
      await _openMenu(tester);

      await tester.tap(find.text('Ver perfil'));
      await tester.pumpAndSettle();

      expect(_location(router), _profilePath);
      expect((await _chatDoc()).containsKey('archivedAt'), isFalse);
    });

    testWidgets(
        'Archivar escribe sólo mi entrada, avisa con Deshacer y vuelve a la '
        'bandeja', (tester) async {
      final router = await _pumpChat(tester, other: _nicolas);
      await _openMenu(tester);

      await tester.tap(find.text('Archivar'));
      await tester.runAsync(() => pumpEventQueue());
      await tester.pumpAndSettle();

      expect(((await _chatDoc())['archivedAt']! as Map).keys, ['aaa']);
      expect(find.text('Chat archivado'), findsOneWidget);
      expect(find.text('Deshacer'), findsOneWidget);
      expect(_location(router), '/feed/messages');
    });

    testWidgets('un chat archivado ofrece Desarchivar', (tester) async {
      await _firestore.collection('chats').doc('aaa_bbb').update({
        'archivedAt.aaa': Timestamp.fromDate(DateTime.utc(2026, 10, 2)),
      });
      await _pumpChat(tester, other: _nicolas);
      await _openMenu(tester);

      expect(find.text('Desarchivar'), findsOneWidget);
      await tester.tap(find.text('Desarchivar'));
      await tester.runAsync(() => pumpEventQueue());
      await tester.pumpAndSettle();

      expect((await _chatDoc())['archivedAt'], isEmpty);
    });

    testWidgets(
        'Eliminar pide confirmación: cancelar no escribe ni sale; confirmar '
        'elimina y vuelve a la bandeja', (tester) async {
      final router = await _pumpChat(tester, other: _nicolas);

      await _openMenu(tester);
      await tester.tap(find.text('Eliminar chat'));
      await tester.pumpAndSettle();
      expect(find.text('¿Eliminar el chat?'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect((await _chatDoc()).containsKey('hiddenBefore'), isFalse);
      expect(_location(router), _chatPath);

      await _openMenu(tester);
      await tester.tap(find.text('Eliminar chat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar'));
      await tester.runAsync(() => pumpEventQueue());
      await tester.pumpAndSettle();

      expect(((await _chatDoc())['hiddenBefore']! as Map).keys, ['aaa']);
      expect(find.text('Chat eliminado'), findsOneWidget);
      expect(_location(router), '/feed/messages');
    });
  });
}
