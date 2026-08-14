import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';

/// A schematic drawing of the screen a slide is talking about.
///
/// Drawn with widgets and [AppPalette] rather than shipped as a screenshot, for
/// three reasons a static asset cannot satisfy at once:
///
///  - The app has BOTH a light and a dark theme (`ThemeMode.system` by
///    default, `theme_mode_provider.dart`). One asset is one theme and would be
///    wrong for half the users; this reads the palette and is right in both.
///  - It cannot drift silently. A screenshot goes stale invisibly; a schematic
///    that stops matching is a visible edit in this file.
///  - No third-party data. Real captures of COACH and FEED would bake trainer
///    names, prices and gym members into the binary.
///
/// It is deliberately abstract — blocks, not legible text. It says "this is the
/// shape of that screen, and this is the tab it lives in", which is all a slide
/// needs; fake copy inside a 200pt frame would only compete with the real
/// headline beside it.
///
/// Every layout below is checked against the running app: tab order comes from
/// `TreinoBottomBar._items` (ENTRENAR · FEED · INICIO · COACH · PERFIL — INICIO
/// is the middle tab, not the first), and each pill from that screen's
/// `_labels`.
class OnboardingIllustration extends StatelessWidget {
  const OnboardingIllustration._({
    required List<_BlockSpec> blocks,
    _PillSpec? pill,
    int? activeTab,
    int? activeSidebarItem,
  })  : _blocks = blocks,
        _pill = pill,
        _activeTab = activeTab,
        _activeSidebarItem = activeSidebarItem;

  // ---------------------------------------------------------------- athlete

  /// INICIO — the day summary: hero card, then the week and streak strips.
  const OnboardingIllustration.athleteHome()
      : this._(activeTab: 2, blocks: _summary);

  /// ENTRENAR — pill `[TU ENTRENO | PLANTILLAS]` (`workout_screen.dart:61`).
  const OnboardingIllustration.athleteWorkout()
      : this._(
          activeTab: 0,
          pill: const _PillSpec(2, 0),
          blocks: _cardThenList,
        );

  /// FEED — pill `[FEED | RANKINGS]` (`feed_screen.dart:74`), then posts.
  const OnboardingIllustration.athleteFeed()
      : this._(activeTab: 1, pill: const _PillSpec(2, 0), blocks: _posts);

  /// COACH — no sub-tabs for the athlete; a list of trainers.
  const OnboardingIllustration.athleteCoach()
      : this._(activeTab: 3, blocks: _people);

  /// PERFIL — identity card, then the settings groups.
  const OnboardingIllustration.athleteProfile()
      : this._(activeTab: 4, blocks: _identityThenRows);

  // ---------------------------------------------------------------- trainer

  /// INICIO — the trainer dashboard.
  const OnboardingIllustration.trainerHome()
      : this._(activeTab: 2, blocks: _summary);

  /// ENTRENAR — the template library. No sub-tabs (`trainer_workout_view.dart`).
  const OnboardingIllustration.trainerWorkout()
      : this._(activeTab: 0, blocks: _cardThenList);

  /// FEED — no RANKINGS tab for the trainer, so no pill.
  const OnboardingIllustration.trainerFeed()
      : this._(activeTab: 1, blocks: _posts);

  /// COACH — pill `[ALUMNOS | AGENDA]` (`trainer_coach_view.dart:26`).
  const OnboardingIllustration.trainerCoach()
      : this._(activeTab: 3, pill: const _PillSpec(2, 0), blocks: _people);

  /// PERFIL — public profile card, then availability and requests.
  const OnboardingIllustration.trainerProfile()
      : this._(activeTab: 4, blocks: _identityThenRows);

  // -------------------------------------------------------------- coach hub

  // Sidebar order comes from `sidebar_registry.dart` — the 8 items left after
  // the W2 reduce: Dashboard · Alumnos · Agenda · Chat · Biblioteca · Rutinas ·
  // Pagos · Ajustes.

  const OnboardingIllustration.webDashboard()
      : this._(activeSidebarItem: 0, blocks: _summary);

  const OnboardingIllustration.webAlumnos()
      : this._(activeSidebarItem: 1, blocks: _people);

  const OnboardingIllustration.webAgenda()
      : this._(activeSidebarItem: 2, blocks: _calendar);

  const OnboardingIllustration.webChat()
      : this._(activeSidebarItem: 3, blocks: _conversation);

  const OnboardingIllustration.webBiblioteca()
      : this._(activeSidebarItem: 4, blocks: _cardThenList);

  const OnboardingIllustration.webRutinas()
      : this._(activeSidebarItem: 5, blocks: _cardThenList);

  const OnboardingIllustration.webPagos()
      : this._(activeSidebarItem: 6, blocks: _people);

  const OnboardingIllustration.webAjustes()
      : this._(activeSidebarItem: 7, blocks: _rows);

  static const _summary = <_BlockSpec>[
    _BlockSpec(5, accent: true),
    _BlockSpec(3),
    _BlockSpec(3),
  ];

  static const _cardThenList = <_BlockSpec>[
    _BlockSpec(5, accent: true),
    _BlockSpec(2),
    _BlockSpec(2),
    _BlockSpec(2),
  ];

  static const _posts = <_BlockSpec>[
    _BlockSpec(5, avatar: true),
    _BlockSpec(5, avatar: true),
  ];

  static const _people = <_BlockSpec>[
    _BlockSpec(2, avatar: true),
    _BlockSpec(2, avatar: true),
    _BlockSpec(2, avatar: true),
    _BlockSpec(2, avatar: true),
  ];

  /// A week of columns rather than stacked cards — the agenda is the one
  /// section whose shape is not a list.
  static const _calendar = <_BlockSpec>[
    _BlockSpec(2),
    _BlockSpec(4, accent: true),
    _BlockSpec(2),
    _BlockSpec(3),
  ];

  static const _conversation = <_BlockSpec>[
    _BlockSpec(2, avatar: true),
    _BlockSpec(2, avatar: true),
    _BlockSpec(3, accent: true),
  ];

  static const _rows = <_BlockSpec>[
    _BlockSpec(2),
    _BlockSpec(2),
    _BlockSpec(2),
    _BlockSpec(2),
    _BlockSpec(2),
  ];

  static const _identityThenRows = <_BlockSpec>[
    _BlockSpec(4, accent: true, avatar: true),
    _BlockSpec(2),
    _BlockSpec(2),
    _BlockSpec(2),
    _BlockSpec(2),
  ];

  /// Design canvas the body is drawn against. Every hardcoded dimension below
  /// is in these units, and the outer `AspectRatio` derives its ratio from
  /// these same numbers — so the FittedBox always fills the frame edge to edge
  /// and can never letterbox it.
  static const _mobileCanvas = Size(180, 310); // 180/310 == 9/15.5
  static const _webCanvas = Size(320, 200); // 320/200 == 16/10

  final List<_BlockSpec> _blocks;
  final _PillSpec? _pill;
  final int? _activeTab;
  final int? _activeSidebarItem;

  bool get _isWeb => _activeSidebarItem != null;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final radius = BorderRadius.circular(_isWeb ? 14 : 26);

    return Center(
      child: AspectRatio(
        // Portrait phone vs landscape desktop — the silhouette alone tells the
        // user which surface the slide is about.
        aspectRatio: _isWeb
            ? _webCanvas.width / _webCanvas.height
            : _mobileCanvas.width / _mobileCanvas.height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            // The same accent halo the hero cards and pill CTAs use.
            boxShadow: [
              BoxShadow(
                color: palette.accent.withValues(alpha: 0.18),
                blurRadius: 32,
                spreadRadius: -6,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: palette.bgCard,
              border: Border.all(color: palette.border, width: 1.5),
              borderRadius: radius,
            ),
            // Everything inside is laid out against a fixed design canvas and
            // then scaled to whatever room the slide has. One guard instead of
            // N: without it, each fixed dimension in here is its own overflow
            // waiting for a small screen — a 320x568 at 2x text scale shrinks
            // this frame until a 12pt avatar row no longer fits its block.
            //
            // The frame itself (border, radius, shadow) stays outside the
            // FittedBox so it renders at true scale and never goes blurry.
            child: FittedBox(
              child: SizedBox(
                width: _isWeb ? _webCanvas.width : _mobileCanvas.width,
                height: _isWeb ? _webCanvas.height : _mobileCanvas.height,
                child: _isWeb ? _WebBody(this) : _MobileBody(this),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One content block: a rounded rectangle standing in for a card or a row.
class _BlockSpec {
  const _BlockSpec(this.flex, {this.accent = false, this.avatar = false});

  /// Relative height inside the content area.
  final int flex;

  /// Filled in accent — the one element the slide is pointing at.
  final bool accent;

  /// Draws a leading circle, for rows that stand for a person.
  final bool avatar;
}

class _PillSpec {
  const _PillSpec(this.segments, this.activeIndex);

  final int segments;
  final int activeIndex;
}

class _MobileBody extends StatelessWidget {
  const _MobileBody(this.spec);

  final OnboardingIllustration spec;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Dynamic island — the cue that makes the frame read as a phone
          // instantly, before any of the content is parsed.
          Center(
            child: Container(
              width: 34,
              height: 5,
              decoration: BoxDecoration(
                color: palette.textMuted.withValues(alpha: 0.30),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 9),
          if (spec._pill case final pill?) ...[
            _Pill(pill: pill),
            const SizedBox(height: 7),
          ],
          Expanded(child: _Blocks(blocks: spec._blocks)),
          const SizedBox(height: 8),
          _BottomBar(activeTab: spec._activeTab!, palette: palette),
        ],
      ),
    );
  }
}

class _WebBody extends StatelessWidget {
  const _WebBody(this.spec);

  final OnboardingIllustration spec;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 44,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 9),
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: palette.border)),
            ),
            child: Column(
              children: [
                for (var i = 0; i < 8; i++) ...[
                  _Line(
                    height: 5,
                    accent: i == spec._activeSidebarItem,
                    palette: palette,
                    // The active row reads as selected by being full-width and
                    // accent, the way the real sidebar marks it.
                    widthFactor: i == spec._activeSidebarItem ? 1 : 0.72,
                  ),
                  if (i != 7) const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Line(height: 7, palette: palette, widthFactor: 0.42),
                const SizedBox(height: 9),
                Expanded(child: _Blocks(blocks: spec._blocks)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Blocks extends StatelessWidget {
  const _Blocks({required this.blocks});

  final List<_BlockSpec> blocks;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Column(
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          Expanded(
            flex: blocks[i].flex,
            child: _Block(spec: blocks[i], palette: palette),
          ),
          if (i != blocks.length - 1) const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.spec, required this.palette});

  final _BlockSpec spec;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: spec.accent
            ? palette.accent.withValues(alpha: 0.80)
            : palette.textMuted.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(7),
      ),
      child: spec.avatar
          ? Row(
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: spec.accent
                          ? palette.bgCard.withValues(alpha: 0.55)
                          : palette.textMuted.withValues(alpha: 0.30),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Line(
                        height: 4,
                        palette: palette,
                        widthFactor: 0.55,
                        onAccent: spec.accent,
                      ),
                      const SizedBox(height: 4),
                      _Line(
                        height: 4,
                        palette: palette,
                        widthFactor: 0.34,
                        onAccent: spec.accent,
                      ),
                    ],
                  ),
                ),
              ],
            )
          : null,
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.pill});

  final _PillSpec pill;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Container(
      height: 15,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: palette.textMuted.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          for (var i = 0; i < pill.segments; i++)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: i == pill.activeIndex
                      ? palette.accent
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The five tabs, in the real order: ENTRENAR · FEED · INICIO · COACH · PERFIL.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.activeTab, required this.palette});

  final int activeTab;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: palette.textMuted.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var i = 0; i < 5; i++)
            Container(
              width: i == activeTab ? 13 : 8,
              height: i == activeTab ? 13 : 8,
              decoration: BoxDecoration(
                color: i == activeTab
                    ? palette.accent
                    : palette.textMuted.withValues(alpha: 0.32),
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.height,
    required this.palette,
    this.accent = false,
    this.onAccent = false,
    this.widthFactor = 1,
  });

  final double height;
  final AppPalette palette;
  final bool accent;

  /// Sitting on top of an accent-filled block, so it must invert.
  final bool onAccent;
  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    final Color color;
    if (accent) {
      color = palette.accent;
    } else if (onAccent) {
      color = palette.bgCard.withValues(alpha: 0.55);
    } else {
      color = palette.textMuted.withValues(alpha: 0.22);
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: widthFactor,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}
