import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/utils/deep_link_destination.dart';

void main() {
  group('DeepLinkDestination.fromQuery', () {
    test('sin to -> null (el default disfrazado)', () {
      expect(DeepLinkDestination.fromQuery(const {}), isNull);
    });

    test('to desconocido -> null, no explota', () {
      expect(
        DeepLinkDestination.fromQuery(const {'to': 'algo-que-no-existe'}),
        isNull,
      );
    });

    test('to=facturacion', () {
      final d = DeepLinkDestination.fromQuery(const {'to': 'facturacion'});
      expect(d?.to, DeepLinkTo.facturacion);
      expect(d?.athleteId, isNull);
    });

    test('to=agenda', () {
      final d = DeepLinkDestination.fromQuery(const {'to': 'agenda'});
      expect(d?.to, DeepLinkTo.agenda);
    });

    test('to=solicitudes', () {
      final d = DeepLinkDestination.fromQuery(const {'to': 'solicitudes'});
      expect(d?.to, DeepLinkTo.solicitudes);
    });

    test('to=alumno con id -> lleva el athleteId', () {
      final d = DeepLinkDestination.fromQuery(
        const {'to': 'alumno', 'id': 'uid-123'},
      );
      expect(d?.to, DeepLinkTo.alumno);
      expect(d?.athleteId, 'uid-123');
    });

    // El caso que importa: un `to=alumno` sin id no es un destino valido.
    // Sin este chequeo, el router intentaria armar `/alumnos/null` o
    // `/coach/athlete/null` — una ruta que no existe, en vez de caer
    // limpiamente al dashboard.
    test('to=alumno SIN id -> null, no un destino con athleteId null', () {
      expect(
        DeepLinkDestination.fromQuery(const {'to': 'alumno'}),
        isNull,
      );
    });

    test('to=alumno con id vacio -> tambien null', () {
      expect(
        DeepLinkDestination.fromQuery(const {'to': 'alumno', 'id': ''}),
        isNull,
      );
    });

    // Parametros de mas (por ejemplo un cache-buster) no rompen el parsing.
    test('ignora parametros extra que no conoce', () {
      final d = DeepLinkDestination.fromQuery(
        const {'to': 'agenda', 'v': '12345', 'utm_source': 'mail'},
      );
      expect(d?.to, DeepLinkTo.agenda);
    });
  });
}
