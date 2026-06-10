import 'package:flutter/material.dart';

/// Resolves the device locale to a supported app locale.
/// Per ADR-I18N-005: any unsupported locale falls back to es-AR.
///
/// This is a pure function extracted from [MaterialApp.localeResolutionCallback]
/// so it can be unit-tested without a widget tree.
Locale resolveLocale(Locale deviceLocale, Iterable<Locale> supported) {
  // Exact match first (language + country).
  for (final locale in supported) {
    if (locale.languageCode == deviceLocale.languageCode &&
        locale.countryCode == deviceLocale.countryCode) {
      return locale;
    }
  }

  // Language-only match.
  for (final locale in supported) {
    if (locale.languageCode == deviceLocale.languageCode &&
        locale.countryCode == null) {
      return locale;
    }
  }

  // Fallback: force es-AR per ADR-I18N-005.
  return const Locale('es', 'AR');
}
