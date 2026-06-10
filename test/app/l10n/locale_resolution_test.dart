// T-I18N-004 RED — SCENARIO-755, SCENARIO-756
// Tests for locale resolution:
//   SCENARIO-755: es-AR device → es-AR locale resolved
//   SCENARIO-756: fr-FR device (unsupported) → forced es-AR fallback
//
// References resolveLocale() which does NOT exist yet — this is the RED.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/locale_resolver.dart';

void main() {
  group('resolveLocale — ADR-I18N-005', () {
    const supported = [
      Locale('es', 'AR'),
      Locale('es'),
      Locale('en'),
    ];

    // SCENARIO-755: es-AR device → es-AR resolved
    test('es-AR device locale resolves to es-AR', () {
      const deviceLocale = Locale('es', 'AR');
      final result = resolveLocale(deviceLocale, supported);
      expect(result, const Locale('es', 'AR'));
    });

    // SCENARIO-755 triangulation: es device → es resolved (base Spanish)
    test('es device locale resolves to es', () {
      const deviceLocale = Locale('es');
      final result = resolveLocale(deviceLocale, supported);
      expect(result, const Locale('es'));
    });

    // SCENARIO-756: fr-FR (unsupported) → forced es-AR
    test('fr-FR unsupported device locale falls back to es-AR', () {
      const deviceLocale = Locale('fr', 'FR');
      final result = resolveLocale(deviceLocale, supported);
      expect(result, const Locale('es', 'AR'));
    });

    // SCENARIO-756 triangulation: pt-BR (unsupported) → forced es-AR
    test('pt-BR unsupported device locale falls back to es-AR', () {
      const deviceLocale = Locale('pt', 'BR');
      final result = resolveLocale(deviceLocale, supported);
      expect(result, const Locale('es', 'AR'));
    });

    // en device locale → en resolved
    test('en device locale resolves to en', () {
      const deviceLocale = Locale('en');
      final result = resolveLocale(deviceLocale, supported);
      expect(result, const Locale('en'));
    });
  });
}
