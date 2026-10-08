import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../data/lugar_search_service.dart';

/// Key de Places para el navegador. SIN default commiteado: sin
/// `--dart-define=PLACES_WEB_CLIENT_KEY=...` el servicio falla explícito
/// ([LugarSearchConfigError]). Debe ser una key restringida por referrer
/// HTTP y a "Places API (New)"; la key mobile (restringida por bundle) no
/// sirve en el navegador.
const String kPlacesWebClientKey = String.fromEnvironment(
  'PLACES_WEB_CLIENT_KEY',
);

final lugarSearchServiceProvider = Provider<LugarSearchService>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return LugarSearchService(httpClient: client, apiKey: kPlacesWebClientKey);
});
