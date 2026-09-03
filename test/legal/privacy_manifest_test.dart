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
    test('si el código pide precisión máxima, se declara PreciseLocation', () {
      // `Geolocator.getCurrentPosition()` SIN argumentos usa la precisión más
      // alta de la plataforma. Si alguien la baja a `LocationAccuracy.low`,
      // este test falla y hay que bajar también la declaración — que es
      // justo lo que uno se olvida.
      final llamadasSinAccuracy = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) =>
              f.readAsStringSync().contains('Geolocator.getCurrentPosition()'))
          .length;

      final xml = manifiesto.readAsStringSync();
      if (llamadasSinAccuracy > 0) {
        expect(xml, contains('NSPrivacyCollectedDataTypePreciseLocation'),
            reason: 'hay $llamadasSinAccuracy archivos llamando a '
                'getCurrentPosition() sin accuracy (= precisión máxima), '
                'así que la declaración NO puede decir sólo CoarseLocation');
      }
    });
  });
}
