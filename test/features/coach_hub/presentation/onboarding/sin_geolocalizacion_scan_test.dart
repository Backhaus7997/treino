import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// SCENARIO-CHW-ONB-043 — el onboarding del PF no usa la geolocalización del
/// dispositivo.
///
/// POR QUÉ. En la web el PF ubica su lugar escribiendo una dirección y
/// eligiendo un resultado de Places. Pedir `navigator.geolocation` (o traer
/// `geolocator`) abriría un prompt de permiso del navegador que el diseño (D9)
/// descartó a propósito: la ubicación que el PF publica es una decisión suya,
/// no un dato que se le extrae.
///
/// QUÉ MIRA. Los archivos de `presentation/onboarding/`, el servicio de
/// búsqueda y su provider, y UN nivel de dependencias propias: si alguno
/// importa un archivo de `lib/` que a su vez menciona `geolocator` (por ejemplo
/// `core/utils/location_precision.dart`), también cuenta.
///
/// LO QUE **NO** PRUEBA. Que la web funcione sin geolocalización: un scanner
/// textual solo dice que una cadena NO está. Que la búsqueda por dirección
/// ande lo prueban `paso_perfil_pf_test.dart` y `lugar_search_service_test.dart`.
final _prohibidos = RegExp(
  r'geolocator|navigator\.geolocation|Geolocator\.',
  caseSensitive: false,
);

final _importPropio = RegExp(r'''package:treino/([^'"]+\.dart)''');

/// Devuelve qué archivos de [archivos] mencionan geolocalización, directa o
/// por una dependencia propia de un nivel.
List<String> infractores(
  Iterable<File> archivos, {
  String Function(String path)? leer,
}) {
  String contenido(String path) => leer != null
      ? leer(path)
      : (File(path).existsSync() ? File(path).readAsStringSync() : '');

  final malos = <String>[];
  for (final f in archivos) {
    final texto = contenido(f.path);
    if (_prohibidos.hasMatch(texto)) {
      malos.add('${f.path} (directo)');
      continue;
    }
    for (final m in _importPropio.allMatches(texto)) {
      final dep = 'lib/${m.group(1)}';
      if (_prohibidos.hasMatch(contenido(dep))) {
        malos.add('${f.path} -> $dep');
      }
    }
  }
  return malos;
}

void main() {
  group('SCENARIO-CHW-ONB-043 — sin geolocalización del dispositivo', () {
    final archivos = <File>[
      ...Directory('lib/features/coach_hub/presentation/onboarding')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')),
      File('lib/features/coach_hub/data/lugar_search_service.dart'),
      File('lib/features/coach_hub/application/lugar_search_providers.dart'),
    ];

    test('el scan ve los archivos que dice mirar', () {
      expect(archivos.length, greaterThanOrEqualTo(8));
      for (final f in archivos) {
        expect(f.existsSync(), isTrue, reason: f.path);
      }
    });

    test('ninguno importa geolocator ni toca navigator.geolocation', () {
      expect(infractores(archivos), isEmpty);
    });

    // Control del scanner: sin esto un regex roto daría verde para siempre.
    test('el scanner SÍ detecta cada forma prohibida', () {
      final falso = File('lib/falso.dart');
      for (final muestra in [
        "import 'package:geolocator/geolocator.dart';",
        'final p = await Geolocator.getCurrentPosition();',
        'js.context[\'navigator\'].geolocation; // navigator.geolocation',
      ]) {
        expect(
          infractores([falso], leer: (_) => muestra),
          isNotEmpty,
          reason: muestra,
        );
      }
      // Y la dependencia propia de un nivel.
      expect(
        infractores(
          [falso],
          leer: (p) => p == 'lib/falso.dart'
              ? "import 'package:treino/core/utils/location_precision.dart';"
              : "import 'package:geolocator/geolocator.dart';",
        ),
        isNotEmpty,
      );
      expect(
        infractores([falso], leer: (_) => 'final x = 1;'),
        isEmpty,
      );
    });
  });
}
