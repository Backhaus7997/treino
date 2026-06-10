import 'package:flutter/material.dart';

/// Resolves the device locale to a supported app locale.
///
/// Per ADR-I18N-005: **es-AR is the only locale with real translations**.
/// `intl_es.arb` (bare `es`, no country) and `intl_en.arb` exist as codegen
/// scaffolds with empty values — they MUST NOT be served to users, otherwise
/// the UI renders blank strings (smoke gap discovered 2026-06-10 on an
/// en-locale simulator). Therefore the only safe contract is: return es-AR
/// regardless of device locale.
///
/// The `supported` parameter is kept for API stability (matches the Flutter
/// `localeResolutionCallback` signature) but is intentionally unused — once
/// `intl_en.arb` is populated with real translations, this function will
/// resume the standard match-then-fallback logic.
Locale resolveLocale(Locale deviceLocale, Iterable<Locale> supported) {
  return const Locale('es', 'AR');
}
