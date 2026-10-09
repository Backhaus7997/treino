/// Key de CARTO Basemaps, leída en tiempo de compilación.
///
/// **SIN default commiteado**: el repo es público. Se pasa con
/// `--dart-define=CARTO_API_KEY=<key>` en `flutter run` y en todo build de
/// release. Sin ella el mapa carga igual, pero CARTO estampa "API KEY
/// REQUIRED" en cada tile. CARTO no devuelve error en ese caso, ni con una
/// key inválida: la única señal es la imagen.
const String cartoApiKey = String.fromEnvironment('CARTO_API_KEY');

/// Tiles CartoDB "Voyager": estilo claro tipo Google Maps (agua azul,
/// parques verdes, calles beige/blanco). Reemplazó al `dark_all` (calles
/// imperceptibles sobre negro) y al intento de Stadia Alidade Smooth Dark.
///
/// Trade-off: rompe la coherencia dark de la app, pero se pidió así porque el
/// dark dificultaba reconocer barrios y calles. Los markers de los PFs igual
/// destacan sobre el fondo claro.
///
/// Desde fines de agosto de 2026 CARTO exige API key (ver [cartoApiKey]).
/// Atribución OSM + CARTO obligatoria en cualquier plan.
const String _cartoVoyagerTemplate =
    'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png';

/// Subdominios del CDN de CARTO para el placeholder `{s}`.
const List<String> cartoSubdomains = ['a', 'b', 'c', 'd'];

/// Arma el `urlTemplate` de los tiles con la key de CARTO.
///
/// Con key vacía devuelve la URL sin `?key=`, idéntica a la de antes de este
/// cambio: el mapa sale con marca de agua pero no se rompe.
String cartoTileUrl(String apiKey) => apiKey.isEmpty
    ? _cartoVoyagerTemplate
    : '$_cartoVoyagerTemplate?key=${Uri.encodeQueryComponent(apiKey)}';
