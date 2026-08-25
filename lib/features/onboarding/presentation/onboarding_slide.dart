import 'package:flutter/widgets.dart';

/// What one slide of the athlete tour shows.
///
/// [preview] is a real app screen built at full phone width —
/// `OnboardingDevicePreview` handles the shrinking. Keeping the screen and the
/// frame apart is what lets the previews be swapped or tested on their own.
@immutable
class OnboardingSlide {
  const OnboardingSlide({
    required this.icon,
    required this.title,
    required this.body,
    required this.preview,
  });

  /// Always a `TreinoIcon.*` constant — never a raw Phosphor icon
  /// (docs/design-system.md, rule 2).
  final IconData icon;

  /// Barlow Condensed 700, UPPERCASE.
  final String title;

  /// Barlow 400, one or two sentences.
  final String body;

  /// The screen this slide is about, built as if it had the full phone width.
  final Widget preview;
}
