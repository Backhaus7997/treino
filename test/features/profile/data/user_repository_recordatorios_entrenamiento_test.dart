// `CollectionReference` y `DocumentReference` están `@sealed` en
// `cloud_firestore`, así que mockearlas dispara `subtype_of_sealed_class`. Mismo
// trato —y mismo motivo— que `user_repository_correos_promocionales_test.dart`:
// para ver QUÉ recibe `set()` hay que espiar la referencia, y
// `fake_cloud_firestore` no lo muestra (ver el grupo «lo que RECIBE Firestore»).
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart'
    show
        CollectionReference,
        DocumentReference,
        FirebaseException,
        FirebaseFirestore,
        SetOptions;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mock_exceptions/mock_exceptions.dart';
import 'package:treino/features/gyms/data/gym_repository.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/notification_pref_keys.dart';

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _MockUsers extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class _MockUserDoc extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

/// El interruptor «Recordatorios de entrenamiento» de Perfil › Privacidad: lo
/// que se escribe en `users/{uid}` y cómo se lee de vuelta.
///
/// El backend (`notify-daily-reminders.ts`) frena el push sólo si
/// `notificationPrefs.recordatorios_entrenamiento.push === false`. Cualquier
/// otra forma del documento —clave con puntos, mapa en otro lugar, el canal
/// equivocado— es un interruptor que escribe un campo que nadie lee.
///
/// Es el gemelo de `user_repository_correos_promocionales_test.dart`: comparten
/// el mismo código de lectura y escritura, con otra fila y otro canal. Por eso
/// además de fijar el contrato acá se prueba que las dos preferencias NO se
/// pisan entre sí.
void main() {
  const uid = 'uid-recordatorios';

  late FakeFirebaseFirestore firestore;
  late UserRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = UserRepository(
      firestore: firestore,
      gyms: GymRepository(firestore: firestore),
    );
  });

  Future<Map<String, dynamic>?> leerDoc() async =>
      (await firestore.collection('users').doc(uid).get()).data();

  group('setRecordatoriosEntrenamiento — qué se escribe', () {
    test('escribe el MAPA ANIDADO en el canal push, sin claves con puntos',
        () async {
      await firestore.collection('users').doc(uid).set({'uid': uid});

      await repo.setRecordatoriosEntrenamiento(uid, false);

      final data = await leerDoc();
      expect(
        data,
        equals({
          'uid': uid,
          'notificationPrefs': {
            kPrefRecordatoriosEntrenamiento: {'push': false},
          },
        }),
      );
      expect(
        data!.keys.where((k) => k.contains('.')),
        isEmpty,
        reason: 'una clave con puntos en un `set` queda como nombre literal',
      );
    });

    test(
        'la clave que escribe es la que lee el backend: '
        'recordatorios_entrenamiento.push', () async {
      // El literal, no la constante: si alguien cambia la constante a otra
      // cosa, el test de deriva contra el `.ts` lo agarra, y éste fija que el
      // campo que existe en producción se sigue llamando así.
      await repo.setRecordatoriosEntrenamiento(uid, false);

      final prefs = (await leerDoc())!['notificationPrefs'] as Map;
      expect(prefs.keys, ['recordatorios_entrenamiento']);
      final fila = prefs['recordatorios_entrenamiento'] as Map;
      expect(fila.keys, ['push'], reason: 'es un push, no un correo');
      expect(fila['push'], isFalse);
      expect(kPrefRecordatoriosEntrenamiento, 'recordatorios_entrenamiento');
    });

    test('prender escribe true explícito, no borra el campo', () async {
      await repo.setRecordatoriosEntrenamiento(uid, false);
      await repo.setRecordatoriosEntrenamiento(uid, true);

      final prefs = (await leerDoc())!['notificationPrefs'] as Map;
      expect(
        (prefs['recordatorios_entrenamiento'] as Map)['push'],
        isTrue,
        reason: 'el servidor sólo frena con `false`; un `true` explícito es '
            'una elección registrada, un campo borrado es «nunca eligió»',
      );
    });

    test('va con merge: no pisa las demás filas ni el canal email de la fila',
        () async {
      await firestore.collection('users').doc(uid).set({
        'uid': uid,
        'displayName': 'Ana',
        'notificationPrefs': {
          'mensaje_nuevo': {'push': true, 'email': false},
          kPrefCorreosPromocionales: {'email': false},
          kPrefRecordatoriosEntrenamiento: {'email': true},
        },
      });

      await repo.setRecordatoriosEntrenamiento(uid, false);

      expect(
        await leerDoc(),
        equals({
          'uid': uid,
          'displayName': 'Ana',
          'notificationPrefs': {
            'mensaje_nuevo': {'push': true, 'email': false},
            // La otra preferencia del atleta queda como estaba.
            kPrefCorreosPromocionales: {'email': false},
            // El merge es profundo: `email` sobrevive y `push` se suma.
            kPrefRecordatoriosEntrenamiento: {'email': true, 'push': false},
          },
        }),
      );
    });

    test('apagar los correos NO toca los recordatorios (y al revés)', () async {
      await repo.setRecordatoriosEntrenamiento(uid, false);
      await repo.setCorreosPromocionales(uid, false);
      await repo.setRecordatoriosEntrenamiento(uid, true);

      expect(
        (await leerDoc())!['notificationPrefs'],
        equals({
          kPrefRecordatoriosEntrenamiento: {'push': true},
          kPrefCorreosPromocionales: {'email': false},
        }),
      );
    });

    test('el error de Firestore SE PROPAGA: el que llama tiene que enterarse',
        () async {
      // Un fallo silencioso deja al atleta con el interruptor apagado sobre un
      // push que va a seguir llegando.
      whenCalling(Invocation.method(#set, null))
          .on(firestore.collection('users').doc(uid))
          .thenThrow(FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
          ));

      await expectLater(
        repo.setRecordatoriosEntrenamiento(uid, false),
        throwsA(isA<FirebaseException>()),
      );
    });
  });

  // POR QUÉ HACE FALTA UN ESPÍA: `fake_cloud_firestore` interpreta una clave con
  // puntos como una RUTA aun en un `set` con merge, así que una escritura con
  // `'notificationPrefs.recordatorios_entrenamiento.push'` termina en el mismo
  // documento anidado que la correcta y los tests de arriba salen verdes.
  // Firestore de verdad no hace eso: en un `set` esa clave es un campo cuyo
  // NOMBRE contiene los puntos (sólo `update()` interpreta la ruta). Para ver
  // qué se manda, hay que mirar el argumento que recibe `set`.
  group('setRecordatoriosEntrenamiento — lo que RECIBE Firestore', () {
    late _MockFirestore firestoreEspia;
    late _MockUserDoc doc;

    setUp(() {
      registerFallbackValue(SetOptions(merge: true));
      registerFallbackValue(<String, Object?>{});
      firestoreEspia = _MockFirestore();
      final users = _MockUsers();
      doc = _MockUserDoc();
      when(() => firestoreEspia.collection('users')).thenReturn(users);
      when(() => users.doc(uid)).thenReturn(doc);
      when(() => doc.set(any(), any())).thenAnswer((_) async {});
    });

    UserRepository repoEspia() => UserRepository(
          firestore: firestoreEspia,
          // El GymRepository por defecto también tocaría el firestore espía.
          gyms: GymRepository(firestore: FakeFirebaseFirestore()),
        );

    test('el dato es el mapa anidado, sin ninguna clave con puntos', () async {
      await repoEspia().setRecordatoriosEntrenamiento(uid, false);

      final captured =
          verify(() => doc.set(captureAny(), captureAny())).captured;
      final data = captured[0] as Map<String, Object?>;

      expect(
        data,
        equals({
          'notificationPrefs': {
            'recordatorios_entrenamiento': {'push': false},
          },
        }),
      );
      expect(data.keys.where((k) => k.contains('.')), isEmpty);
    });

    test('va con merge:true, que es lo que hace profundo el merge', () async {
      await repoEspia().setRecordatoriosEntrenamiento(uid, true);

      final captured =
          verify(() => doc.set(captureAny(), captureAny())).captured;
      final data = captured[0] as Map<String, Object?>;
      final options = captured[1] as SetOptions;

      expect(options.merge, isTrue,
          reason: 'sin merge, el set REEMPLAZA el documento entero');
      expect(
        (data['notificationPrefs']! as Map)['recordatorios_entrenamiento'],
        {'push': true},
      );
    });

    test('es UNA sola escritura al documento del usuario', () async {
      await repoEspia().setRecordatoriosEntrenamiento(uid, false);

      verify(() => doc.set(any(), any())).called(1);
      verifyNoMoreInteractions(doc);
    });
  });

  group('watchRecordatoriosEntrenamiento — qué se lee', () {
    Future<void> sembrar(Map<String, Object?> extra) => firestore
        .collection('users')
        .doc(uid)
        .set(<String, Object?>{'uid': uid, ...extra});

    test('campo ausente → true, igual que el servidor', () async {
      await sembrar({});
      expect(await repo.watchRecordatoriosEntrenamiento(uid).first, isTrue);
    });

    test('notificationPrefs sin la fila de recordatorios → true', () async {
      await sembrar({
        'notificationPrefs': {
          'mensaje_nuevo': {'push': false, 'email': false},
        },
      });
      expect(await repo.watchRecordatoriosEntrenamiento(uid).first, isTrue);
    });

    test('fila sin canal push (sólo email) → true', () async {
      await sembrar({
        'notificationPrefs': {
          kPrefRecordatoriosEntrenamiento: {'email': false},
        },
      });
      expect(await repo.watchRecordatoriosEntrenamiento(uid).first, isTrue);
    });

    test('push: false → false', () async {
      await sembrar({
        'notificationPrefs': {
          kPrefRecordatoriosEntrenamiento: {'push': false},
        },
      });
      expect(await repo.watchRecordatoriosEntrenamiento(uid).first, isFalse);
    });

    test('push: true → true', () async {
      await sembrar({
        'notificationPrefs': {
          kPrefRecordatoriosEntrenamiento: {'push': true},
        },
      });
      expect(await repo.watchRecordatoriosEntrenamiento(uid).first, isTrue);
    });

    test('apagar los correos promocionales NO apaga los recordatorios',
        () async {
      await sembrar({
        'notificationPrefs': {
          kPrefCorreosPromocionales: {'email': false, 'push': false},
        },
      });
      expect(await repo.watchRecordatoriosEntrenamiento(uid).first, isTrue);
    });

    test('un valor de tipo inesperado NO cuenta como «no»', () async {
      // Sólo `false` EXPLÍCITO frena en el servidor: un string «false» o un
      // null no son `false`, y la app tiene que leer lo mismo que el servidor
      // para no mostrar «apagado» sobre un push que sale.
      await sembrar({
        'notificationPrefs': {
          kPrefRecordatoriosEntrenamiento: {'push': 'false'},
        },
      });
      expect(await repo.watchRecordatoriosEntrenamiento(uid).first, isTrue);
    });

    test('lee de vuelta lo que escribe setRecordatoriosEntrenamiento',
        () async {
      await sembrar({});
      final valores = <bool>[];
      final sub = repo.watchRecordatoriosEntrenamiento(uid).listen(valores.add);

      await Future<void>.delayed(Duration.zero);
      await repo.setRecordatoriosEntrenamiento(uid, false);
      await Future<void>.delayed(Duration.zero);
      await repo.setRecordatoriosEntrenamiento(uid, true);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(valores, [true, false, true]);
    });

    test('un cambio de OTRO campo del perfil no re-emite (distinct)', () async {
      await sembrar({});
      final valores = <bool>[];
      final sub = repo.watchRecordatoriosEntrenamiento(uid).listen(valores.add);

      await Future<void>.delayed(Duration.zero);
      await firestore
          .collection('users')
          .doc(uid)
          .set({'displayName': 'Otro nombre'}, SetOptions(merge: true));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(valores, [true]);
    });
  });
}
