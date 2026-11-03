// El chat seleccionado del Coach Hub web es de UNA cuenta.
//
// Bug encontrado en la E2E de 1.3.0: en la misma pestaña, Lautaro abría un
// chat, cerraba sesión, entraba Diego y Diego veía ese chat abierto con los
// mensajes de Lautaro. `selectedChatIdProvider` era un `StateProvider` global
// sin dependencias: sobrevivía al cambio de usuario porque nada lo invalidaba.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/presentation/sections/chat/chat_section_screen.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;

final _uid = StateProvider<String?>((ref) => 'pf-lautaro');

ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: [currentUidProvider.overrideWith((ref) => ref.watch(_uid))],
  );
  addTearDown(container.dispose);
  // Lo mantiene vivo como lo mantiene la pantalla con su `ref.watch`.
  container.listen(selectedChatIdProvider, (_, __) {});
  return container;
}

void main() {
  test('cerrar sesión deselecciona el chat', () {
    final container = _container();
    container.read(selectedChatIdProvider.notifier).state = 'chat-de-lautaro';

    container.read(_uid.notifier).state = null;

    expect(container.read(selectedChatIdProvider), isNull);
  });

  test('entrar con otra cuenta no hereda el chat de la anterior', () {
    final container = _container();
    container.read(selectedChatIdProvider.notifier).state = 'chat-de-lautaro';

    container.read(_uid.notifier).state = null;
    container.read(_uid.notifier).state = 'pf-diego';

    expect(container.read(selectedChatIdProvider), isNull);
  });

  test('el mismo uid otra vez (refresh de token) no cierra el chat', () {
    final container = _container();
    container.read(selectedChatIdProvider.notifier).state = 'chat-de-lautaro';
    var recalculos = 0;
    container.listen(currentUidProvider, (_, __) {});
    container.listen(_uid, (_, __) => recalculos++);

    // Un String igual pero NO idéntico. Con el literal, `StateProvider` compara
    // por `identical`, ni notifica, y el test pasaba sin ejercitar nada: lo que
    // tiene que frenar el reset es el `==` de `currentUidProvider`.
    final mismoUid = String.fromCharCodes('pf-lautaro'.codeUnits);
    expect(identical(mismoUid, 'pf-lautaro'), isFalse);
    container.read(_uid.notifier).state = mismoUid;

    expect(recalculos, 1, reason: 'el uid tiene que haber vuelto a emitir');
    expect(container.read(selectedChatIdProvider), 'chat-de-lautaro');
  });
}
