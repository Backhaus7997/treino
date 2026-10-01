// `CollectionReference` y `DocumentReference` están `@sealed` en
// `cloud_firestore`, así que mockearlas dispara `subtype_of_sealed_class`. Mismo
// trato —y mismo motivo— que `session_repository_adoption_timeout_test.dart`:
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

/// El interruptor «Correos promocionales» de Perfil › Privacidad: lo que se
/// escribe en `users/{uid}` y cómo se lee de vuelta.
///
/// El backend (`emailChannelAllowed`) frena el envío sólo si
/// `notificationPrefs.novedades_plan.email === false`. Cualquier otra forma del
/// documento —clave con puntos, mapa en otro lugar— es un interruptor que
/// escribe un campo que nadie lee.
void main() {
  const uid = 'uid-correos';

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

  group('setCorreosPromocionales — qué se escribe', () {
    test('escribe el MAPA ANIDADO, no una clave con puntos', () async {
      await firestore.collection('users').doc(uid).set({'uid': uid});

      await repo.setCorreosPromocionales(uid, false);

      final data = await leerDoc();
      // `equals` sobre el documento ENTERO y no sólo sobre la ruta anidada:
      // un campo de más (o un mapa en otro lugar) tiene que verse. OJO: esto
      // NO detecta una clave con puntos —el fake la interpreta como ruta—;
      // eso lo cubre el grupo de «lo que RECIBE Firestore», más abajo.
      expect(
        data,
        equals({
          'uid': uid,
          'notificationPrefs': {
            kPrefCorreosPromocionales: {'email': false},
          },
        }),
      );
      expect(
        data!.keys.where((k) => k.contains('.')),
        isEmpty,
        reason: 'una clave con puntos en un `set` queda como nombre literal',
      );
    });

    test('la clave que escribe es la que lee el backend: novedades_plan',
        () async {
      // El literal, no la constante: si alguien cambia la constante a otra
      // cosa, el test de deriva contra el `.ts` lo agarra, y éste fija que el
      // campo que existe en producción se sigue llamando así.
      await repo.setCorreosPromocionales(uid, false);

      final prefs = (await leerDoc())!['notificationPrefs'] as Map;
      expect(prefs.keys, ['novedades_plan']);
      expect((prefs['novedades_plan'] as Map)['email'], isFalse);
    });

    test('prender escribe true explícito, no borra el campo', () async {
      await repo.setCorreosPromocionales(uid, false);
      await repo.setCorreosPromocionales(uid, true);

      final prefs = (await leerDoc())!['notificationPrefs'] as Map;
      expect(
        (prefs['novedades_plan'] as Map)['email'],
        isTrue,
        reason: 'el servidor sólo frena con `false`; un `true` explícito es '
            'una elección registrada, un campo borrado es «nunca eligió»',
      );
    });

    test('va con merge: no pisa la matriz del Coach Hub ni otros campos',
        () async {
      // La matriz que el Coach Hub guarda completa (`NotifPrefs.toFirestore`),
      // más el canal `push` de esta misma fila, más un campo ajeno.
      await firestore.collection('users').doc(uid).set({
        'uid': uid,
        'displayName': 'Coach',
        'notificationPrefs': {
          'mensaje_nuevo': {'push': true, 'email': false},
          'nueva_solicitud': {'push': false, 'email': true},
          kPrefCorreosPromocionales: {'push': false},
        },
      });

      await repo.setCorreosPromocionales(uid, false);

      expect(
        await leerDoc(),
        equals({
          'uid': uid,
          'displayName': 'Coach',
          'notificationPrefs': {
            'mensaje_nuevo': {'push': true, 'email': false},
            'nueva_solicitud': {'push': false, 'email': true},
            // El merge es profundo: `push` sobrevive y `email` se suma.
            kPrefCorreosPromocionales: {'push': false, 'email': false},
          },
        }),
      );
    });

    test('el error de Firestore SE PROPAGA: el que llama tiene que enterarse',
        () async {
      // A diferencia de `registrarTopeTocado`, que traga todo a propósito. Acá
      // un fallo silencioso deja al usuario con el interruptor apagado sobre
      // un correo que va a seguir llegando.
      whenCalling(Invocation.method(#set, null))
          .on(firestore.collection('users').doc(uid))
          .thenThrow(FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
          ));

      await expectLater(
        repo.setCorreosPromocionales(uid, false),
        throwsA(isA<FirebaseException>()),
      );
    });
  });

  // POR QUÉ HACE FALTA UN ESPÍA, y no alcanza con leer el documento de vuelta:
  // `fake_cloud_firestore` interpreta una clave con puntos como una RUTA aun en
  // un `set` con merge, así que una escritura con
  // `'notificationPrefs.novedades_plan.email'` termina en el mismo documento
  // anidado que la correcta y los tests de arriba salen verdes. Firestore de
  // verdad no hace eso: en un `set` esa clave es un campo cuyo NOMBRE contiene
  // los puntos (verificado contra el emulador con el SDK de JS: el documento
  // queda con un campo literal `notificationPrefs.novedades_plan.email`; sólo
  // `update()` interpreta la ruta). Se comprobó por mutación que con la clave
  // con puntos los tests que leen el documento siguen en verde.
  // Para ver qué se manda, hay que mirar el argumento que recibe `set`.
  group('setCorreosPromocionales — lo que RECIBE Firestore', () {
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
      await repoEspia().setCorreosPromocionales(uid, false);

      final captured =
          verify(() => doc.set(captureAny(), captureAny())).captured;
      final data = captured[0] as Map<String, Object?>;

      expect(
        data,
        equals({
          'notificationPrefs': {
            'novedades_plan': {'email': false},
          },
        }),
      );
      // Mirar sólo las claves del nivel de arriba no alcanza: una con puntos
      // es exactamente lo que se cuela ahí.
      expect(data.keys.where((k) => k.contains('.')), isEmpty);
    });

    test('va con merge:true, que es lo que hace profundo el merge', () async {
      await repoEspia().setCorreosPromocionales(uid, true);

      final captured =
          verify(() => doc.set(captureAny(), captureAny())).captured;
      final data = captured[0] as Map<String, Object?>;
      final options = captured[1] as SetOptions;

      expect(options.merge, isTrue,
          reason: 'sin merge, el set REEMPLAZA el documento entero');
      expect(
        (data['notificationPrefs']! as Map)['novedades_plan'],
        {'email': true},
      );
    });

    test('es UNA sola escritura al documento del usuario', () async {
      await repoEspia().setCorreosPromocionales(uid, false);

      verify(() => doc.set(any(), any())).called(1);
      verifyNoMoreInteractions(doc);
    });
  });

  group('watchCorreosPromocionales — qué se lee', () {
    Future<void> sembrar(Map<String, Object?> extra) => firestore
        .collection('users')
        .doc(uid)
        .set(<String, Object?>{'uid': uid, ...extra});

    test('campo ausente → true, igual que el servidor', () async {
      await sembrar({});
      expect(await repo.watchCorreosPromocionales(uid).first, isTrue);
    });

    test('notificationPrefs sin la fila novedades_plan → true', () async {
      await sembrar({
        'notificationPrefs': {
          'mensaje_nuevo': {'push': false, 'email': false},
        },
      });
      expect(await repo.watchCorreosPromocionales(uid).first, isTrue);
    });

    test('fila sin canal email (sólo push) → true', () async {
      await sembrar({
        'notificationPrefs': {
          kPrefCorreosPromocionales: {'push': false},
        },
      });
      expect(await repo.watchCorreosPromocionales(uid).first, isTrue);
    });

    test('email: false → false', () async {
      await sembrar({
        'notificationPrefs': {
          kPrefCorreosPromocionales: {'email': false},
        },
      });
      expect(await repo.watchCorreosPromocionales(uid).first, isFalse);
    });

    test('email: true → true', () async {
      await sembrar({
        'notificationPrefs': {
          kPrefCorreosPromocionales: {'email': true},
        },
      });
      expect(await repo.watchCorreosPromocionales(uid).first, isTrue);
    });

    test('un valor de tipo inesperado NO cuenta como «no»', () async {
      // Sólo `false` EXPLÍCITO frena en el servidor (`value !== false`): un
      // string «false» o un null no son `false`, y la app tiene que leer lo
      // mismo que el servidor para no mostrar «apagado» sobre un correo que
      // sale.
      await sembrar({
        'notificationPrefs': {
          kPrefCorreosPromocionales: {'email': 'false'},
        },
      });
      expect(await repo.watchCorreosPromocionales(uid).first, isTrue);
    });

    test('lee de vuelta lo que escribe setCorreosPromocionales', () async {
      await sembrar({});
      final valores = <bool>[];
      final sub = repo.watchCorreosPromocionales(uid).listen(valores.add);

      await Future<void>.delayed(Duration.zero);
      await repo.setCorreosPromocionales(uid, false);
      await Future<void>.delayed(Duration.zero);
      await repo.setCorreosPromocionales(uid, true);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(valores, [true, false, true]);
    });

    test('un cambio de OTRO campo del perfil no re-emite (distinct)', () async {
      await sembrar({});
      final valores = <bool>[];
      final sub = repo.watchCorreosPromocionales(uid).listen(valores.add);

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
