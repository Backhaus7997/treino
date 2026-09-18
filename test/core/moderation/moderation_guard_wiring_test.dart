import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/moderation/moderation_guard.dart';
import 'package:treino/features/chat/data/chat_repository.dart';
import 'package:treino/features/feed/data/post_repository.dart';
import 'package:treino/features/feed/domain/post.dart';
import 'package:treino/features/feed/domain/post_privacy.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/reviews/data/review_repository.dart';
import 'package:treino/features/reviews/domain/review.dart';

/// El filtro esta CABLEADO a las superficies, no solo escrito.
///
/// La suite de `moderation_filter_test.dart` prueba que el filtro decide bien.
/// Esta prueba otra cosa, que es la que de verdad puede fallar en silencio:
/// que cada superficie lo LLAME. Un filtro perfecto que nadie invoca da la
/// misma suite verde que uno cableado, y la unica diferencia se ve en
/// produccion.
///
/// Cada caso ademas verifica que NO SE ESCRIBIO NADA. Sin eso, un guard puesto
/// despues del `set()` pasaria igual: lanzaria la excepcion con el documento
/// ya en Firestore, que es peor que no tenerlo — el contenido vetado quedaria
/// publicado y el usuario veria un error.
const _vetado = 'sos un hijo de puta';
const _limpio = 'buena rutina, gracias';

Post _post({String text = _limpio}) => Post(
      id: 'p1',
      authorUid: 'u1',
      authorDisplayName: 'Test',
      authorAvatarUrl: null,
      authorGymId: null,
      text: text,
      routineTag: null,
      privacy: PostPrivacy.public,
      createdAt: DateTime.utc(2026, 1, 1),
    );

Review _review({String? comment}) => Review(
      id: Review.idFor('l1', 'a1'),
      linkId: 'l1',
      athleteId: 'a1',
      trainerId: 't1',
      rating: 5,
      comment: comment,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() => firestore = FakeFirebaseFirestore());

  group('posts', () {
    test('create rechaza y no escribe nada', () async {
      final repo = PostRepository(firestore: firestore);

      await expectLater(
        repo.create(_post(text: _vetado)),
        throwsA(isA<ModerationBlockedException>()),
      );

      final docs = await firestore.collection('posts').get();
      expect(docs.docs, isEmpty,
          reason: 'el guard corrio DESPUES del set(): el post quedo publicado');
    });

    test('create deja pasar el texto limpio', () async {
      final repo = PostRepository(firestore: firestore);
      await firestore.collection('users').doc('u1').set({'gymId': 'g1'});

      final post = await repo.create(_post());

      expect(post.text, _limpio);
      expect((await firestore.collection('posts').get()).docs, hasLength(1));
    });

    test('update rechaza: editar un post limpio para meter lo vetado',
        () async {
      // La evasion mas barata que existe. Sin guard en `update`, alcanza con
      // publicar algo inocente y editarlo.
      final repo = PostRepository(firestore: firestore);
      await firestore.collection('users').doc('u1').set({'gymId': 'g1'});
      final creado = await repo.create(_post());

      await expectLater(
        repo.update(creado.copyWith(text: _vetado)),
        throwsA(isA<ModerationBlockedException>()),
      );

      final doc = await firestore.collection('posts').doc(creado.id).get();
      expect(doc.data()!['text'], _limpio,
          reason: 'el update piso el texto igual');
    });
  });

  group('chat', () {
    test('sendMessage rechaza y no escribe nada', () async {
      final repo = ChatRepository(firestore: firestore);
      await firestore.collection('chats').doc('c1').set({'id': 'c1'});

      await expectLater(
        repo.sendMessage(chatId: 'c1', senderId: 'u1', text: _vetado),
        throwsA(isA<ModerationBlockedException>()),
      );

      final msgs = await firestore.collection('chats/c1/messages').get();
      expect(msgs.docs, isEmpty);
    });

    test('sendMessage deja pasar el texto limpio', () async {
      final repo = ChatRepository(firestore: firestore);
      await firestore.collection('chats').doc('c1').set({'id': 'c1'});

      await repo.sendMessage(chatId: 'c1', senderId: 'u1', text: _limpio);

      final msgs = await firestore.collection('chats/c1/messages').get();
      expect(msgs.docs, hasLength(1));
    });
  });

  group('resenas', () {
    test('upsert rechaza el comentario vetado y no escribe', () async {
      final repo = ReviewRepository(firestore: firestore);

      await expectLater(
        repo.upsert(_review(comment: _vetado)),
        throwsA(isA<ModerationBlockedException>()),
      );

      expect((await firestore.collection('reviews').get()).docs, isEmpty);
    });

    test('upsert acepta una resena sin comentario', () async {
      // El comentario es opcional. `null` no es "escribio algo vetado".
      final repo = ReviewRepository(firestore: firestore);
      await repo.upsert(_review());
      expect((await firestore.collection('reviews').get()).docs, hasLength(1));
    });
  });

  group('displayName', () {
    test('update rechaza el nombre vetado y no lo escribe', () async {
      final repo = UserRepository(firestore: firestore);
      await firestore.collection('users').doc('u1').set({
        'uid': 'u1',
        'displayName': 'Nombre Normal',
      });

      await expectLater(
        repo.update('u1', {'displayName': _vetado}),
        throwsA(isA<ModerationBlockedException>()),
      );

      final doc = await firestore.collection('users').doc('u1').get();
      expect(doc.data()!['displayName'], 'Nombre Normal');
    });

    test('un update que no toca displayName pasa', () async {
      // El guard mira `containsKey`, no el valor: un partial de otros campos
      // no puede quedar frenado por un nombre que ni viaja.
      final repo = UserRepository(firestore: firestore);
      await firestore.collection('users').doc('u1').set({'uid': 'u1'});

      await repo.update('u1', {'bio': 'entreno hace 5 anios'});

      final doc = await firestore.collection('users').doc('u1').get();
      expect(doc.data()!['bio'], 'entreno hace 5 anios');
    });
  });

  group('el mensaje al usuario', () {
    test('no nombra el termino que lo disparo', () {
      // Decirlo convierte al filtro en un oraculo: se prueban variantes hasta
      // que el mensaje deja de aparecer, y el mensaje confirma el exito.
      const e = ModerationBlockedException('text');
      expect(e.mensaje, isNot(contains('puta')));
      expect(e.mensaje, isNot(contains('hijo')));
      expect(e.mensaje, contains('Normas de Comunidad'));
    });
  });
}
