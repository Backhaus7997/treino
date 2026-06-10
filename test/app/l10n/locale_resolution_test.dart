// T-I18N-004 — SCENARIO-755, SCENARIO-756, SCENARIO-789 (regression).
//
// Per ADR-I18N-005: only es-AR has real translations. `intl_es.arb` and
// `intl_en.arb` exist as codegen scaffolds with empty values. ANY device
// locale that is not exactly es-AR must resolve to es-AR — including
// `en`, `es` (no country), `es-ES`, etc. — otherwise the user sees empty
// strings (smoke gap discovered 2026-06-10 on en-locale simulator).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/locale_resolver.dart';

void main() {
  group('resolveLocale — ADR-I18N-005 (force es-AR)', () {
    const supported = [
      Locale('es', 'AR'),
      Locale('es'),
      Locale('en'),
    ];

    // SCENARIO-755: es-AR device → es-AR.
    test('es-AR device locale resolves to es-AR', () {
      final result = resolveLocale(const Locale('es', 'AR'), supported);
      expect(result, const Locale('es', 'AR'));
    });

    // SCENARIO-789 regression: en-locale device must NOT resolve to en
    // (the scaffold ARB is empty — would render blank UI).
    test('en device locale falls back to es-AR (scaffold guard)', () {
      final result = resolveLocale(const Locale('en'), supported);
      expect(result, const Locale('es', 'AR'));
    });

    // SCENARIO-789 regression: en-US likewise.
    test('en-US device locale falls back to es-AR', () {
      final result = resolveLocale(const Locale('en', 'US'), supported);
      expect(result, const Locale('es', 'AR'));
    });

    // SCENARIO-789 regression: bare `es` (no country) is also a scaffold —
    // must fall back to es-AR.
    test('es device locale (no country) falls back to es-AR', () {
      final result = resolveLocale(const Locale('es'), supported);
      expect(result, const Locale('es', 'AR'));
    });

    // SCENARIO-789 regression: es-ES is unsupported AND would hit the scaffold
    // via language-only matching — must fall back to es-AR.
    test('es-ES device locale falls back to es-AR', () {
      final result = resolveLocale(const Locale('es', 'ES'), supported);
      expect(result, const Locale('es', 'AR'));
    });

    // SCENARIO-756: fr-FR (unsupported language) → forced es-AR.
    test('fr-FR unsupported device locale falls back to es-AR', () {
      final result = resolveLocale(const Locale('fr', 'FR'), supported);
      expect(result, const Locale('es', 'AR'));
    });

    // SCENARIO-756 triangulation: pt-BR → forced es-AR.
    test('pt-BR unsupported device locale falls back to es-AR', () {
      final result = resolveLocale(const Locale('pt', 'BR'), supported);
      expect(result, const Locale('es', 'AR'));
    });
  });
}
