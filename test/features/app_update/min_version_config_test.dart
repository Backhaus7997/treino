import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/app_update/domain/min_version_config.dart';

void main() {
  group('MinVersionConfig.fromMap', () {
    test('documento ausente o vacío', () {
      expect(MinVersionConfig.fromMap(null), isNull);
      final vacio = MinVersionConfig.fromMap(<String, dynamic>{})!;
      expect(vacio.minVersion, isEmpty);
    });

    test('lee ambas plataformas y las URLs', () {
      final c = MinVersionConfig.fromMap({
        'minVersion': {'ios': '1.4.0', 'android': '1.5.0'},
        'storeUrl': {
          'ios': 'https://apps.apple.com/app/id1',
          'android': 'https://play.google.com/x',
        },
      })!;
      expect(c.minVersion[AppUpdatePlatform.ios], '1.4.0');
      expect(c.minVersion[AppUpdatePlatform.android], '1.5.0');
      expect(c.storeUrl[AppUpdatePlatform.ios], startsWith('https://apps'));
    });

    test('entradas malformadas se descartan una por una', () {
      final c = MinVersionConfig.fromMap({
        'minVersion': {'ios': 'basura', 'android': '1.5.0'},
        'storeUrl': {'ios': 'javascript:alert(1)', 'android': 42},
      })!;
      expect(c.minVersion.containsKey(AppUpdatePlatform.ios), isFalse);
      expect(c.minVersion[AppUpdatePlatform.android], '1.5.0');
      expect(c.storeUrl, isEmpty);
    });

    test('forma equivocada (no-mapa) no revienta', () {
      final c = MinVersionConfig.fromMap({
        'minVersion': '1.4.0',
        'storeUrl': ['x'],
      })!;
      expect(c.minVersion, isEmpty);
      expect(c.storeUrl, isEmpty);
    });
  });

  group('UpdateRequirement.evaluar', () {
    final config = MinVersionConfig.fromMap({
      'minVersion': {'ios': '1.4.0', 'android': '2.0.0'},
      'storeUrl': {'ios': 'https://apps.apple.com/app/id1'},
    });

    UpdateRequirement? eval(
      AppUpdatePlatform? p,
      String? v, [
      MinVersionConfig? c,
    ]) =>
        UpdateRequirement.evaluar(
          platform: p,
          installedVersion: v,
          config: c ?? config,
        );

    test('más vieja que el mínimo de SU plataforma bloquea', () {
      expect(eval(AppUpdatePlatform.ios, '1.3.9'), isNotNull);
      expect(eval(AppUpdatePlatform.android, '1.9.9'), isNotNull);
    });

    test('cada plataforma usa su propio mínimo', () {
      expect(eval(AppUpdatePlatform.ios, '1.5.0'), isNull);
      expect(eval(AppUpdatePlatform.android, '1.5.0'), isNotNull);
    });

    test('igual o más nueva no bloquea', () {
      expect(eval(AppUpdatePlatform.ios, '1.4.0'), isNull);
      expect(eval(AppUpdatePlatform.ios, '1.4.0+3'), isNull);
      expect(eval(AppUpdatePlatform.ios, '9.0.0'), isNull);
    });

    test('la URL sale de la config y, si falta, del fallback', () {
      expect(eval(AppUpdatePlatform.ios, '1.0.0')!.storeUrl,
          'https://apps.apple.com/app/id1');
      expect(eval(AppUpdatePlatform.android, '1.0.0')!.storeUrl,
          kStoreUrlFallback[AppUpdatePlatform.android]);
    });

    test('falla abierto: sin plataforma, sin config, sin mínimo, sin versión',
        () {
      expect(eval(null, '1.0.0'), isNull);
      expect(
          UpdateRequirement.evaluar(
            platform: AppUpdatePlatform.ios,
            installedVersion: '1.0.0',
            config: null,
          ),
          isNull);
      expect(
          eval(
            AppUpdatePlatform.ios,
            '1.0.0',
            MinVersionConfig.fromMap({
              'minVersion': {'android': '9.0.0'},
            }),
          ),
          isNull);
      expect(eval(AppUpdatePlatform.ios, null), isNull);
      expect(eval(AppUpdatePlatform.ios, 'basura'), isNull);
    });
  });
}
