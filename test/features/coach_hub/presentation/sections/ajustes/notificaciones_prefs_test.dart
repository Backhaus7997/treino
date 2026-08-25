// Invariantes de la matriz de preferencias de notificación.
//
// Estos tests NO prueban UI: prueban que la taxonomía siga siendo honesta.
// Una fila que promete un canal sin backend detrás es una mentira que el
// usuario descubre cuando el aviso no llega, y esa clase de bug no la agarra
// ningún widget test.

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/presentation/sections/ajustes/tabs/notificaciones_prefs.dart';

void main() {
  group('kNotifTypes — taxonomía', () {
    test('no hay claves duplicadas', () {
      final keys = kNotifTypes.map((t) => t.key).toList();
      expect(keys.toSet().length, keys.length);
    });

    test('toda clave de kEmailBackedTypes existe en kNotifTypes', () {
      final keys = kNotifTypes.map((t) => t.key).toSet();
      for (final backed in kEmailBackedTypes) {
        expect(
          keys,
          contains(backed),
          reason: '"$backed" declara envío por email pero no es una fila de la '
              'matriz — el PF no tiene dónde apagarlo.',
        );
      }
    });

    test('las filas sin backend real quedaron fuera', () {
      // pago_recibido / alumno_inactivo / comida_pendiente venían del mockup y
      // nunca tuvieron Cloud Function. Si alguna vuelve, tiene que volver
      // JUNTO con su trigger en functions/src/notifications/.
      final keys = kNotifTypes.map((t) => t.key).toSet();
      expect(keys, isNot(contains('pago_recibido')));
      expect(keys, isNot(contains('alumno_inactivo')));
      expect(keys, isNot(contains('comida_pendiente')));
    });
  });

  group('NotifPrefs — defaults', () {
    final prefs = NotifPrefs.fromFirestore(null);

    test('push arranca prendido en todas las filas', () {
      for (final t in kNotifTypes) {
        expect(prefs.isOn(t.key, NotifChannel.push), isTrue, reason: t.key);
      }
    });

    // LA regresión a evitar. El default viejo dejaba mensaje_nuevo con email en
    // ON; conectar la matriz al backend habría convertido cada mensaje de chat
    // en un mail, con la reputación de remitente como daño colateral.
    test('mensaje_nuevo NUNCA arranca con email prendido', () {
      expect(prefs.isOn('mensaje_nuevo', NotifChannel.email), isFalse);
    });

    test('email arranca prendido SOLO donde hay envío real', () {
      for (final t in kNotifTypes) {
        expect(
          prefs.isOn(t.key, NotifChannel.email),
          kEmailBackedTypes.contains(t.key),
          reason: '"${t.key}": el default de email tiene que seguir a '
              'kEmailBackedTypes, no al revés.',
        );
      }
    });

    test('whatsapp arranca apagado en todo — no hay canal implementado', () {
      for (final t in kNotifTypes) {
        expect(prefs.isOn(t.key, NotifChannel.whatsapp), isFalse,
            reason: t.key);
      }
    });
  });

  group('NotifPrefs — toggle', () {
    test('toggle es inmutable y no arrastra las otras filas', () {
      final base = NotifPrefs.fromFirestore(null);
      final next = base.toggle('mensaje_nuevo', NotifChannel.push, false);

      expect(base.isOn('mensaje_nuevo', NotifChannel.push), isTrue);
      expect(next.isOn('mensaje_nuevo', NotifChannel.push), isFalse);
      // El resto de la matriz queda intacta.
      expect(next.isOn('nueva_solicitud', NotifChannel.push), isTrue);
      expect(next.isOn('nueva_solicitud', NotifChannel.email), isTrue);
    });

    test('toFirestore serializa las 5 filas × 3 canales', () {
      final map = NotifPrefs.fromFirestore(null).toFirestore();

      expect(map.keys.toSet(), kNotifTypes.map((t) => t.key).toSet());
      for (final entry in map.values) {
        expect((entry as Map).keys.toSet(),
            NotifChannel.values.map((c) => c.name).toSet());
      }
    });

    test('fromFirestore rellena los huecos con los defaults', () {
      // Un doc viejo que solo guardó una fila parcial.
      final prefs = NotifPrefs.fromFirestore({
        'mensaje_nuevo': {'push': false},
      });

      expect(prefs.isOn('mensaje_nuevo', NotifChannel.push), isFalse);
      // Los canales ausentes caen al default, no a false.
      expect(prefs.isOn('mensaje_nuevo', NotifChannel.email), isFalse);
      expect(prefs.isOn('nueva_solicitud', NotifChannel.email), isTrue);
    });
  });
}
