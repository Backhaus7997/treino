// Guard estructural del manifiesto de privacidad de iOS.
//
// Un `PrivacyInfo.xcprivacy` que existe en el repo pero NO está en la fase de
// Resources del target Runner **no viaja en el bundle**. El build sale verde,
// el archivo está commiteado, y Apple no ve nada. Es la peor variante posible:
// parece hecho.
//
// Estos tests miran el `project.pbxproj` directamente. Es feo, y es a propósito:
// el pbxproj se rompe con cualquier merge y nadie lo lee al revisar un PR.
//
// Mismo criterio que `scripts/test/storage_scripts_destination.test.js`: cuando
// la garantía vive en un archivo que nadie mira, el test tiene que mirarlo.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifiesto = File('ios/Runner/PrivacyInfo.xcprivacy');
  final pbxproj = File('ios/Runner.xcodeproj/project.pbxproj');

  group('PrivacyInfo.xcprivacy', () {
    test('existe', () {
      expect(manifiesto.existsSync(), isTrue,
          reason: 'Apple lo pide para las required-reason APIs');
    });

    test('está declarado como archivo del proyecto', () {
      expect(pbxproj.readAsStringSync(),
          contains('/* PrivacyInfo.xcprivacy */ = {isa = PBXFileReference'),
          reason: 'sin PBXFileReference, Xcode no lo conoce');
    });

    test('está en la fase de Resources — o sea, VIAJA en el bundle', () {
      // Este es el único assert que importa de verdad. Los otros dos pueden
      // pasar con un archivo que nunca llega al .app.
      expect(pbxproj.readAsStringSync(),
          contains('/* PrivacyInfo.xcprivacy in Resources */'),
          reason: 'está en el repo pero no se empaqueta: Apple no lo va a ver');
    });

    test('declara que no hay tracking cross-app', () {
      // Si algún día entra un SDK de ads o de atribución, esto tiene que
      // cambiar Y hay que sumar NSPrivacyTrackingDomains. Que el test lo fije
      // obliga a pasar por acá en vez de olvidarlo.
      final xml = manifiesto.readAsStringSync();
      expect(xml, contains('<key>NSPrivacyTracking</key>'));
      expect(
        RegExp(r'<key>NSPrivacyTracking</key>\s*<false/>').hasMatch(xml),
        isTrue,
        reason: 'NSPrivacyTracking dejó de ser false — '
            '¿entró un SDK de tracking? Entonces faltan los TrackingDomains',
      );
    });

    test('declara los tipos de dato que la app realmente recolecta', () {
      final xml = manifiesto.readAsStringSync();
      // No es una lista exhaustiva: es el piso que sabemos cierto por el
      // pubspec y por los permisos del Info.plist. Si mañana se saca una
      // feature, este test avisa que la declaración quedó de más.
      for (final tipo in [
        'NSPrivacyCollectedDataTypeEmailAddress',
        'NSPrivacyCollectedDataTypeUserID',
        'NSPrivacyCollectedDataTypePhotosorVideos',
        'NSPrivacyCollectedDataTypeFitness',
        'NSPrivacyCollectedDataTypeCrashData',
      ]) {
        expect(xml, contains(tipo), reason: 'falta declarar $tipo');
      }
    });
  });

  group('la declaración de ubicación tiene que matchear el código', () {
    List<File> dartDeLib() => Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    test('ningún call site usa el default implícito de geolocator', () {
      // `getCurrentPosition()` sin argumentos usa `LocationAccuracy.best`
      // por default. Eso NO es una decisión: es lo que quedó. Exigir el
      // parámetro explícito obliga a que cada call site diga qué precisión
      // pide y por qué — y hace que este test pueda auditarlo.
      final implicitas = dartDeLib()
          .where((f) =>
              f.readAsStringSync().contains('getCurrentPosition()'))
          .map((f) => f.path)
          .toList();

      expect(implicitas, isEmpty,
          reason: 'usan el default implícito (= best) en vez de '
              'kAthleteLocationSettings / kTrainerLocationSettings: '
              '${implicitas.join(", ")}');
    });

    test('si algún call site pide best o high, se declara PreciseLocation', () {
      // El invariante que importa: la declaración sigue al código. Si algún
      // día TODOS los usos bajan a `low`/`medium`, este test deja de exigir
      // PreciseLocation y hay que bajar también la declaración — que es justo
      // lo que uno se olvida.
      final pideFino = dartDeLib().any((f) {
        final src = f.readAsStringSync();
        return src.contains('LocationAccuracy.best') ||
            src.contains('LocationAccuracy.high');
      });

      final xml = manifiesto.readAsStringSync();
      if (pideFino) {
        expect(xml, contains('NSPrivacyCollectedDataTypePreciseLocation'),
            reason: 'hay call sites pidiendo best/high, así que la '
                'declaración no puede decir sólo CoarseLocation');
      }
    });

    test('el atleta NO pide la precisión más alta; el entrenador SÍ', () {
      // Los dos valores viven en `core/utils/location_precision.dart` y su
      // diferencia es lo que la sección "4. Ubicación" del texto legal le
      // promete al usuario. Si alguien los iguala, el texto pasa a ser falso.
      final src =
          File('lib/core/utils/location_precision.dart').readAsStringSync();
      expect(src, contains('kAthleteLocationSettings'));
      expect(src, contains('kTrainerLocationSettings'));
      expect(
        RegExp(r'kAthleteLocationSettings\s*=\s*LocationSettings\(\s*'
                r'accuracy:\s*LocationAccuracy\.high')
            .hasMatch(src),
        isTrue,
        reason: 'el atleta dejó de pedir `high` — revisá si el texto legal '
            'sigue siendo cierto',
      );
      expect(
        RegExp(r'kTrainerLocationSettings\s*=\s*LocationSettings\(\s*'
                r'accuracy:\s*LocationAccuracy\.best')
            .hasMatch(src),
        isTrue,
        reason: 'el pin publicado del PF dejó de pedir `best`',
      );
    });
  });

  group('el texto legal describe los DOS roles', () {
    test('la política dice que la del PF SÍ es visible para otros', () {
      // La versión anterior decía "Tu ubicación no es visible para otros
      // usuarios" a secas, y para un entrenador eso era falso: su pin se
      // publica en el mapa. Es el agujero que este cambio cierra.
      final src = File('lib/features/auth/presentation/legal/legal_content.dart')
          .readAsStringSync();
      expect(src, contains('SÍ es visible para los atletas'),
          reason: 'la sección Ubicación volvió a ocultar el caso del PF');
      expect(src, isNot(contains('Tu ubicación no es visible para otros')),
          reason: 'volvió la afirmación que le miente al entrenador');
    });

    test('la política afirma el redondeo del bias, y el código lo cumple', () {
      final legal = File('lib/features/auth/presentation/legal/legal_content.dart')
          .readAsStringSync();
      expect(legal, contains('zona aproximada de unos 5 km'));

      // Si el bias vuelve a mandar el punto exacto, esa frase pasa a ser
      // falsa. El código tiene que seguir mandando el centro de la celda.
      final places =
          File('lib/features/gyms/application/places_providers.dart')
              .readAsStringSync();
      expect(places, isNot(contains('biasLatitude: position?.latitude')),
          reason: 'volvieron las coordenadas crudas al request de Places, '
              'y el texto legal promete una celda de ~5 km');
      expect(places, contains('biasLatitude: biasCenter?.\$1'));
    });
  });
}
