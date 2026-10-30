import 'package:fake_async/fake_async.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/utils/app_clock.dart';
import 'package:treino/features/coach_hub/application/pdf_import_quota_provider.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;

/// El cupo depende del reloj ART (claves de día y semana), no sólo de
/// Firestore: una pantalla abierta al cruzar la medianoche tiene que pasar al
/// cupo del día nuevo sin esperar a que cambie un documento.
void main() {
  tearDown(AppClock.unfreeze);

  test('al cruzar la medianoche ART el cupo del día se renueva solo', () {
    fakeAsync((async) {
      final db = FakeFirebaseFirestore();
      // Free: 2 por semana y 2 por día. Miércoles 23:59:30 ART = jueves
      // 02:59:30 UTC. Ya usó 1 hoy (miércoles) y 1 en la semana.
      AppClock.freeze(DateTime.utc(2026, 10, 22, 2, 59, 30).toLocal());
      db.collection('users').doc('pf1').set({'role': 'trainer'});
      db.collection('pdfImportUsage').doc('pf1').set({
        'weekKey': '2026-10-19',
        'weekCount': 1,
        'dayKey': '2026-10-21',
        'dayCount': 1,
      });
      async.flushMicrotasks();

      final container = ProviderContainer(overrides: [
        firestoreProvider.overrideWithValue(db),
        currentUidProvider.overrideWithValue('pf1'),
      ]);
      addTearDown(container.dispose);
      final values = <PdfImportRemaining?>[];
      container.listen(
          pdfImportRemainingProvider, (_, next) => values.add(next),
          fireImmediately: true);
      // Los streams del doble de Firestore emiten en tareas, no microtasks.
      async.elapse(const Duration(milliseconds: 200));
      expect(values.last, isNotNull);
      expect(values.last!.day, 1, reason: 'miércoles: le queda 1 de 2');

      // Pasa la medianoche ART: jueves 00:00:05. Firestore no cambia.
      AppClock.freeze(DateTime.utc(2026, 10, 22, 3, 0, 5).toLocal());
      async.elapse(const Duration(seconds: 40));
      async.flushMicrotasks();

      expect(values.last!.day, 2, reason: 'jueves: el día empieza entero');
      expect(values.last!.week, 1, reason: 'la semana sigue siendo la misma');
      container.dispose();
    });
  });
}
