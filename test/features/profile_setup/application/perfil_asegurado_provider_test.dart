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
import 'package:treino/features/profile_setup/application/perfil_asegurado_provider.dart';

class _MockUser extends Mock implements User {}

class _MockUserRepository extends Mock implements UserRepository {}

void main() {
  late _MockUserRepository repo;
  late List<String> reportados;
  late StreamController<User?> auth;

  setUp(() {
    repo = _MockUserRepository();
    reportados = [];
    auth = StreamController<User?>();
  });

  // Sin await: en el test sin cuenta nadie escucha `auth`, y el `close()` de un
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
  /// `false` tira. Devuelve cuántas veces se llamó.
  int Function() guion(List<bool> resultados) {
    var llamadas = 0;
    when(
      () => repo.createIfAbsent(
        uid: any(named: 'uid'),
        email: any(named: 'email'),
      ),
    ).thenAnswer((_) async {
      final anda = resultados[llamadas++];
      if (!anda) throw Exception('client is offline');
    });
    return () => llamadas;
  }

  Future<void> correr() async {
    final c = ProviderContainer(overrides: [
      authStateChangesProvider.overrideWith((ref) => auth.stream),
      userRepositoryProvider.overrideWithValue(repo),
      esperasDelPerfilProvider.overrideWithValue(
        const [Duration.zero, Duration.zero, Duration.zero, Duration.zero],
      ),
      reportePerfilAseguradoProvider.overrideWithValue(
        (error, stack, {required reason}) async => reportados.add(reason),
      ),
    ]);
    addTearDown(c.dispose);
    // Lo mantiene vivo como lo hace la pantalla del alta.
    c.listen(perfilAseguradoProvider, (_, __) {});
    auth.add(usuario());
    await pumpEventQueue();
    await c.read(perfilAseguradoProvider.future);
  }

  group('perfilAseguradoProvider', () {
    test('si el primer intento anda, no reintenta ni reporta', () async {
      final llamadas = guion([true]);

      await correr();

      expect(llamadas(), 1);
      expect(reportados, isEmpty);
    });

    // El caso para el que existe: el create del login falló (en producción,
    // teléfonos nuevos) y el doc termina existiendo sin esperar al submit.
    test('reintenta hasta que anda, y no reporta', () async {
      final llamadas = guion([false, false, true]);

      await correr();

      expect(llamadas(), 3);
      expect(reportados, isEmpty);
    });

    test('si ninguno anda, reporta UNA vez con la cantidad de intentos',
        () async {
      final llamadas = guion([false, false, false, false]);

      await correr();

      expect(llamadas(), 4);
      expect(reportados.single, contains('4 intentos'));
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
}
