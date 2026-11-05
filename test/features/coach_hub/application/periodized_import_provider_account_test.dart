// El borrador del import de plan es de UNA cuenta.
//
// Mismo bug que el #1670 con `selectedChatIdProvider`: `periodizedImportProvider`
// era un `StateProvider` global sin dependencias, y el `ProviderScope` raíz no
// cambia con el uid. El job de PDF ya borraba SU borrador al cambiar de cuenta
// (`HubPdfImportJobNotifier._resetForAccountChange`), pero sólo si seguía
// siendo el suyo: el de un Excel —o el de los flujos de la app— quedaba vivo, y
// el PF que entraba después abría la vista previa con el plan del anterior.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/application/plan_import_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;

import '../presentation/periodized_draft_fixtures.dart' show pdfDraft;

final _uid = StateProvider<String?>((ref) => 'pf-lautaro');

ProviderContainer _container({bool listened = true}) {
  final container = ProviderContainer(
    overrides: [currentUidProvider.overrideWith((ref) => ref.watch(_uid))],
  );
  addTearDown(container.dispose);
  // Lo mantiene vivo como lo mantiene la vista previa con su `ref.watch`.
  if (listened) container.listen(periodizedImportProvider, (_, __) {});
  return container;
}

void main() {
  test('cerrar sesión descarta el borrador', () {
    final container = _container();
    container.read(periodizedImportProvider.notifier).state = pdfDraft();

    container.read(_uid.notifier).state = null;

    expect(container.read(periodizedImportProvider), isNull);
  });

  test('entrar con otra cuenta no hereda el borrador de la anterior', () {
    final container = _container();
    container.read(periodizedImportProvider.notifier).state = pdfDraft();

    container.read(_uid.notifier).state = null;
    container.read(_uid.notifier).state = 'pf-diego';

    expect(container.read(periodizedImportProvider), isNull);
  });

  // Sin nadie escuchando —el PF subió el Excel y se fue a otra sección antes
  // de cerrar sesión— el reset tiene que estar igual cuando se vuelva a leer.
  test('sin pantalla abierta, la próxima lectura ya no lo ve', () {
    final container = _container(listened: false);
    container.read(periodizedImportProvider.notifier).state = pdfDraft();

    container.read(_uid.notifier).state = 'pf-diego';

    expect(container.read(periodizedImportProvider), isNull);
  });

  test('el mismo uid otra vez (refresh de token) no descarta el borrador', () {
    final container = _container();
    final draft = pdfDraft();
    container.read(periodizedImportProvider.notifier).state = draft;
    var recalculos = 0;
    container.listen(currentUidProvider, (_, __) {});
    container.listen(_uid, (_, __) => recalculos++);

    // Un String igual pero NO idéntico: con el literal, `StateProvider`
    // compara por `identical`, no notifica, y el test no ejercita nada. Lo que
    // tiene que frenar el reset es el `==` de `currentUidProvider`.
    final mismoUid = String.fromCharCodes('pf-lautaro'.codeUnits);
    expect(identical(mismoUid, 'pf-lautaro'), isFalse);
    container.read(_uid.notifier).state = mismoUid;

    expect(recalculos, 1, reason: 'el uid tiene que haber vuelto a emitir');
    expect(container.read(periodizedImportProvider), same(draft));
  });
}
