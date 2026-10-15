import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/app_update/domain/app_version.dart';

void main() {
  group('parseAppVersion', () {
    test('completa, parcial y con sufijos', () {
      expect(parseAppVersion('1.4.0'), (major: 1, minor: 4, patch: 0));
      expect(parseAppVersion('2'), (major: 2, minor: 0, patch: 0));
      expect(parseAppVersion('2.3'), (major: 2, minor: 3, patch: 0));
      expect(parseAppVersion('1.4.0+12'), (major: 1, minor: 4, patch: 0));
      expect(parseAppVersion('1.4.0-beta.1'), (major: 1, minor: 4, patch: 0));
      expect(parseAppVersion('1.4.0-rc.1+7'), (major: 1, minor: 4, patch: 0));
      expect(parseAppVersion('  1.0.2  '), (major: 1, minor: 0, patch: 2));
    });

    test('malformadas devuelven null', () {
      for (final raw in [
        null,
        '',
        'abc',
        '1.x.0',
        '1.2.3.4',
        'v1.2.3',
        '1..2',
        '-1.0.0',
        '1.0.0+',
        '1.0.0 beta',
      ]) {
        expect(parseAppVersion(raw), isNull, reason: 'raw=$raw');
      }
    });
  });

  group('compareAppVersions', () {
    test('iguales', () {
      expect(compareAppVersions('1.4.0', '1.4.0'), 0);
      expect(compareAppVersions('1.4', '1.4.0'), 0);
    });

    test('menor / mayor por patch, minor y major', () {
      expect(compareAppVersions('1.4.0', '1.4.1')!, isNegative);
      expect(compareAppVersions('1.4.1', '1.4.0')!, isPositive);
      expect(compareAppVersions('1.3.9', '1.4.0')!, isNegative);
      expect(compareAppVersions('1.5.0', '1.4.9')!, isPositive);
      expect(compareAppVersions('0.9.9', '1.0.0')!, isNegative);
      expect(compareAppVersions('2.0.0', '1.99.99')!, isPositive);
    });

    test('compara numéricamente, no como texto', () {
      expect(compareAppVersions('1.10.0', '1.9.0')!, isPositive);
      expect(compareAppVersions('1.2.10', '1.2.9')!, isPositive);
    });

    test('el build number se ignora', () {
      expect(compareAppVersions('1.4.0+12', '1.4.0'), 0);
      expect(compareAppVersions('1.4.0+1', '1.4.0+99'), 0);
      expect(compareAppVersions('1.3.9+500', '1.4.0+1')!, isNegative);
    });

    test('malformada en cualquiera de los lados devuelve null', () {
      expect(compareAppVersions('x', '1.0.0'), isNull);
      expect(compareAppVersions('1.0.0', null), isNull);
    });
  });

  group('isOlderThan', () {
    test('solo es true cuando es estrictamente menor', () {
      expect(isOlderThan('1.3.9', '1.4.0'), isTrue);
      expect(isOlderThan('1.4.0', '1.4.0'), isFalse);
      expect(isOlderThan('1.4.1', '1.4.0'), isFalse);
      expect(isOlderThan('1.4.0+5', '1.4.0+9'), isFalse);
    });

    test('ante cualquier duda es false (falla abierto)', () {
      expect(isOlderThan('basura', '1.4.0'), isFalse);
      expect(isOlderThan('1.0.0', 'basura'), isFalse);
      expect(isOlderThan(null, '1.4.0'), isFalse);
      expect(isOlderThan('1.0.0', null), isFalse);
    });
  });
}
