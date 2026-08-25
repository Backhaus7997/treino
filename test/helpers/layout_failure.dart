import 'package:flutter_test/flutter_test.dart';

/// Drains the pending exceptions and returns the first REAL failure, or null
/// when everything left is known environmental noise.
///
/// ── The allowlist, and why it points this way ───────────────────────────────
/// This started out as a blocklist — fail on "unbounded height", on "was not
/// laid out", on overflow from our own code — and that let a genuine bug reach
/// a device: `LinkStateCard` reads `miCuotaProvider`, which derives from a
/// provider the preview overrides, and Riverpod threw an assertion that painted
/// a red box across the middle of the Coach slide. The suite stayed green,
/// because the message contained none of the blocked words.
///
/// So the polarity is inverted: EVERYTHING fails except the one artifact that
/// provably cannot be fixed from inside the code under test.
///
/// That artifact is font metrics. Google Fonts cannot download during a test
/// run, so Barlow falls back to a substitute with wider glyphs, and shipped
/// widgets that fit a 393pt phone on a real device — `HomeCtaButton`,
/// `EstaSemanaCard` — report a few dozen pixels of HORIZONTAL overflow. It is a
/// property of the harness, it originates outside [ownCode], and no change to
/// the widget under test removes it.
String? drainLayoutFailure(
  WidgetTester tester, {
  /// Path fragment identifying the code under test. Overflow reported from
  /// inside it is a real defect; horizontal overflow from elsewhere is the
  /// font artifact.
  String ownCode = 'features/onboarding/',
}) {
  final messages = <String>[];
  for (Object? e = tester.takeException();
      e != null;
      e = tester.takeException()) {
    messages.add(e.toString());
  }

  for (final m in messages) {
    if (_isHarnessSummary(m)) continue;
    if (_isForeignFontOverflow(m, ownCode)) continue;
    return m;
  }
  return null;
}

/// Flutter emits "Multiple exceptions (N) were detected…" as a SUMMARY of the
/// exception stream, not as a failure of its own. Every exception it counts is
/// already in [messages] and judged individually, so treating the summary as a
/// finding would report a failure with no cause attached.
bool _isHarnessSummary(String message) =>
    message.contains('Multiple exceptions') &&
    message.contains('were detected during the running of the current test');

bool _isForeignFontOverflow(String message, String ownCode) {
  final isHorizontalOverflow =
      message.contains('overflowed') && message.contains('on the right');
  if (!isHorizontalOverflow) return false;
  // Overflow inside the code under test is ours to fix, font or not.
  return !message.contains(ownCode);
}
