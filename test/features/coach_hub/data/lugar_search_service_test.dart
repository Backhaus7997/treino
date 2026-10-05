import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:treino/features/coach_hub/data/lugar_search_service.dart';

const _key = 'KEY-DE-PRUEBA-123';

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
        apiKey: _key,
      );

      await service.buscar('Av. Siempreviva 742');

      expect(visto.method, 'POST');
      expect(
        visto.url.toString(),
        'https://places.googleapis.com/v1/places:searchText',
      );
      expect(visto.headers['X-Goog-Api-Key'], _key);
      expect(
        visto.headers['X-Goog-FieldMask'],
        'places.displayName,places.formattedAddress,places.location',
      );
      final body = jsonDecode(visto.body) as Map<String, dynamic>;
      expect(body['textQuery'], 'Av. Siempreviva 742');
      expect(body['languageCode'], 'es');
    });

    test('mapea location.latitude/longitude a lat/lng exactos', () async {
      final service = LugarSearchService(
        httpClient: MockClient(
          (_) async => _json({
            'places': [
              {
                'displayName': {'text': 'Casa Simpson', 'languageCode': 'es'},
                'formattedAddress': 'Av. Siempreviva 742, Springfield',
                'location': {'latitude': -34.603722, 'longitude': -58.381592},
              },
            ],
          }),
        ),
        apiKey: _key,
      );

      final r = await service.buscar('Av. Siempreviva 742');

      expect(r, hasLength(1));
      expect(r.single.label, 'Casa Simpson');
      expect(r.single.direccion, 'Av. Siempreviva 742, Springfield');
      expect(r.single.lat, -34.603722);
      expect(r.single.lng, -58.381592);
    });

    test('sin displayName usa la dirección como label; sin location se omite',
        () async {
      final service = LugarSearchService(
        httpClient: MockClient(
          (_) async => _json({
            'places': [
              {
                'formattedAddress': 'Calle 1',
                'location': {'latitude': 1.5, 'longitude': 2.5},
              },
              {
                'displayName': {'text': 'Sin coordenadas'},
                'formattedAddress': 'Calle 2',
              },
            ],
          }),
        ),
        apiKey: _key,
      );

      final r = await service.buscar('calle');

      expect(r, hasLength(1));
      expect(r.single.label, 'Calle 1');
    });

    test('busca solo desde 3 caracteres: sin red y sin error', () async {
      var llamadas = 0;
      final service = LugarSearchService(
        httpClient: MockClient((_) async {
          llamadas++;
          return _json({'places': []});
        }),
        apiKey: _key,
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
        apiKey: _key,
      );

      Object? capturado;
      try {
        await service.buscar('Av. Siempreviva 742');
      } catch (e) {
        capturado = e;
      }

      expect(capturado, isA<LugarSearchError>());
      expect((capturado! as LugarSearchError).statusCode, 403);
      expect(capturado.toString(), isNot(contains(_key)));
    });

    test('excepción de red lanza LugarSearchError sin la key', () async {
      final service = LugarSearchService(
        httpClient: MockClient(
          (req) async => throw http.ClientException(
            'fallo de red en ${req.headers['X-Goog-Api-Key']}',
          ),
        ),
        apiKey: _key,
      );

      Object? capturado;
      try {
        await service.buscar('Av. Siempreviva 742');
      } catch (e) {
        capturado = e;
      }

      expect(capturado, isA<LugarSearchError>());
      expect(capturado.toString(), isNot(contains(_key)));
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
      expect(capturado.toString(), isNot(contains(_key)));
    });

    test('respuesta sin places devuelve lista vacía legítima', () async {
      final service = LugarSearchService(
        httpClient: MockClient((_) async => _json(<String, Object?>{})),
        apiKey: _key,
      );
      expect(await service.buscar('Av. Siempreviva 742'), isEmpty);
    });
  });
}
