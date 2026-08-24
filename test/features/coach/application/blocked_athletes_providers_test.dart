// El primer y único consumidor Dart de `users/{uid}.blockedAthleteIds`, que
// hasta ahora era un campo inerte que sólo escribía una Cloud Function.
//
// Estos tests existen porque el cuerpo del provider tenía cobertura CERO: los
// dos harness de widget lo overridean entero, así que el mapeo crudo de la
// snapshot —el nombre del campo incluido— no lo ejercitaba nadie. Un typo ahí
// produce las DOS respuestas equivocadas que este slice existe para evitar: la
// pantalla afirma «ninguno, no fue por el cupo de tu plan» para siempre, y el
// evento de analytics sale con `athlete_entitlement: entitled` en el 100% de
// los casos, que es la señal que manda al on-call a buscar una regla rota.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/application/blocked_athletes_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';

const _uid = 'pf1';

ProviderContainer _container(
  FakeFirebaseFirestore firestore, {
  String? uid = _uid,
}) {
  final container = ProviderContainer(
    overrides: [
      firestoreProvider.overrideWithValue(firestore),
      currentUidProvider.overrideWithValue(uid),
    ],
  );
  addTearDown(container.dispose);
  // El provider es autoDispose: sin un listener vivo se tira entre el read y
  // el await y el `.future` nunca resuelve.
  container.listen(blockedAthletesProvider, (_, __) {});
  return container;
}

Future<BlockedAthletes> _read(
  Map<String, Object?>? doc, {
  String? uid = _uid,
}) async {
  final firestore = FakeFirebaseFirestore();
  if (doc != null) {
    await firestore.collection('users').doc(_uid).set(doc);
  }
  return _container(firestore, uid: uid).read(blockedAthletesProvider.future);
}

void main() {
  group('blockedAthletesProvider — lectura del doc del PF', () {
    test('lee blockedAthleteIds del doc propio', () async {
      // Si el nombre del campo se rompe, ESTE test cae. Era el único
      // literal del slice que nada comparaba contra Firestore.
      final blocked = await _read({
        'displayName': 'Profe',
        'blockedAthleteIds': ['a2', 'a1'],
      });

      expect(blocked.isPublished, isTrue);
      expect(blocked.ids, {'a1', 'a2'});
    });

    test('lista vacía publicada es «ninguno», no «no sé»', () async {
      final blocked = await _read({'blockedAthleteIds': <String>[]});

      expect(blocked.ids, isEmpty);
      // La distinción entera de la que depende el copy del estado vacío: acá
      // el backend SÍ miró y dijo que no hay ninguno.
      expect(blocked.isPublished, isTrue);
    });

    test('campo ausente es «no sé», no «ninguno»', () async {
      // El caso permanente de HOY: `blockedAthleteIds` sólo aparece después de
      // que syncTrainerEntitlements corre sobre ese PF. Un PF cuyo padrón y
      // suscripción no se movieron todavía no tiene el campo, y afirmarle
      // «ninguno de tus alumnos quedó afuera» es inventar.
      final blocked = await _read({'displayName': 'Profe'});

      expect(blocked.isPublished, isFalse);
      expect(blocked.ids, isEmpty);
    });

    test('doc inexistente es «no sé»', () async {
      final blocked = await _read(null);

      expect(blocked.isPublished, isFalse);
    });

    test('un campo que no es lista no se toma por lista vacía', () async {
      // Escrito a mano con el Admin SDK, este campo puede llegar con
      // cualquier forma. Tomar la basura por «ninguno» es la afirmación
      // positiva más cara de la pantalla.
      final blocked = await _read({'blockedAthleteIds': 'a1,a2'});

      expect(blocked.isPublished, isFalse);
    });

    test('los elementos que no son String se descartan', () async {
      final blocked = await _read({
        'blockedAthleteIds': ['a1', 42, null, 'a2'],
      });

      expect(blocked.ids, {'a1', 'a2'});
      expect(blocked.isPublished, isTrue);
    });

    test('sin sesión no se afirma nada', () async {
      final blocked = await _read(
        {
          'blockedAthleteIds': ['a1']
        },
        uid: null,
      );

      // Sin uid no se leyó ningún doc, así que el estado es «no sé» y NO el
      // conjunto vacío publicado.
      expect(blocked.isPublished, isFalse);
      expect(blocked.ids, isEmpty);
    });
  });

  group('BlockedAthletes — igualdad por valor', () {
    // De esto depende que el `.distinct()` corte las reemisiones. La CF
    // reescribe `users/{trainerId}` sin condición —`linkLoadReconcile` la
    // dispara en CADA escritura de `trainer_links`, con los mismos valores si
    // nada cambió— y el editor de rutinas observa este provider mientras está
    // abierto. Sin igualdad por valor, cada una de esas reescrituras
    // reconstruye el árbol más pesado del Coach Hub.
    test('dos publicaciones con el mismo contenido son iguales', () {
      // Uno de los dos lados va SIN `const` a propósito, y por eso hacen falta
      // los ignores. Con los dos `const`, Dart canonicaliza los literales en
      // UNA sola instancia y el `expect` lo satisface el `identical` del
      // `operator ==` — pasaría igual con la igualdad por valor borrada, que
      // es justo la que este test existe para pinear. Las instancias tienen
      // que ser distintas de verdad, como lo son las que produce cada snapshot
      // de Firestore.
      expect(
        const BlockedAthletes.published({'a1', 'a2'}),
        // ignore: prefer_const_constructors, prefer_const_literals_to_create_immutables
        BlockedAthletes.published({'a2', 'a1'}),
      );
      expect(
        const BlockedAthletes.published({'a1'}).hashCode,
        // ignore: prefer_const_constructors, prefer_const_literals_to_create_immutables
        BlockedAthletes.published({'a1'}).hashCode,
      );
    });

    test('publicada-vacía y sin-publicar NO son iguales', () {
      // Si colapsaran, el `.distinct()` se comería la transición de «no sé» a
      // «ninguno» y la pantalla se quedaría en el mensaje equivocado.
      expect(
        const BlockedAthletes.published(<String>{}),
        isNot(BlockedAthletes.unpublished),
      );
    });

    test('contenidos distintos no son iguales', () {
      expect(
        const BlockedAthletes.published({'a1'}),
        isNot(const BlockedAthletes.published({'a2'})),
      );
    });
  });

  test('el stream no reemite cuando el doc se reescribe con lo mismo',
      () async {
    final firestore = FakeFirebaseFirestore();
    final doc = firestore.collection('users').doc(_uid);
    await doc.set({
      'blockedAthleteIds': ['a1']
    });

    final container = _container(firestore);
    final seen = <BlockedAthletes>[];
    container.listen(
      blockedAthletesProvider,
      (_, next) {
        final value = next.valueOrNull;
        if (value != null) seen.add(value);
      },
      fireImmediately: true,
    );
    await container.read(blockedAthletesProvider.future);

    // El `tx.set` de la CF no es condicional: corre siempre, con los mismos
    // valores si nada cambió.
    await doc.set({
      'blockedAthleteIds': ['a1']
    });
    await doc.set({
      'blockedAthleteIds': ['a1']
    });
    await Future<void>.delayed(Duration.zero);

    expect(seen, hasLength(1));

    // Pero un cambio REAL sí tiene que llegar.
    await doc.set({
      'blockedAthleteIds': ['a1', 'a2']
    });
    await Future<void>.delayed(Duration.zero);

    expect(seen, hasLength(2));
    expect(seen.last.ids, {'a1', 'a2'});
  });
}
