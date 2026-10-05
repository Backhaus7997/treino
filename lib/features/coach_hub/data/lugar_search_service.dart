import 'dart:convert';

import 'package:http/http.dart' as http;

/// Un lugar devuelto por la búsqueda por dirección del PF.
///
/// [lat]/[lng] son EXACTOS (sin redondear): paridad con mobile, que guarda
/// la coordenada tal cual y deriva el `geohash5` de ella.
class LugarCandidato {
  const LugarCandidato({
    required this.label,
    required this.direccion,
    required this.lat,
    required this.lng,
  });

  /// `displayName.text`, o la dirección si Places no manda nombre.
  final String label;
  final String direccion;
  final double lat;
  final double lng;
}

/// El servicio está mal configurado (key vacía): error de armado, no de red.
///
/// Distinto de [LugarSearchError] y de "sin resultados": la UI NO debe
/// leerlo como "no hay lugares". El mensaje nunca incluye la key.
class LugarSearchConfigError implements Exception {
  const LugarSearchConfigError(this.message);

  final String message;

  @override
  String toString() => 'LugarSearchConfigError: $message';
}

/// Falló el request (red o status != 200). Nunca incluye la key.
class LugarSearchError implements Exception {
  const LugarSearchError(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'LugarSearchError($statusCode): $message';
}

/// Google Places Text Search (New) llamado DIRECTO desde el navegador
/// (design D9). Que el endpoint acepte CORS se verifica a mano (Task 0).
///
/// La key llega por `--dart-define=PLACES_WEB_CLIENT_KEY=<key>`; no hay
/// default commiteado: sin ella [buscar] lanza [LugarSearchConfigError].
class LugarSearchService {
  LugarSearchService({
    required http.Client httpClient,
    required String apiKey,
  })  : _httpClient = httpClient,
        _apiKey = apiKey;

  static final Uri _endpoint =
      Uri.parse('https://places.googleapis.com/v1/places:searchText');

  static const String fieldMask =
      'places.displayName,places.formattedAddress,places.location';

  /// Largo mínimo (tras `trim`) para gastar un request de Text Search.
  static const int minCaracteres = 3;

  final http.Client _httpClient;
  final String _apiKey;

  /// Busca [consulta]. Con menos de [minCaracteres] devuelve `[]` sin red.
  /// Los resultados sin coordenadas se descartan: no se pueden guardar.
  Future<List<LugarCandidato>> buscar(String consulta) async {
    if (_apiKey.isEmpty) {
      throw const LugarSearchConfigError(
        'PLACES_WEB_CLIENT_KEY está vacía: pasala al build con '
        '--dart-define=PLACES_WEB_CLIENT_KEY=<key restringida por referrer>.',
      );
    }
    final texto = consulta.trim();
    if (texto.length < minCaracteres) return const [];

    http.Response response;
    try {
      response = await _httpClient.post(
        _endpoint,
        headers: {
          'X-Goog-Api-Key': _apiKey,
          'X-Goog-FieldMask': fieldMask,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'textQuery': texto, 'languageCode': 'es'}),
      );
    } catch (_) {
      // No se interpola `e`: una ClientException puede traer la URL/headers.
      throw const LugarSearchError('searchText request failed');
    }

    if (response.statusCode != 200) {
      throw LugarSearchError(
        'searchText request returned an error',
        statusCode: response.statusCode,
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw const LugarSearchError('searchText response is not valid JSON');
    }
    if (decoded is! Map || decoded['places'] is! List) return const [];

    final out = <LugarCandidato>[];
    for (final entry in decoded['places'] as List) {
      if (entry is! Map) continue;
      final loc = entry['location'];
      if (loc is! Map) continue;
      final lat = loc['latitude'];
      final lng = loc['longitude'];
      if (lat is! num || lng is! num) continue;

      final direccion = entry['formattedAddress'];
      final dir = direccion is String ? direccion : '';
      final nombre = _texto(entry['displayName']);
      final label = (nombre != null && nombre.trim().isNotEmpty) ? nombre : dir;
      if (label.isEmpty) continue;

      out.add(LugarCandidato(
        label: label,
        direccion: dir,
        lat: lat.toDouble(),
        lng: lng.toDouble(),
      ));
    }
    return out;
  }

  String? _texto(Object? field) =>
      field is Map && field['text'] is String ? field['text'] as String : null;
}
