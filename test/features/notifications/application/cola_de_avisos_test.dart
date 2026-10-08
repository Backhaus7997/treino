// La cola de avisos que esperan al permiso (plan del PF §5.1).
//
// `PermissionGate` no pide el permiso hasta tener el perfil cargado y el
// onboarding resuelto, así que en una instalación nueva hay una ventana
// GARANTIZADA —no un caso de borde— en la que ya llegan pushes y todavía no
// hay permiso. Y adentro de esa ventana los dos sistemas fallan distinto:
//
//   iOS      → `show()` tira (Error 2003) y devuelve false → caía al cartel.
//   Android  → sin POST_NOTIFICATIONS no tira nada: el sistema descarta la
//              notificación en silencio y `show()` devuelve TRUE, así que el
//              aviso desaparecía entero, sin cartel y sin log.
//
// Por eso lo que esta cola tiene que garantizar no es "ordenar bien": es que
// NADA se pierda sin que esté escrito dónde. Lo único que se descarta es por
// el tope, y estos tests fijan en qué punta.

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/notifications/application/cola_de_avisos.dart';

Aviso _aviso(String id) => Aviso(title: id, body: 'cuerpo $id');

void main() {
  group('ColaDeAvisos', () {
    test('drenar devuelve lo encolado, en orden de llegada', () {
      final cola = ColaDeAvisos()
        ..encolar(_aviso('a'))
        ..encolar(_aviso('b'));

      expect(cola.drenar().map((a) => a.title), ['a', 'b']);
    });

    test('drenar deja la cola vacía', () {
      final cola = ColaDeAvisos()..encolar(_aviso('a'));

      cola.drenar();

      expect(cola.vacia, isTrue);
      expect(cola.largo, 0);
      // El segundo drenaje no puede repetir el aviso: el listener del permiso
      // y el timer pueden disparar los dos, y el usuario vería todo dos veces.
      expect(cola.drenar(), isEmpty);
    });

    test('al desbordar tira los MÁS VIEJOS y conserva los nuevos', () {
      final cola = ColaDeAvisos(maximo: 3);
      for (final id in ['1', '2', '3', '4', '5']) {
        cola.encolar(_aviso(id));
      }

      expect(
        cola.drenar().map((a) => a.title),
        ['3', '4', '5'],
        reason: 'lo que se pierde tiene que ser lo más viejo, que es también '
            'lo menos urgente — al revés se descartaría el aviso recién '
            'llegado, que es el único que el usuario está esperando',
      );
    });

    test('el deep link sobrevive a la espera', () {
      // Es la mitad que importa del aviso: sin él, el usuario recibe el aviso
      // pero tocarlo no lo lleva a ningún lado.
      final cola = ColaDeAvisos()
        ..encolar(const Aviso(
          title: 'Molestia',
          body: 'Lucía reportó algo',
          deepLink: '/coach/athlete/a1/session/s1',
        ));

      expect(cola.drenar().single.deepLink, '/coach/athlete/a1/session/s1');
    });

    test('una cola vacía drena vacío sin romperse', () {
      expect(ColaDeAvisos().drenar(), isEmpty);
    });

    test('una cola de tope cero no se construye: descartaría todo', () {
      expect(() => ColaDeAvisos(maximo: 0), throwsA(isA<AssertionError>()));
    });
  });
}
