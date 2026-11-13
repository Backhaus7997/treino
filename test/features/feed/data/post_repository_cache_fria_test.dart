// Regresión del feed sin red (QA E2E 2026-11-06, Web 2/2 y Android): sin
// conexión las tres pestañas decían «no hay posts» en vez de un error con
// Reintentar. Un `.get()` de una query no falla sin red: con la caché fría
// devuelve un `QuerySnapshot` VACÍO con `isFromCache == true`, y el repo lo
// convertía en una página vacía (mismo agujero que
// `trainer_link_repository_cache_fria_test.dart`).
//
// `fake_cloud_firestore` no modela `isFromCache`, así que se mockea con
// mocktail la cadena real de cada query y se ejercita `PostRepository` de
// verdad. Los documentos se generan reales con una `FakeFirebaseFirestore`
// auxiliar (`QueryDocumentSnapshot` es `@sealed`).

// `CollectionReference` y `Query` están `@sealed` en `cloud_firestore`.
// Mockearlas es la ÚNICA forma de controlar `metadata.isFromCache`.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/feed/application/feed_screen_providers.dart';
import 'package:treino/features/feed/application/follow_providers.dart';
import 'package:treino/features/feed/application/post_providers.dart';
import 'package:treino/features/feed/data/post_repository.dart';
import 'package:treino/features/feed/domain/feed_segment.dart';
import 'package:treino/features/feed/domain/post.dart';
import 'package:treino/features/feed/domain/post_privacy.dart';
import 'package:treino/features/feed/feed_screen.dart';
import 'package:treino/features/moderation/application/moderation_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

class _MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class _MockCollectionReference extends Mock
    implements CollectionReference<Map<String, Object?>> {}

class _MockQuery extends Mock implements Query<Map<String, Object?>> {}

class _MockQuerySnapshot extends Mock
    implements QuerySnapshot<Map<String, Object?>> {}

class _MockSnapshotMetadata extends Mock implements SnapshotMetadata {}

class _MockUser extends Mock implements User {
  _MockUser({required String uid}) : _uid = uid;
  final String _uid;
  @override
  String get uid => _uid;
}

typedef _Docs = List<QueryDocumentSnapshot<Map<String, Object?>>>;

Post _post(String id, {PostPrivacy privacy = PostPrivacy.public}) => Post(
      id: id,
      authorUid: 'u2',
      authorDisplayName: 'Tincho',
      authorAvatarUrl: null,
      authorGymId: null,
      text: 'post $id',
      routineTag: null,
      privacy: privacy,
      createdAt: DateTime.utc(2026, 7, 27, 12),
    );

/// `QueryDocumentSnapshot` REALES (no mockeados) sembrados en una
/// `FakeFirebaseFirestore` auxiliar.
Future<_Docs> _realDocs(List<Post> posts) async {
  final aux = FakeFirebaseFirestore();
  for (final p in posts) {
    await aux.collection('posts').doc(p.id).set(p.toJson());
  }
  return (await aux.collection('posts').get()).docs;
}

QuerySnapshot<Map<String, Object?>> _snap({
  required _Docs docs,
  required bool isFromCache,
}) {
  final metadata = _MockSnapshotMetadata();
  when(() => metadata.isFromCache).thenReturn(isFromCache);
  final snap = _MockQuerySnapshot();
  when(() => snap.docs).thenReturn(docs);
  when(() => snap.metadata).thenReturn(metadata);
  return snap;
}

void main() {
  late _MockFirebaseFirestore firestore;
  late _MockCollectionReference posts;
  late _MockQuery terminal;
  late List<QuerySnapshot<Map<String, Object?>>> respuestas;
  late PostRepository repo;

  /// Cada `.get()` de la query terminal consume la próxima respuesta.
  Future<QuerySnapshot<Map<String, Object?>>> siguiente() async =>
      respuestas.removeAt(0);

  /// Engancha `queryAntesDeOrden` → orderBy → limit → get; los filtros que lo
  /// preceden los cablea cada grupo (lo que distingue una pestaña de otra).
  void cablearOrdenLimitGet(_MockQuery queryAntesDeOrden) {
    final ordenada = _MockQuery();
    when(
      () => queryAntesDeOrden.orderBy('createdAt', descending: true),
    ).thenReturn(ordenada);
    when(() => ordenada.limit(20)).thenReturn(terminal);
    when(() => terminal.get()).thenAnswer((_) => siguiente());
  }

  setUp(() {
    firestore = _MockFirebaseFirestore();
    posts = _MockCollectionReference();
    terminal = _MockQuery();
    respuestas = [];
    when(() => firestore.collection('posts')).thenReturn(posts);
    repo = PostRepository(firestore: firestore);
  });

  Matcher throwsUnavailable() => throwsA(
        isA<FirebaseException>().having((e) => e.code, 'code', 'unavailable'),
      );

  group('feedPublic', () {
    late _MockQuery porPrivacidad;

    setUp(() {
      porPrivacidad = _MockQuery();
      when(() => posts.where('privacy', isEqualTo: 'public'))
          .thenReturn(porPrivacidad);
      cablearOrdenLimitGet(porPrivacidad);
    });

    test('vacío DESDE CACHÉ → tira unavailable, no un "no hay posts"',
        () async {
      respuestas = [_snap(docs: const [], isFromCache: true)];

      await expectLater(repo.feedPublic(), throwsUnavailable());
    });

    test('vacío CONFIRMADO por el servidor → página vacía legítima', () async {
      respuestas = [_snap(docs: const [], isFromCache: false)];

      final page = await repo.feedPublic();

      expect(page.posts, isEmpty);
    });

    test('con posts en caché → se muestran (datos viejos pero reales)',
        () async {
      respuestas = [
        _snap(docs: await _realDocs([_post('a')]), isFromCache: true),
      ];

      final page = await repo.feedPublic();

      expect(page.posts.map((p) => p.id), ['a']);
    });

    test(
        'página siguiente vacía desde caché → también tira: loadMore '
        'conserva lo cargado en vez de concluir que no hay más', () async {
      final after = DateTime.utc(2026, 7, 27);
      final conCursor = _MockQuery();
      when(
        () => porPrivacidad.where(
          'createdAt',
          isLessThan: Timestamp.fromDate(after),
        ),
      ).thenReturn(conCursor);
      cablearOrdenLimitGet(conCursor);
      respuestas = [_snap(docs: const [], isFromCache: true)];

      await expectLater(repo.feedPublic(after: after), throwsUnavailable());
    });
  });

  group('feedForGym', () {
    setUp(() {
      final porPrivacidad = _MockQuery();
      final porGym = _MockQuery();
      when(() => posts.where('privacy', isEqualTo: 'gym'))
          .thenReturn(porPrivacidad);
      when(() => porPrivacidad.where('authorGymId', isEqualTo: 'g1'))
          .thenReturn(porGym);
      cablearOrdenLimitGet(porGym);
    });

    test('vacío DESDE CACHÉ → tira unavailable', () async {
      respuestas = [_snap(docs: const [], isFromCache: true)];

      await expectLater(repo.feedForGym('g1'), throwsUnavailable());
    });
  });

  group('feedForFriends', () {
    setUp(() {
      final porPrivacidad = _MockQuery();
      final porAutores = _MockQuery();
      // `followers` viaja a Firestore como 'friends' (LD-05, post_privacy.dart).
      when(() => posts.where('privacy', isEqualTo: 'friends'))
          .thenReturn(porPrivacidad);
      // Cada chunk lleva otro `whereIn`; lo que cambia es la RESPUESTA del get.
      when(
        () => porPrivacidad.where(
          'authorUid',
          whereIn: any(named: 'whereIn'),
        ),
      ).thenReturn(porAutores);
      cablearOrdenLimitGet(porAutores);
    });

    test('un chunk vacío DESDE CACHÉ → tira unavailable', () async {
      respuestas = [_snap(docs: const [], isFromCache: true)];

      await expectLater(repo.feedForFriends(['u1']), throwsUnavailable());
    });

    test(
        '11 amigos = 2 chunks, los dos vacíos de caché → tira '
        'unavailable', () async {
      respuestas = [
        _snap(docs: const [], isFromCache: true),
        _snap(docs: const [], isFromCache: true),
      ];

      await expectLater(
        repo.feedForFriends([for (var i = 0; i < 11; i++) 'u$i']),
        throwsUnavailable(),
      );
    });

    test(
        '11 amigos: un chunk con posts de caché y otro vacío de caché → se '
        'muestran los que hay (no se tira todo el feed)', () async {
      respuestas = [
        _snap(
          docs: await _realDocs([_post('f', privacy: PostPrivacy.followers)]),
          isFromCache: true,
        ),
        _snap(docs: const [], isFromCache: true),
      ];

      final page = await repo.feedForFriends([
        for (var i = 0; i < 11; i++) 'u$i',
      ]);

      expect(page.posts.map((p) => p.id), ['f']);
    });

    test(
        '11 amigos, los dos chunks vacíos y CONFIRMADOS → vacío legítimo, '
        'no error', () async {
      respuestas = [
        _snap(docs: const [], isFromCache: false),
        _snap(docs: const [], isFromCache: false),
      ];

      final page = await repo.feedForFriends([
        for (var i = 0; i < 11; i++) 'u$i',
      ]);

      expect(page.posts, isEmpty);
    });
  });

  // De punta a punta: repo REAL → providers → pantalla. Caché vacía →
  // unavailable → AsyncError → error con Reintentar, que con red repone el feed.
  group('FeedScreen sin red (repo real)', () {
    late _MockQuery porPrivacidad;

    setUp(() {
      porPrivacidad = _MockQuery();
      when(() => posts.where('privacy', isEqualTo: 'public'))
          .thenReturn(porPrivacidad);
      cablearOrdenLimitGet(porPrivacidad);
    });

    Widget wrap() => ProviderScope(
          overrides: [
            feedSegmentProvider.overrideWith((ref) => FeedSegment.public),
            authStateChangesProvider.overrideWith(
              (ref) => Stream.value(_MockUser(uid: 'u1')),
            ),
            followingProvider('u1')
                .overrideWith((ref) => Stream.value(const <String>[])),
            blockedUidsProvider('u1')
                .overrideWith((ref) => Stream.value(const <String>[])),
            unreadFromFriendsProvider.overrideWith((ref) => 0),
            postRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            locale: const Locale('es', 'AR'),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            home: const Scaffold(body: FeedScreen()),
          ),
        );

    testWidgets(
        'caché vacía → error con Reintentar (NO "Aún no hay posts públicos") '
        'y Reintentar con red repone el feed', (tester) async {
      respuestas = [
        // 1ª carga: sin red, caché fría.
        _snap(docs: const [], isFromCache: true),
        // Tras Reintentar: vuelve la red y el servidor contesta con un post.
        _snap(docs: await _realDocs([_post('a')]), isFromCache: false),
      ];

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.text('No pudimos cargar tu feed. Probá de nuevo.'),
          findsOneWidget);
      expect(find.text('Aún no hay posts públicos'), findsNothing);
      final retry = find.widgetWithText(TextButton, 'Reintentar');
      expect(retry, findsOneWidget);

      await tester.tap(retry);
      await tester.pumpAndSettle();

      expect(find.text('No pudimos cargar tu feed. Probá de nuevo.'),
          findsNothing);
      expect(find.text('post a'), findsOneWidget);
    });

    testWidgets(
        'vacío CONFIRMADO por el servidor → sigue siendo "Aún no hay posts '
        'públicos", sin error', (tester) async {
      respuestas = [_snap(docs: const [], isFromCache: false)];

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.text('Aún no hay posts públicos'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Reintentar'), findsNothing);
    });
  });
}
