import 'package:flutter/widgets.dart';

/// What a module's card says.
///
/// A plain immutable class, deliberately NOT freezed: it is never serialized,
/// never diffed, never copied — a generated `.freezed.dart`/`.g.dart` pair for
/// four fields would be pure ceremony.
///
/// Lives in `presentation/` rather than `domain/` because it carries an
/// [IconData]. Keeping Flutter types out of `domain/` is what lets the
/// versioning logic be tested without a widget tree.
@immutable
class OnboardingCardContent {
  const OnboardingCardContent({
    required this.icon,
    required this.title,
    required this.body,
    required this.illustration,
    this.bullets = const <String>[],
  });

  /// Always a `TreinoIcon.*` constant — never a raw Phosphor icon
  /// (docs/design-system.md, rule 2).
  final IconData icon;

  /// Barlow Condensed 700 UPPERCASE. Keep it to ~4 words: this is a card sitting
  /// on top of real content, not a landing page.
  final String title;

  /// Barlow 400. One sentence. If it needs two, the second one is a bullet.
  final String body;

  /// Concrete specifics, one accent-dotted line each. Three at most.
  ///
  /// Detail goes here rather than into a longer [body]: a skimming reader still
  /// picks up a dotted list, and the card stays short enough that it does not
  /// bury the screen it is explaining.
  final List<String> bullets;

  /// The schematic of the screen this slide describes — an
  /// `OnboardingIllustration.*` constant. Required, not optional: a slide
  /// without one is a slide the reader cannot place, and leaving the field
  /// nullable is how half the tour ends up shipping without art.
  final Widget illustration;
}
