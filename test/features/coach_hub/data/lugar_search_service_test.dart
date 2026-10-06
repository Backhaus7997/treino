import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:treino/features/coach_hub/data/lugar_search_service.dart';

const _credencialFalsa = 'credencial-falsa-de-test';

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  group('LugarSearchService (SCENARIO-CHW-ONB-065)', () {
    test('el request lleva la key, el fieldMask y languageCode es', () async {
      late http.Request visto;
      final service = LugarSearchService(
        httpClient: MockClient((req) async {
          visto = req;
          return _json({'places': []});
        }),
        apiKey: _credencialFalsa,
      );

      await service.buscar('Av. Siempreviva 742');

      expect(visto.method, 'POST');
      expect(
        visto.url.toString(),
        'https://places.googleapis.com/v1/places:searchText',
      );
      expect(visto.headers['X-Goog-Api-Key'], _credencialFalsa);
      expect(
        visto.headers['X-Goog-FieldMask'],
        // Nombre y dirección se piden para MOSTRARLOS en la lista de
        // candidatos; no se persisten (ver el comentario de fieldMask).
        'places.id,places.location,places.displayName,'
        'places.formattedAddress',
      );
      final body = jsonDecode(visto.body) as Map<String, dynamic>;
      expect(body['textQuery'], 'Av. Siempreviva 742');
      expect(body['languageCode'], 'es');
    });

    test('mapea id y location.latitude/longitude exactos', () async {
      final service = LugarSearchService(
        httpClient: MockClient(
          (_) async => _json({
            'places': [
              {
                'id': 'ChIJabc123',
                'location': {'latitude': -34.603722, 'longitude': -58.381592},
              },
            ],
          }),
        ),
        apiKey: _credencialFalsa,
      );

      final r = await service.buscar('Av. Siempreviva 742');

      expect(r, hasLength(1));
      expect(r.single.placeId, 'ChIJabc123');
      expect(r.single.lat, -34.603722);
      expect(r.single.lng, -58.381592);
    });

    test('el candidato carga nombre y dirección solo para mostrarlos',
        () async {
      final service = LugarSearchService(
        httpClient: MockClient(
          (_) async => _json({
            'places': [
              {
                'id': 'ChIJabc123',
                'displayName': {'text': 'Casa Simpson'},
                'formattedAddress': 'Av. Siempreviva 742, Springfield',
                'location': {'latitude': 1.5, 'longitude': 2.5},
              },
              {
                'id': 'ChIJsin-texto',
                'location': {'latitude': 3.5, 'longitude': 4.5},
              },
            ],
          }),
        ),
        apiKey: _credencialFalsa,
      );

      final r = await service.buscar('calle');

      expect(r.first.displayName, 'Casa Simpson');
      expect(r.first.formattedAddress, 'Av. Siempreviva 742, Springfield');
      // Sin texto de Google el candidato sigue siendo válido.
      expect(r.last.displayName, isEmpty);
      expect(r.last.formattedAddress, isEmpty);
    });

    test('sin id o sin location se omite (no se puede refrescar ni guardar)',
        () async {
      final service = LugarSearchService(
        httpClient: MockClient(
          (_) async => _json({
            'places': [
              {
                'location': {'latitude': 1.5, 'longitude': 2.5},
              },
              {'id': 'sin-coordenadas'},
              {
                'id': 'ok',
                'location': {'latitude': 3.5, 'longitude': 4.5},
              },
            ],
          }),
        ),
        apiKey: _credencialFalsa,
      );

      final r = await service.buscar('calle');

      expect(r, hasLength(1));
      expect(r.single.placeId, 'ok');
    });

    test('busca solo desde 3 caracteres: sin red y sin error', () async {
      var llamadas = 0;
      final service = LugarSearchService(
        httpClient: MockClient((_) async {
          llamadas++;
          return _json({'places': []});
        }),
        apiKey: _credencialFalsa,
      );

      expect(await service.buscar('ab'), isEmpty);
      expect(await service.buscar('  a  '), isEmpty);
      expect(llamadas, 0);

      await service.buscar('abc');
      expect(llamadas, 1);
    });

    test('key vacía lanza el error de configuración, sin red ni key', () async {
      var llamadas = 0;
      final service = LugarSearchService(
        httpClient: MockClient((_) async {
          llamadas++;
          return _json({'places': []});
        }),
        apiKey: '',
      );

      await expectLater(
        service.buscar('Av. Siempreviva 742'),
        throwsA(isA<LugarSearchConfigError>()),
      );
      expect(llamadas, 0);
    });

    test('key vacía falla también con consulta corta (no es "sin resultados")',
        () async {
      final service = LugarSearchService(
        httpClient: MockClient((_) async => _json({'places': []})),
        apiKey: '',
      );

      await expectLater(
        service.buscar('ab'),
        throwsA(isA<LugarSearchConfigError>()),
      );
    });

    test('error HTTP lanza LugarSearchError sin la key en el mensaje',
        () async {
      final service = LugarSearchService(
        httpClient: MockClient((_) async => _json({'error': 'x'}, 403)),
        apiKey: _credencialFalsa,
      );

      Object? capturado;
      try {
        await service.buscar('Av. Siempreviva 742');
      } catch (e) {
        capturado = e;
      }

      expect(capturado, isA<LugarSearchError>());
      expect((capturado! as LugarSearchError).statusCode, 403);
      expect(capturado.toString(), isNot(contains(_credencialFalsa)));
    });

    test('excepción de red lanza LugarSearchError sin la key', () async {
      final service = LugarSearchService(
        httpClient: MockClient(
          (req) async => throw http.ClientException(
            'fallo de red en ${req.headers['X-Goog-Api-Key']}',
          ),
        ),
        apiKey: _credencialFalsa,
      );

      Object? capturado;
      try {
        await service.buscar('Av. Siempreviva 742');
      } catch (e) {
        capturado = e;
      }

      expect(capturado, isA<LugarSearchError>());
      expect(capturado.toString(), isNot(contains(_credencialFalsa)));
    });

    test('el error de configuración no contiene la key', () async {
      final service = LugarSearchService(
        httpClient: MockClient((_) async => _json({})),
        apiKey: '',
      );
      Object? capturado;
      try {
        await service.buscar('Av. Siempreviva 742');
      } catch (e) {
        capturado = e;
      }
      expect(capturado.toString(), contains('PLACES_WEB_CLIENT_KEY'));
      expect(capturado.toString(), isNot(contains(_credencialFalsa)));
    });

    test('respuesta sin places devuelve lista vacía legítima', () async {
      final service = LugarSearchService(
        httpClient: MockClient((_) async => _json(<String, Object?>{})),
        apiKey: _credencialFalsa,
      );
      expect(await service.buscar('Av. Siempreviva 742'), isEmpty);
    });
  });
}
