import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/data/deferred_invite_source.dart';

void main() {
  test('sin proveedor no hay invitación de instalación, y no rompe', () async {
    // Es la implementación de hoy y la que corre en producción. El resto del
    // flujo —casos B a E— está construido para no depender de esto: lo único
    // que se pierde es que la invitación sobreviva a INSTALAR la app, y ese
    // viaje todavía no se puede empezar (no hay ficha pública en las tiendas).
    expect(await const SinDeferredInvites().trainerIdDeLaInstalacion(), isNull);
  });
}
