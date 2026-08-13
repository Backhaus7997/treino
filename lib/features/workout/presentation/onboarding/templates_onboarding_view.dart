import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/motion/treino_tappable.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../onboarding/presentation/onboarding_chrome.dart';
import '../../domain/routine_goal.dart';
import '../../domain/template_preferences.dart';
import 'templates_onboarding_steps.dart';

/// Finder keys used by the widget tests.
const templatesOnboardingSkipKey = Key('templates_onboarding_skip_button');
const templatesOnboardingCtaKey = Key('templates_onboarding_primary_cta');
const templatesOnboardingBackKey = Key('templates_onboarding_back_button');
Key templatesOnboardingOptionKey(String dimension, String value) =>
    Key('templates_onboarding_option_${dimension}_$value');

/// The PLANTILLAS mini-onboarding (#635 PR#2), as a widget.
///
/// Purely presentational: no Riverpod, no repository, no navigation. It collects
/// four answers and hands back a [TemplatePreferences] — the same
/// no-provider-overrides testability contract as
/// [CustomExerciseOnboardingView].
///
/// ── Why this is not a `PageView` like its sibling ───────────────────────────
/// The custom-exercise onboarding pages through slides of roughly equal height,
/// so a computed fixed height works. Here each step has a different number of
/// pills — five one-line days, four with a second line, six zones — and a
/// PageView would have to be sized for the tallest, leaving dead space under
/// the short ones. The sheet is supposed to hug its content (commit 2221b6a0),
/// so the steps swap in place inside an [AnimatedSize] instead.
///
/// Steps ARE draggable, though — the content follows the finger horizontally
/// and settles on release, the same two moves VOLVER and SIGUIENTE make. A
/// gesture that only reacted to a fast flick would leave a deliberate slow drag
/// doing nothing, which reads as a broken screen rather than as a threshold.
///
/// What a gesture must never do is COMMIT: dragging left on the last step
/// rubber-bands and returns, because the CTA there writes four answers to the
/// user's document. The sheet's own vertical drag-to-dismiss stays off for the
/// same reason — that one closed the whole flow and discarded the answers.
class TemplatesOnboardingView extends StatefulWidget {
  const TemplatesOnboardingView({
    super.key,
    required this.steps,
    required this.onFinish,
    required this.onSkip,
    required this.skipLabel,
    required this.nextLabel,
    required this.finishLabel,
    required this.backLabel,
    required this.stepSemanticsLabel,
  });

  final List<TemplatesOnboardingStep> steps;

  /// Last step's CTA. The caller persists and closes.
  final void Function(TemplatePreferences preferences) onFinish;

  /// SALTAR. Terminal and equivalent to the CTA as far as "has this user seen
  /// it" goes — but it persists NO preferences. A tour nobody can leave is a
  /// toll, not a welcome (#429).
  final VoidCallback onSkip;

  final String skipLabel;
  final String nextLabel;
  final String finishLabel;

  /// VOLVER — hidden on step 1, where there is nothing to go back to.
  final String backLabel;

  /// Already-interpolated "Paso 2 de 4".
  final String Function(int current, int total) stepSemanticsLabel;

  @override
  State<TemplatesOnboardingView> createState() =>
      _TemplatesOnboardingViewState();
}

class _TemplatesOnboardingViewState extends State<TemplatesOnboardingView> {
  /// How much of the finger's travel the content actually mirrors.
  ///
  /// Not 1:1. Following the finger exactly is what dragged the question far
  /// enough to expose the empty sheet behind it — the "queda blanco" report.
  /// A third of the distance still reads as "the screen heard me" without ever
  /// opening a gap.
  static const _dragFollowFactor = 0.35;

  /// Hard cap on that travel, as a fraction of the content width.
  static const _maxTravel = 0.10;

  int _index = 0;

  /// Answers so far, keyed by dimension. A `Set` even for single-choice steps
  /// so one selection path covers both; single-choice replaces, multi toggles.
  final _answers = <TemplatesOnboardingDimension, Set<String>>{};

  bool get _isLast => _index == widget.steps.length - 1;

  TemplatesOnboardingStep get _step => widget.steps[_index];

  void _toggle(TemplatesOnboardingStep step, String value) {
    setState(() {
      final current = _answers[step.dimension] ?? <String>{};
      if (step.multiSelect) {
        _answers[step.dimension] = current.contains(value)
            ? (current..remove(value))
            : (current..add(value));
      } else {
        // Tapping the chosen pill again clears it. Without this the first tap
        // is irreversible and "I'd rather not say" becomes unreachable once
        // touched — and every dimension here is legitimately optional.
        _answers[step.dimension] =
            current.contains(value) ? <String>{} : <String>{value};
      }
    });
  }

  /// True while the outgoing step is fading out, before the swap.
  bool _swapping = false;

  /// Half of the step transition. Out, swap, in.
  static const _fadeHalf = AppMotion.fast;

  /// Moves to [next] as a FADE-THROUGH, never a cross-fade.
  ///
  /// A cross-fade stacks both steps for the duration, so the box takes the
  /// height of the TALLER one: going from the four full-width durations back to
  /// the shorter day pills left the old rows ghosting over a tall empty gap
  /// that only collapsed once the fade ended. Steps here differ too much in
  /// height for the two of them to ever share the frame.
  ///
  /// So: fade the current step out, swap it while nothing is on screen, fade
  /// the new one in. [AnimatedSize] moves the height during the gap, when there
  /// is no content to misalign.
  void _goTo(int next) {
    if (next == _index || _swapping) return;
    setState(() => _swapping = true);
    Future.delayed(AppMotion.resolve(context, _fadeHalf), () {
      if (!mounted) return;
      setState(() {
        _index = next;
        _swapping = false;
      });
    });
  }

  void _onPrimary() {
    if (_isLast) {
      widget.onFinish(_preferences());
      return;
    }
    _goTo(_index + 1);
  }

  /// Steps back one question.
  ///
  /// Answers live in `_answers`, keyed by dimension and never cleared on
  /// navigation, so going back and forward again preserves every choice. That
  /// is the whole point: a back button that discarded what you already picked
  /// would be worse than not having one.
  void _onBack() {
    if (_index == 0) return;
    _goTo(_index - 1);
  }

  /// How far the finger has carried the content, in logical pixels.
  ///
  /// Non-zero only while a drag is in flight. The content is translated by this
  /// so the step FOLLOWS the finger instead of waiting for a flick — a gesture
  /// you cannot see responding reads as a broken screen, not as a threshold.
  double _dragDx = 0;
  bool _dragging = false;

  /// Width of the CONTENT, captured by the `LayoutBuilder` in [build].
  ///
  /// Not `MediaQuery.sizeOf(context).width`. That is the SCREEN, and the sheet
  /// is not the screen: on a wide viewport the screen-derived threshold grows
  /// past anything a thumb can travel, so the drag silently stops committing —
  /// which is exactly how this shipped broken the first time.
  double _contentWidth = 1;

  /// Steps the drag is allowed to reach.
  ///
  /// Pulling right on step 1 or left on the last one rubber-bands to a third of
  /// the distance instead of moving freely: the resistance IS the message that
  /// there is nothing over there. Left on the last step is capped because a
  /// gesture must never be what commits — the CTA writes, swiping only walks.
  bool get _canGoNext => !_isLast;

  bool get _canGoPrev => _index > 0;

  void _onDragStart(DragStartDetails _) {
    setState(() => _dragging = true);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      final next = _dragDx + details.delta.dx;
      final blocked = (next < 0 && !_canGoNext) || (next > 0 && !_canGoPrev);
      _dragDx = blocked ? next / 3 : next;
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    // Either intention counts: a short, fast flick and a slow, long haul are
    // both unambiguous. Requiring velocity alone is what made a deliberate slow
    // drag do nothing at all.
    final committedByDistance = _dragDx.abs() > _contentWidth * 0.25;
    final committedByVelocity = velocity.abs() > 400;
    final goingBack = _dragDx > 0;

    setState(() {
      _dragging = false;
      _dragDx = 0;
    });

    if (!committedByDistance && !committedByVelocity) return;
    if (goingBack && _canGoPrev) {
      _goTo(_index - 1);
    } else if (!goingBack && _canGoNext) {
      _goTo(_index + 1);
    }
  }

  /// Folds the answers into the persisted shape.
  ///
  /// Anything unanswered stays null / empty rather than being defaulted: the
  /// issue is explicit that a missing answer must rank NEUTRAL, and a default
  /// would be indistinguishable from a real choice the moment it is read back.
  TemplatePreferences _preferences() {
    int? intAnswer(TemplatesOnboardingDimension d) {
      final raw = _answers[d]?.firstOrNull;
      return raw == null ? null : int.tryParse(raw);
    }

    return TemplatePreferences(
      daysPerWeek: intAnswer(TemplatesOnboardingDimension.days),
      minutesPerSession: intAnswer(TemplatesOnboardingDimension.minutes),
      goal: RoutineGoal.fromWireKey(
        _answers[TemplatesOnboardingDimension.goal]?.firstOrNull,
      ),
      priorityMuscleGroups:
          (_answers[TemplatesOnboardingDimension.zones] ?? <String>{})
              .toList(growable: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.steps.length;
    final step = _step;
    final selected = _answers[step.dimension] ?? const <String>{};

    return MediaQuery(
      // Clamp OS text scaling: the actions row is fixed while the card grows,
      // so an extreme accessibility setting would push the CTA off the sheet.
      // Same guard as CustomExerciseOnboardingView and ProfileSetupFlow.
      data: MediaQuery.of(context).copyWith(
        textScaler: MediaQuery.textScalerOf(context).clamp(
          minScaleFactor: 1.0,
          maxScaleFactor: 1.3,
        ),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        // Captured for the drag maths: both the settle threshold and the slide
        // fraction are relative to the CONTENT, never to the screen.
        _contentWidth = constraints.maxWidth > 0 ? constraints.maxWidth : 1;

        return GestureDetector(
          // Only the horizontal axis is claimed, so the sheet's vertical scroll
          // and every pill tap keep working — a drag that moves vertically
          // never enters this recognizer's arena.
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          // The gaps between the card, the copy and the dots must catch the
          // gesture too, not just the painted pixels.
          behavior: HitTestBehavior.opaque,
          child: AnimatedSize(
            duration: AppMotion.resolve(context, AppMotion.slow),
            curve: AppMotion.standard,
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(child: OnboardingGrabber()),
                // ONLY the question travels. The grabber, the dots and the
                // actions are a fixed frame it moves inside.
                //
                // Sliding the whole column was the "queda blanco" bug: the
                // entire sheet body translated out and the empty background
                // showed where it used to be, then the next step flew in from
                // off-screen across the same gap.
                _SlidingStep(
                  // Damped and capped: the content acknowledges the finger
                  // without travelling far enough to expose the sheet behind
                  // it. Following 1:1 is what opened the white band.
                  offsetX: (_dragDx * _dragFollowFactor).clamp(
                      -_contentWidth * _maxTravel, _contentWidth * _maxTravel),
                  width: _contentWidth,
                  // Zero WHILE dragging so it sits under the finger frame for
                  // frame. On release it settles; on a committed step change it
                  // snaps to centre instantly and the CROSS-FADE carries the
                  // change instead — a slide would re-open the same gap.
                  duration: _dragging
                      ? Duration.zero
                      : AppMotion.resolve(context, AppMotion.slow),
                  // 0 while the outgoing step clears the frame, 1 once the new
                  // one is in place. See [_goTo].
                  opacity: _swapping ? 0 : 1,
                  fadeDuration: AppMotion.resolve(context, _fadeHalf),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _InsetCard(
                        step: step,
                        selected: selected,
                        onToggle: (value) => _toggle(step, value),
                      ),
                      const SizedBox(height: 14),
                      OnboardingKicker(
                          widget.stepSemanticsLabel(_index + 1, total)),
                      const SizedBox(height: 8),
                      // UPPERCASE here, not in the ARB: the handoff sets
                      // `text-transform:uppercase` on the headline, and keeping
                      // the source string sentence case is what lets a
                      // translator read it.
                      OnboardingTitle(step.title.toUpperCase()),
                      const SizedBox(height: 8),
                      OnboardingBody(step.body),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // VOLVER rides with the DOTS, not with SALTAR and the CTA.
                //
                // Three controls in the actions row leaves the pill about 158pt on
                // a 390pt screen, and "VER MIS PLANTILLAS" needs ~190 — the button
                // that closes the flow would ship ellipsised. Here the CTA keeps
                // its full width, and "go back a step" sits next to the step
                // indicator it moves.
                Row(
                  children: [
                    if (_index > 0) ...[
                      _BackButton(label: widget.backLabel, onTap: _onBack),
                      const SizedBox(width: 12),
                    ],
                    OnboardingDots(
                      current: _index,
                      total: total,
                      semanticsLabel:
                          widget.stepSemanticsLabel(_index + 1, total),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                OnboardingActions(
                  skipKey: templatesOnboardingSkipKey,
                  primaryKey: templatesOnboardingCtaKey,
                  // SALTAR stays available on the LAST step too, unlike the
                  // slide decks. There the final CTA only closes; here it WRITES
                  // four answers, so "show me the grid without saving this" has to
                  // remain reachable at the moment the user can finally see what
                  // they are about to save.
                  showSkip: true,
                  skipLabel: widget.skipLabel,
                  primaryLabel: _isLast ? widget.finishLabel : widget.nextLabel,
                  onSkip: widget.onSkip,
                  onPrimary: _onPrimary,
                  ctaHeight: 48,
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// The one part of the sheet that moves: the question.
///
/// Two motions, and they are deliberately NOT the same one:
///
///  - While a finger is down, [offsetX] nudges the block sideways so the drag
///    is visibly acknowledged. Damped and capped by the caller, because a 1:1
///    follow slid the content off its own background.
///  - When the step actually changes, the block does NOT fly in from off-screen.
///    It fades THROUGH: out, swap, in, driven by [opacity] from the caller. A
///    slide-in has to cross the same empty band that caused the white flash,
///    and at the slower duration asked for it would be on screen twice as long.
///
/// No `AnimatedSwitcher`. That stacks the outgoing and incoming steps for the
/// whole transition, so the box takes the height of the TALLER one — going from
/// the four duration rows back to the day pills left the old rows ghosting over
/// a tall empty gap. One child at a time is the only thing that survives steps
/// this different in height.
class _SlidingStep extends StatelessWidget {
  const _SlidingStep({
    required this.offsetX,
    required this.width,
    required this.duration,
    required this.opacity,
    required this.fadeDuration,
    required this.child,
  });

  final double offsetX;
  final double width;
  final Duration duration;
  final double opacity;
  final Duration fadeDuration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      duration: duration,
      curve: AppMotion.standard,
      offset: Offset(width > 0 ? offsetX / width : 0, 0),
      child: AnimatedOpacity(
        opacity: opacity,
        duration: fadeDuration,
        curve: AppMotion.standard,
        child: child,
      ),
    );
  }
}

/// VOLVER — a chevron plus its label, sized like every other secondary control.
///
/// A `TextButton` rather than a bare `TreinoTappable`: this is a low-emphasis
/// text action, exactly what SALTAR already is, and matching it keeps the two
/// reading as the same weight next to the one filled CTA.
class _BackButton extends StatelessWidget {
  const _BackButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return TextButton(
      key: templatesOnboardingBackKey,
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        // 44pt minimum touch target (a11y, #619).
        minimumSize: const Size(44, 44),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: palette.textMuted,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(TreinoIcon.chevronLeft, size: 14, color: palette.textMuted),
          const SizedBox(width: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.barlowCondensed(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// The sunken card that holds the question's controls.
class _InsetCard extends StatelessWidget {
  // No `key`: the step identity now lives on the `_SlidingStep` above, which is
  // what drives the cross-fade. A second key here would only re-create the card
  // a frame out of step with it.
  const _InsetCard({
    required this.step,
    required this.selected,
    required this.onToggle,
  });

  final TemplatesOnboardingStep step;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // Derived from a semantic token instead of a light/dark literal pair:
        // 5% of the text colour over the sheet lands on the handoff's #F2F2F0
        // in light and #1D2422 in dark, and follows any future palette change
        // for free.
        color: palette.textPrimary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            step.cardLabel,
            style: GoogleFonts.barlow(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              height: 1.3,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          if (step.layout == TemplatesOnboardingOptionLayout.wrap)
            Wrap(
              spacing: 9,
              runSpacing: 9,
              children: [
                for (final option in step.options)
                  _OptionPill(
                    key: templatesOnboardingOptionKey(
                      step.dimension.name,
                      option.value,
                    ),
                    option: option,
                    isSelected: selected.contains(option.value),
                    isMulti: step.multiSelect,
                    onTap: () => onToggle(option.value),
                  ),
              ],
            )
          else
            Column(
              children: [
                for (final option in step.options) ...[
                  if (option != step.options.first) const SizedBox(height: 8),
                  _OptionRow(
                    key: templatesOnboardingOptionKey(
                      step.dimension.name,
                      option.value,
                    ),
                    option: option,
                    isSelected: selected.contains(option.value),
                    onTap: () => onToggle(option.value),
                  ),
                ],
              ],
            ),
          if (step.hint != null) ...[
            const SizedBox(height: 12),
            Text(
              step.hint!,
              style: GoogleFonts.barlow(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                height: 1.45,
                color: palette.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A content-sized pill that wraps with its siblings.
///
/// ⚠️ No `alignment:` on the container. `Container.alignment` makes the box
/// expand to fill the constraints it is handed, and inside a `Wrap` that is the
/// full row width — which is exactly how five day pills ended up stacked one
/// per line instead of wrapping. Centring happens on the text itself.
class _OptionPill extends StatelessWidget {
  const _OptionPill({
    super.key,
    required this.option,
    required this.isSelected,
    required this.isMulti,
    required this.onTap,
  });

  final TemplatesOnboardingOption option;
  final bool isSelected;
  final bool isMulti;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    // Compact while unselected, full once chosen — see
    // `TemplatesOnboardingOption.shortLabel`. Semantics always gets the full
    // label, so the unit is never lost to a screen reader.
    final text =
        isSelected ? option.label : (option.shortLabel ?? option.label);

    return Semantics(
      // `inMutuallyExclusiveGroup` for single choice, `checked` for the
      // multi-select step: a radio and a checkbox are announced differently,
      // and step 4 genuinely is a checkbox group.
      button: true,
      selected: isSelected,
      checked: isMulti ? isSelected : null,
      inMutuallyExclusiveGroup: isMulti ? null : true,
      label: option.label,
      excludeSemantics: true,
      child: TreinoTappable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.resolve(context, AppMotion.fast),
          curve: AppMotion.standard,
          // 44pt minimum touch target (a11y, #619).
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? palette.accent
                : palette.textPrimary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(9999),
          ),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Text(
              text,
              style: GoogleFonts.barlowCondensed(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                height: 1.1,
                color: isSelected ? AppColors.ink : palette.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A full-width row: label left, sub-label right.
///
/// Selected reads as an accent BORDER over the sheet colour, not a fill — the
/// handoff draws it outlined, and a full-width accent block would carry more
/// visual weight than "45 minutes" deserves next to the actual CTA.
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    super.key,
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  final TemplatesOnboardingOption option;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Semantics(
      button: true,
      selected: isSelected,
      inMutuallyExclusiveGroup: true,
      label: option.subLabel == null
          ? option.label
          : '${option.label}, ${option.subLabel}',
      excludeSemantics: true,
      child: TreinoTappable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.resolve(context, AppMotion.fast),
          curve: AppMotion.standard,
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: palette.bgCard,
            borderRadius: BorderRadius.circular(9999),
            border: Border.all(
              color: isSelected ? palette.accent : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  option.label,
                  style: GoogleFonts.barlowCondensed(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    height: 1.1,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              if (option.subLabel != null) ...[
                const SizedBox(width: 12),
                Text(
                  option.subLabel!,
                  style: GoogleFonts.barlow(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    height: 1.3,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
