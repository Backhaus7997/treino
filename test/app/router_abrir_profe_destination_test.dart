// El destino fino de `/abrir/profe` en mobile — ver `deep_link_destination.dart`.
//
// El #898 agregó `/abrir/profe` sin ningún test de Dart (solo cobertura de
// que el manifest/AASA/vercel.json estuvieran bien armados, en
// `scripts/test/deep_links.test.js`). El redirect en sí, escrito como lambda
// anónima adentro de la GoRoute, nunca se probó. Se extrajo a
// `mobileTrainerEntryPath` justamente para poder cerrar ese hueco acá.

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/router.dart';
import 'package:treino/core/utils/deep_link_destination.dart';

void main() {
  group('mobileTrainerEntryPath', () {
    test('sin destino -> agenda (default historico, sin cambios)', () {
      expect(mobileTrainerEntryPath(null), '/coach?tab=agenda');
    });

    test('to=facturacion -> /facturacion/planes', () {
      const dest = DeepLinkDestination(DeepLinkTo.facturacion);
      expect(mobileTrainerEntryPath(dest), '/facturacion/planes');
    });

    test('to=agenda -> el mismo lugar que el default', () {
      const dest = DeepLinkDestination(DeepLinkTo.agenda);
      expect(mobileTrainerEntryPath(dest), mobileTrainerEntryPath(null));
    });

    test('to=solicitudes -> /coach a secas (no hay pantalla propia)', () {
      const dest = DeepLinkDestination(DeepLinkTo.solicitudes);
      expect(mobileTrainerEntryPath(dest), '/coach');
    });

    test('to=alumno -> /coach/athlete/:id, con el id que trajo', () {
      const dest = DeepLinkDestination(DeepLinkTo.alumno, 'uid-456');
      expect(mobileTrainerEntryPath(dest), '/coach/athlete/uid-456');
    });

    test('to=invitacion -> agenda: esta función es la entrada del PF', () {
      // Pasa de verdad: el PF abre el link que él mismo generó, probando que
      // anda o porque se lo reenviaron. Mandarlo a una pantalla de vinculación
      // sería ofrecerle vincularse consigo mismo, y el repositorio lo rechaza
      // igual con un ArgumentError. La invitación la consume el ALUMNO, por
      // otro camino (`InviteGate`).
      const dest = DeepLinkDestination(DeepLinkTo.invitacion, null, 'pf-1');
      expect(mobileTrainerEntryPath(dest), mobileTrainerEntryPath(null));
    });
  });
}
