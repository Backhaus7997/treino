import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/auth/application/email_gate_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';

class _MockUser extends Mock implements User {}

User _usuario(String uid) {
  final user = _MockUser();
  when(() => user.uid).thenReturn(uid);
  return user;
}

/// Deja correr los streams del fake (Firestore y auth) antes de mirar el estado.
Future<void> _asentar() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  Future<void> sembrar(Map<String, Object?> data) =>
      firestore.collection('app_config').doc('email_gate').set(data);

  /// Container con sesión de [uid] (o sin sesión si es null) ya resuelta: el
  /// provider depende del uid, y sin esperar a auth la primera lectura es la
  /// de "todavía no sé quién es".
  Future<ProviderContainer> contenedor({String? uid}) async {
    final c = ProviderContainer(
      overrides: [
        firestoreProvider.overrideWithValue(firestore),
        authStateChangesProvider.overrideWith(
          (_) => Stream<User?>.value(uid == null ? null : _usuario(uid)),
        ),
      ],
    );
    addTearDown(c.dispose);
    await c.read(authStateChangesProvider.future);
    return c;
  }

  group('emailGateEnabledProvider', () {
    test('sin documento, el gate está apagado', () async {
      final c = await contenedor(uid: 'u1');

      expect(await c.read(emailGateEnabledProvider.future), isFalse);
    });

    test('con {enabled: true}, está prendido', () async {
      await sembrar({'enabled': true});
      final c = await contenedor(uid: 'u1');

      expect(await c.read(emailGateEnabledProvider.future), isTrue);
    });

    test('con {enabled: false}, está apagado', () async {
      await sembrar({'enabled': false});
      final c = await contenedor(uid: 'u1');

      expect(await c.read(emailGateEnabledProvider.future), isFalse);
    });

    test('solo el booleano true prende: un "true" de texto no cuenta',
        () async {
      // Un typo en la consola no puede prender el gate para todos.
      await sembrar({'enabled': 'true'});
      final c = await contenedor(uid: 'u1');

      expect(await c.read(emailGateEnabledProvider.future), isFalse);
    });

    test('sin sesión, apagado aunque el documento diga true', () async {
      // Con sesión cerrada la regla real lo deniega: el provider ni lo abre.
      await sembrar({'enabled': true});
      final c = await contenedor();

      expect(await c.read(emailGateEnabledProvider.future), isFalse);
    });

    test('el equipo lo da vuelta desde la consola y el provider lo sigue',
        () async {
      await sembrar({'enabled': true});
      final c = await contenedor(uid: 'u1');
      final sub = c.listen(emailGateEnabledProvider, (_, __) {});
      addTearDown(sub.close);
      await _asentar();
      expect(sub.read().valueOrNull, isTrue);

      await sembrar({'enabled': false});
      await _asentar();

      expect(sub.read().valueOrNull, isFalse);
    });

    test('arranca sin sesión y al loguearse abre el documento', () async {
      // El motivo de que dependa del uid: un stream abierto sin sesión termina
      // en error y no se vuelve a suscribir solo.
      await sembrar({'enabled': true});
      final auth = StreamController<User?>.broadcast();
      addTearDown(auth.close);
      final c = ProviderContainer(
        overrides: [
          firestoreProvider.overrideWithValue(firestore),
          authStateChangesProvider.overrideWith((_) => auth.stream),
        ],
      );
      addTearDown(c.dispose);
      final sub = c.listen(emailGateEnabledProvider, (_, __) {});
      addTearDown(sub.close);

      auth.add(null);
      await _asentar();
      expect(sub.read().valueOrNull, isFalse);

      auth.add(_usuario('u1'));
      await _asentar();
      expect(sub.read().valueOrNull, isTrue);
    });
  });

  group('interruptorDesde', () {
    Future<List<bool>> emitidos(List<Map<String, dynamic>?> datos) =>
        interruptorDesde(Stream.fromIterable(datos)).toList();

    test('sin documento (null), apagado', () async {
      expect(await emitidos([null]), [false]);
    });

    test('solo el booleano true prende', () async {
      expect(
        await emitidos([
          {'enabled': true},
          {'enabled': false},
          {'enabled': 'true'},
          {'otro': true},
          <String, dynamic>{},
          null,
        ]),
        [true, false, false, false, false, false],
      );
    });

    test('un true y después un error: el último valor es false', () async {
      // Firestore cierra el listener después de un error, así que un `false`
      // posterior en la consola ya no llegaría: este es el último valor.
      final datos = StreamController<Map<String, dynamic>?>();
      addTearDown(datos.close);
      final valores = <bool>[];
      interruptorDesde(datos.stream).listen(valores.add);

      datos.add({'enabled': true});
      datos.addError(StateError('permission-denied'));
      await _asentar();

      expect(valores, [true, false]);
    });

    test('un error de entrada también da false (no solo después de un true)',
        () async {
      final datos = StreamController<Map<String, dynamic>?>();
      addTearDown(datos.close);
      final valores = <bool>[];
      interruptorDesde(datos.stream).listen(valores.add);

      datos.addError(StateError('permission-denied'));
      await _asentar();

      expect(valores, [false]);
    });

    test('dentro de un StreamProvider, tras true + error el valor es false',
        () async {
      final datos = StreamController<Map<String, dynamic>?>();
      addTearDown(datos.close);
      final provider =
          StreamProvider<bool>((ref) => interruptorDesde(datos.stream));
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final sub = c.listen(provider, (_, __) {});
      addTearDown(sub.close);

      datos.add({'enabled': true});
      await _asentar();
      expect(sub.read().valueOrNull, isTrue);

      datos.addError(StateError('permission-denied'));
      await _asentar();

      expect(sub.read().hasError, isFalse);
      expect(sub.read().valueOrNull, isFalse);
    });

    test('control: SIN la conversión, Riverpod se queda con el true', () async {
      // La premisa de la función: un StreamProvider que pasa a error conserva el
      // último valor, y `valueOrNull ?? false` (lo que lee el router) daría true.
      final datos = StreamController<Map<String, dynamic>?>();
      addTearDown(datos.close);
      final provider = StreamProvider<bool>(
        (ref) => datos.stream.map((d) => d?['enabled'] == true),
      );
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final sub = c.listen(provider, (_, __) {});
      addTearDown(sub.close);

      datos.add({'enabled': true});
      await _asentar();
      datos.addError(StateError('permission-denied'));
      await _asentar();

      expect(sub.read().hasError, isTrue);
      expect(sub.read().valueOrNull, isTrue);
    });
  });
}
