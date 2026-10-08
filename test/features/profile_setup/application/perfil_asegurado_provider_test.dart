// El reintento de `users/{uid}` durante el alta.
//
// Qué NO mide esto: que un intento tardío no pise el alta ya guardada. Eso lo
// garantizan las reglas (el pin de `createdAt`), y se mide contra el emulador
// en `functions/src/__tests__/alta-no-se-pisa-rules.test.ts`. Un doble de
// UserRepository no puede decir nada sobre eso.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_providers.dart'
    show authStateChangesProvider;
import 'package:treino/features/profile/application/user_providers.dart'
    show userRepositoryProvider;
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile_setup/application/perfil_asegurado_provider.dart';

class _MockUser extends Mock implements User {}

class _MockUserRepository extends Mock implements UserRepository {}

const _sinEsperar = [
  Duration.zero,
  Duration.zero,
  Duration.zero,
  Duration.zero,
];

void main() {
  late _MockUserRepository repo;
  late List<String> reportados;
  late StreamController<User?> auth;

  setUp(() {
    repo = _MockUserRepository();
    reportados = [];
    auth = StreamController<User?>();
    // Por default el doc no existe: es el caso para el que corre el reintento.
    when(() => repo.get(any())).thenAnswer((_) async => null);
  });

  // Sin await: en los tests que no llegan a escuchar `auth`, el `close()` de un
  // StreamController sin listener no completa nunca (colgaba el tearDown).
  tearDown(() {
    auth.close();
  });

  User usuario() {
    final u = _MockUser();
    when(() => u.uid).thenReturn('u1');
    when(() => u.email).thenReturn('a@b.com');
    return u;
  }

  /// Cada llamada a createIfAbsent consume el próximo resultado: `true` anda,
  /// `false` tira. [antes] corre al principio de cada llamada. Devuelve
  /// cuántas veces se llamó.
  int Function() guion(List<bool> resultados, {void Function()? antes}) {
    var llamadas = 0;
    when(
      () => repo.createIfAbsent(
        uid: any(named: 'uid'),
        email: any(named: 'email'),
      ),
    ).thenAnswer((_) async {
      antes?.call();
      final anda = resultados[llamadas++];
      if (!anda) throw Exception('client is offline');
    });
    return () => llamadas;
  }

  ProviderContainer contenedor({
    List<Duration> esperas = _sinEsperar,
    bool cancelada = false,
  }) {
    final c = ProviderContainer(overrides: [
      authStateChangesProvider.overrideWith((ref) => auth.stream),
      userRepositoryProvider.overrideWithValue(repo),
      esperasDelPerfilProvider.overrideWithValue(esperas),
      reportePerfilAseguradoProvider.overrideWithValue(
        (error, stack, {required reason}) async => reportados.add(reason),
      ),
      if (cancelada) altaCanceladaProvider.overrideWith((ref) => true),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  /// Monta el reintento como la pantalla del alta (que lo mantiene vivo),
  /// loguea la cuenta y espera a que termine.
  Future<void> correr(ProviderContainer c) async {
    c.listen(perfilAseguradoProvider, (_, __) {});
    auth.add(usuario());
    await pumpEventQueue();
    await c.read(perfilAseguradoProvider.future);
    await pumpEventQueue();
  }

  group('perfilAseguradoProvider', () {
    test('si el primer intento anda, no reintenta ni reporta', () async {
      final llamadas = guion([true]);

      await correr(contenedor());

      expect(llamadas(), 1);
      expect(reportados, isEmpty);
    });

    // El caso para el que existe: el create del login falló (en producción,
    // teléfonos nuevos) y el doc termina existiendo sin esperar al submit.
    test('reintenta hasta que anda, y no reporta', () async {
      final llamadas = guion([false, false, true]);

      await correr(contenedor());

      expect(llamadas(), 3);
      expect(reportados, isEmpty);
    });

    test('si ninguno anda y el doc no existe, reporta UNA vez', () async {
      final llamadas = guion([false, false, false, false]);

      await correr(contenedor());

      expect(llamadas(), 4);
      expect(reportados.single, contains('sigue sin existir'));
      expect(reportados.single, contains('4 intentos'));
    });

    // Hallazgo de la revisión: el último intento puede fallar porque el doc
    // APARECIÓ (el submit ganó la carrera y el pin de createdAt rechazó el
    // batch). Reportar «sigue sin existir» ahí sería falso.
    test('si ninguno anda pero el doc ya existe, NO reporta', () async {
      guion([false, false, false, false]);
      when(() => repo.get('u1')).thenAnswer(
        (_) async => UserProfile(
          uid: 'u1',
          email: 'a@b.com',
          displayName: 'carlos',
          role: UserRole.athlete,
          createdAt: DateTime.utc(2026, 9, 23),
          updatedAt: DateTime.utc(2026, 9, 23),
        ),
      );

      await correr(contenedor());

      expect(reportados, isEmpty);
    });

    test('sin cuenta logueada no hace nada', () async {
      final llamadas = guion([true]);
      final c = ProviderContainer(overrides: [
        authStateChangesProvider.overrideWith((ref) => Stream.value(null)),
        userRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(c.dispose);
      c.listen(perfilAseguradoProvider, (_, __) {});
      await pumpEventQueue();
      await c.read(perfilAseguradoProvider.future);

      expect(llamadas(), 0);
    });
  });

  group('perfilAseguradoProvider — calendario e intento en vuelo', () {
    // Hallazgo de Codex en #1232: las esperas se SUMAN. Con 0/3/10/30 los
    // intentos salían a los 0, 3, 13 y 43 s.
    test('las esperas por default dan intentos a los 0, 3, 10 y 30 s', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      var acumulado = Duration.zero;
      final momentos = [
        for (final espera in c.read(esperasDelPerfilProvider))
          acumulado += espera,
      ];

      expect(momentos, const [
        Duration.zero,
        Duration(seconds: 3),
        Duration(seconds: 10),
        Duration(seconds: 30),
      ]);
    });

    test('el provider registra el intento en vuelo, y esperar() lo espera',
        () async {
      final enVuelo = Completer<void>();
      when(
        () => repo.createIfAbsent(
          uid: any(named: 'uid'),
          email: any(named: 'email'),
        ),
      ).thenAnswer((_) => enVuelo.future);
      final c = contenedor();
      c.listen(perfilAseguradoProvider, (_, __) {});
      auth.add(usuario());
      await pumpEventQueue();

      var termino = false;
      unawaited(
        c.read(intentoDelPerfilProvider).esperar().then((_) => termino = true),
      );
      await pumpEventQueue();
      expect(termino, isFalse);

      enVuelo.complete();
      await pumpEventQueue();
      expect(termino, isTrue);
    });

    test('esperar() no tira si el intento falla, y respeta el tope', () async {
      await IntentoDelPerfil.enVuelo(Future<void>.error(Exception('offline')))
          .esperar();
      final nunca = Completer<void>();
      await IntentoDelPerfil.enVuelo(nunca.future)
          .esperar(tope: const Duration(milliseconds: 10));
    });
  });

  // Hallazgo de la revisión: un reintento podía crear `users/{uid}` —con el
  // mail— justo antes de que «Cancelar cuenta» borrara la cuenta de Auth, y el
  // doc quedaba huérfano (cancelOnboarding borra los docs ANTES de borrar la
  // cuenta; lo que se escribe después no lo limpia nadie).
  group('perfilAseguradoProvider — «Cancelar cuenta»', () {
    test('con la cancelación en curso no intenta crear nada', () async {
      final llamadas = guion([true]);

      await correr(contenedor(cancelada: true));

      expect(llamadas(), 0);
    });

    test('si se cancela entre intentos, no sigue ni reporta', () async {
      late ProviderContainer c;
      final llamadas = guion(
        [false, false, false, false],
        // La persona confirma «Cancelar cuenta» mientras sale el 1er intento.
        // En un microtask: el 1er intento sale DENTRO del build del provider,
        // y Riverpod no deja modificar otro provider ahí (en la app el flag lo
        // cambia la pantalla, nunca el build).
        antes: () => scheduleMicrotask(
          () => c.read(altaCanceladaProvider.notifier).state = true,
        ),
      );
      // Mide que una cancelación entre intentos corte el loop. En un
      // ProviderContainer de test lo corta el rebuild que dispara el flag; la
      // consulta explícita del flag en el loop (para cuando la app no tiene
      // frames) NO queda aislada acá: el control negativo sin ella sale verde.
      c = contenedor();

      await correr(c);

      expect(llamadas(), 1);
      expect(reportados, isEmpty);
    });

    // Si `cancelOnboarding` falla (p. ej. requires-recent-login), la cuenta
    // sigue viva y la pantalla vuelve el flag a false: los reintentos tienen
    // que retomar, o esa cuenta se queda sin doc hasta el submit.
    test('si la cancelación falla y el flag vuelve a false, reintenta',
        () async {
      final llamadas = guion([true]);
      final c = contenedor(cancelada: true);

      await correr(c);
      expect(llamadas(), 0);

      c.read(altaCanceladaProvider.notifier).state = false;
      await pumpEventQueue();
      await c.read(perfilAseguradoProvider.future);

      expect(llamadas(), 1);
    });
  });
}
