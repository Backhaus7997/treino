import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/moderation/moderation_guard.dart';
import 'package:treino/l10n/app_l10n_en.dart';
import 'package:treino/l10n/app_l10n_es.dart';
import 'package:treino/features/chat/data/chat_repository.dart';
import 'package:treino/features/feed/data/post_repository.dart';
import 'package:treino/features/feed/domain/post.dart';
import 'package:treino/features/feed/domain/post_privacy.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/reviews/data/review_repository.dart';
import 'package:treino/features/reviews/domain/review.dart';
import 'package:treino/features/workout/data/routine_repository.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';

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

  group('bio del entrenador (trainerBio)', () {
    test('update rechaza la bio vetada y no la escribe en ningun documento',
        () async {
      final repo = UserRepository(firestore: firestore);
      await firestore.collection('users').doc('t1').set({
        'uid': 't1',
        'trainerBio': 'Bio original limpia.',
      });
      await firestore.collection('trainerPublicProfiles').doc('t1').set({
        'uid': 't1',
        'trainerBio': 'Bio original limpia.',
      });

      await expectLater(
        repo.update('t1', {'trainerBio': _vetado}),
        throwsA(isA<ModerationBlockedException>()),
      );

      final privado = await firestore.collection('users').doc('t1').get();
      final publico =
          await firestore.collection('trainerPublicProfiles').doc('t1').get();
      expect(privado.data()!['trainerBio'], 'Bio original limpia.',
          reason: 'el update piso la bio en users igual');
      expect(publico.data()!['trainerBio'], 'Bio original limpia.',
          reason: 'el update piso la bio en trainerPublicProfiles igual');
    });

    test('update deja pasar una bio limpia y la dual-escribe', () async {
      final repo = UserRepository(firestore: firestore);
      await firestore.collection('users').doc('t1').set({'uid': 't1'});

      await repo.update('t1', {'trainerBio': 'Entreno hace 10 anios.'});

      final publico =
          await firestore.collection('trainerPublicProfiles').doc('t1').get();
      expect(publico.data()!['trainerBio'], 'Entreno hace 10 anios.');
    });
  });

  group('rutinas', () {
    // Los CINCO campos de texto libre de una rutina: `name`, `split`,
    // `summary` a nivel documento, y `days[].name` / `days[].slots[].notes`
    // anidados. Cada test de abajo ejercita un metodo de escritura distinto
    // con un campo distinto, asi que entre todos quedan los seis metodos Y
    // los cinco campos cubiertos sin repetir la matriz completa — la
    // exhaustividad campo x metodo ya la tiene
    // `quarantine-routine-fields.test.ts` del lado del servidor.
    RoutineSlot slot({String? notes}) => RoutineSlot(
          exerciseId: 'e1',
          exerciseName: 'Press banca',
          muscleGroup: 'chest',
          targetSets: 3,
          targetRepsMin: 8,
          targetRepsMax: 12,
          restSeconds: 90,
          notes: notes,
        );

    test('createUserOwned rechaza el nombre vetado y no escribe nada',
        () async {
      final repo = RoutineRepository(firestore: firestore);

      await expectLater(
        repo.createUserOwned(
          uid: 'a1',
          draft: const Routine(
            id: '',
            name: _vetado,
            split: null,
            level: ExperienceLevel.beginner,
            days: [],
          ),
        ),
        throwsA(isA<ModerationBlockedException>()),
      );

      expect((await firestore.collection('routines').get()).docs, isEmpty);
    });

    test(
        'updateUserOwned rechaza: editar una rutina limpia para meter el '
        'nombre vetado', () async {
      // La misma evasion barata que en posts: publicar algo inocente y
      // editarlo. Sin guard en el UPDATE, el guard del CREATE no alcanza.
      final repo = RoutineRepository(firestore: firestore);
      final saved = await repo.createUserOwned(
        uid: 'a1',
        draft: const Routine(
          id: '',
          name: 'Mi rutina',
          split: null,
          level: ExperienceLevel.beginner,
          days: [],
        ),
      );

      await expectLater(
        repo.updateUserOwned(
          uid: 'a1',
          draft: saved.copyWith(name: _vetado),
        ),
        throwsA(isA<ModerationBlockedException>()),
      );

      final doc = await firestore.collection('routines').doc(saved.id).get();
      expect(doc.data()!['name'], 'Mi rutina',
          reason: 'el update piso el nombre igual');
    });

    test('createAssigned rechaza el split vetado y no escribe nada', () async {
      final repo = RoutineRepository(firestore: firestore);

      await expectLater(
        repo.createAssigned(const Routine(
          id: '',
          name: 'Plan asignado',
          split: _vetado,
          level: ExperienceLevel.beginner,
          days: [],
          assignedBy: 't1',
          assignedTo: 'a1',
        )),
        throwsA(isA<ModerationBlockedException>()),
      );

      expect((await firestore.collection('routines').get()).docs, isEmpty);
    });

    test('updateAssigned rechaza el resumen vetado y no pisa el doc', () async {
      final repo = RoutineRepository(firestore: firestore);
      final saved = await repo.createAssigned(const Routine(
        id: '',
        name: 'Plan asignado',
        split: 'PPL',
        summary: 'Resumen original.',
        level: ExperienceLevel.beginner,
        days: [],
        assignedBy: 't1',
        assignedTo: 'a1',
      ));

      await expectLater(
        repo.updateAssigned(uid: 't1', draft: saved.copyWith(summary: _vetado)),
        throwsA(isA<ModerationBlockedException>()),
      );

      final doc = await firestore.collection('routines').doc(saved.id).get();
      expect(doc.data()!['summary'], 'Resumen original.',
          reason: 'el update piso el resumen igual');
    });

    test('createTemplate rechaza el nombre de un dia vetado y no escribe nada',
        () async {
      final repo = RoutineRepository(firestore: firestore);

      await expectLater(
        repo.createTemplate(Routine(
          id: '',
          name: 'Plantilla',
          split: 'PPL',
          level: ExperienceLevel.beginner,
          days: [
            RoutineDay(dayNumber: 1, name: 'Dia 1', slots: [slot()]),
            const RoutineDay(dayNumber: 2, name: _vetado, slots: []),
          ],
          assignedBy: 't1',
        )),
        throwsA(isA<ModerationBlockedException>()),
      );

      expect((await firestore.collection('routines').get()).docs, isEmpty);
    });

    test(
        'updateTemplate rechaza notas vetadas en days[1].slots[1] (NO el '
        'primer slot) y no pisa el doc', () async {
      // Un bug de indice pasa desapercibido si el unico caso probado es la
      // posicion 0 — mismo motivo que el test gemelo del lado del servidor.
      final repo = RoutineRepository(firestore: firestore);
      final saved = await repo.createTemplate(Routine(
        id: '',
        name: 'Plantilla',
        split: 'PPL',
        level: ExperienceLevel.beginner,
        days: [
          RoutineDay(
              dayNumber: 1, name: 'Dia 1', slots: [slot(notes: 'buena forma')]),
          RoutineDay(
            dayNumber: 2,
            name: 'Dia 2',
            slots: [
              slot(notes: 'buena forma'),
              slot(notes: 'controlar el descenso'),
            ],
          ),
        ],
        assignedBy: 't1',
      ));

      final draft = saved.copyWith(days: [
        saved.days[0],
        saved.days[1].copyWith(slots: [
          saved.days[1].slots[0],
          saved.days[1].slots[1].copyWith(notes: _vetado),
        ]),
      ]);

      await expectLater(
        repo.updateTemplate(uid: 't1', draft: draft),
        throwsA(isA<ModerationBlockedException>()),
      );

      final doc = await firestore.collection('routines').doc(saved.id).get();
      final days = doc.data()!['days'] as List<dynamic>;
      final day1Slots =
          (days[1] as Map<String, dynamic>)['slots'] as List<dynamic>;
      expect((day1Slots[1] as Map<String, dynamic>)['notes'],
          'controlar el descenso',
          reason: 'el update piso las notas igual');
    });

    test(
        'vocabulario que roza el filtro (allowlist, "culo"/"puta" como '
        'subcadena de palabras legitimas) no se rechaza en ningun campo',
        () async {
      // A diferencia del corpus viejo (musculo/dorsal/aductores: ninguna es
      // subcadena de un termino de VETTED_ANTI_EVASION, asi que este test
      // pasaba igual con el filtro vacio) este corpus usa palabras que SI
      // entran a la pasada antievasion y sobreviven solo por la allowlist —
      // "controlo" contiene "trolo", "computo" contiene "puto" — o que
      // dependen de que la pasada A compare por palabra completa y no por
      // subcadena — "calculo" contiene "culo". Si se rompe cualquiera de
      // las dos cosas, este test se pone rojo.
      final repo = RoutineRepository(firestore: firestore);

      final saved = await repo.createUserOwned(
        uid: 'a1',
        draft: Routine(
          id: '',
          name: 'Full body - controlo la tecnica',
          split: 'El computo de series por grupo muscular',
          summary: 'Trabajo el musculo dorsal sin descontrolo en la carga.',
          level: ExperienceLevel.beginner,
          days: [
            RoutineDay(
              dayNumber: 1,
              name: 'Dia de aductores y calculo de RM',
              slots: [
                slot(notes: 'No te disputo el peso, priorizo la forma'),
              ],
            ),
          ],
        ),
      );

      expect(saved.name, 'Full body - controlo la tecnica');
      expect((await firestore.collection('routines').get()).docs, hasLength(1));
    });

    test(
        'el cue que motivo todo: "matate" en una nota de entrenador ya no '
        'bloquea la rutina', () async {
      // finding 3: "matate" es jerga de gimnasio corriente ("matate en la
      // ultima serie") y bajo de `block` a `review` — deja de impedir el
      // guardado. `ModerationGuard.ensure` del cliente solo tira para
      // `block`, asi que este test fija que una nota real de entrenador con
      // "matate" ya puede guardarse.
      final repo = RoutineRepository(firestore: firestore);

      final saved = await repo.createUserOwned(
        uid: 'a1',
        draft: Routine(
          id: '',
          name: 'Rutina de piernas',
          split: null,
          level: ExperienceLevel.beginner,
          days: [
            RoutineDay(
              dayNumber: 1,
              name: 'Dia 1',
              slots: [
                slot(
                  notes: 'Dale, matate en la ultima serie que ya casi '
                      'terminamos',
                ),
              ],
            ),
          ],
        ),
      );

      expect(
        saved.days[0].slots[0].notes,
        'Dale, matate en la ultima serie que ya casi terminamos',
      );
    });
  });

  group('el mensaje al usuario', () {
    test('la excepcion no carga copy: eso vive en l10n', () {
      // Una capa de datos que devuelve castellano rioplatense obliga a
      // traducirlo desde donde no hay contexto. La app tiene tres locales.
      const e = ModerationBlockedException('text');
      expect(e.toString(), contains('text'));
    });

    test('el copy de l10n no nombra el termino que lo disparo', () {
      // Decirlo convierte al filtro en un oraculo: se prueban variantes hasta
      // que el mensaje deja de aparecer, y el mensaje confirma el exito.
      for (final l in [AppL10nEsAr(), AppL10nEs(), AppL10nEn()]) {
        final copy = l.moderationBlockedMessage.toLowerCase();
        expect(copy, isNot(contains('puta')), reason: l.localeName);
        expect(copy, isNot(contains('hijo')), reason: l.localeName);
        expect(copy, isNotEmpty, reason: l.localeName);
      }
    });
  });
}
