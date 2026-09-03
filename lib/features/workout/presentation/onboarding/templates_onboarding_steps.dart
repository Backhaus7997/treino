import 'package:flutter/foundation.dart';

import '../../../../l10n/app_l10n.dart';
import '../../domain/muscle_group.dart';
import '../../domain/routine_goal.dart';

/// Which answer a step collects.
enum TemplatesOnboardingDimension { days, minutes, goal, zones }

/// How a step lays its options out.
///
/// Two layouts, because the handoff draws two. They are not a responsive
/// choice — each step uses the one its content needs.
enum TemplatesOnboardingOptionLayout {
  /// Content-sized pills that wrap onto as many rows as they need. Used when
  /// the label is short (`3 DÍAS`, `ESTÉTICA`, `ESPALDA`) and fitting several
  /// per row is what makes the set readable at a glance.
  ///
  /// Selected state is a FILLED accent pill.
  wrap,

  /// Full-width rows, label left and sub-label right. Used by the durations,
  /// where every option carries a second phrase ("45 MIN" / "Lo de siempre")
  /// that has nowhere to go on a hugging pill.
  ///
  /// Selected state is an accent BORDER, not a fill: a full-width block of
  /// accent would shout louder than the answer deserves, and the handoff draws
  /// it outlined.
  rows,
}

/// One selectable pill.
@immutable
class TemplatesOnboardingOption {
  const TemplatesOnboardingOption({
    required this.value,
    required this.label,
    this.shortLabel,
    this.subLabel,
  });

  /// Wire value. Ints arrive here as their decimal string so one option type
  /// covers all four dimensions; the step's [TemplatesOnboardingDimension]
  /// says how to parse it back.
  final String value;

  /// Full label, always what a screen reader announces.
  final String label;

  /// Compact label drawn only while UNSELECTED.
  ///
  /// The handoff draws the days row as `2 · 3 DÍAS · 4 · 5 · 6` — the unit is
  /// spelled out on the chosen pill and dropped on the rest, which is how five
  /// pills fit one row. Purely visual: [label] is what Semantics announces
  /// either way, so the unit never disappears for a screen reader.
  final String? shortLabel;

  /// Second line inside the pill ("30 MIN" / "Entro y salgo").
  final String? subLabel;
}

/// One question.
@immutable
class TemplatesOnboardingStep {
  const TemplatesOnboardingStep({
    required this.dimension,
    required this.cardLabel,
    required this.title,
    required this.body,
    required this.options,
    this.hint,
    this.multiSelect = false,
    this.layout = TemplatesOnboardingOptionLayout.wrap,
  });

  final TemplatesOnboardingDimension dimension;

  /// Small header inside the inset card ("Días por semana").
  final String cardLabel;

  /// Headline. Rendered UPPERCASE by the view (`text-transform:uppercase` in
  /// the handoff) — kept sentence case here so the ARB entry stays readable and
  /// translatable.
  final String title;

  final String body;

  /// Optional footnote inside the card. Only step 1 has one.
  final String? hint;

  final List<TemplatesOnboardingOption> options;

  /// Step 4 only. Everything else is single-choice.
  final bool multiSelect;

  final TemplatesOnboardingOptionLayout layout;
}

/// The zones offered in step 4, in the handoff's order.
///
/// SIX of the twelve [MuscleGroup] values, not all of them: the handoff draws
/// exactly these, and twelve pills would push the sheet past the 90%-height cap
/// the presentation already lives under. They are still canonical `MuscleGroup`
/// keys — the point of reusing the taxonomy is the vocabulary, not the arity.
const templatesOnboardingZones = <MuscleGroup>[
  MuscleGroup.espalda,
  MuscleGroup.pecho,
  MuscleGroup.hombros,
  MuscleGroup.gluteos,
  MuscleGroup.cuadriceps,
  MuscleGroup.abdominales,
];

/// The four questions, built from the current locale.
///
/// Copy is verbatim from "Onboarding Plantillas.dc.html". It lives in
/// `lib/l10n` rather than hardcoded with `// i18n` markers (the convention the
/// older decks use) because this flow ships with both locales.
List<TemplatesOnboardingStep> templatesOnboardingSteps(AppL10n l10n) {
  return <TemplatesOnboardingStep>[
    TemplatesOnboardingStep(
      dimension: TemplatesOnboardingDimension.days,
      cardLabel: l10n.templatesOnboardingStep1Label,
      title: l10n.templatesOnboardingStep1Title,
      body: l10n.templatesOnboardingStep1Body,
      hint: l10n.templatesOnboardingStep1Hint,
      options: [
        for (var d = 2; d <= 6; d++)
          TemplatesOnboardingOption(
            value: '$d',
            label: l10n.templatesOnboardingDaysOption(d),
            shortLabel: '$d',
          ),
      ],
    ),
    TemplatesOnboardingStep(
      dimension: TemplatesOnboardingDimension.minutes,
      cardLabel: l10n.templatesOnboardingStep2Label,
      title: l10n.templatesOnboardingStep2Title,
      body: l10n.templatesOnboardingStep2Body,
      layout: TemplatesOnboardingOptionLayout.rows,
      options: [
        TemplatesOnboardingOption(
          value: '30',
          label: l10n.templatesOnboardingMinutes30,
          subLabel: l10n.templatesOnboardingMinutes30Hint,
        ),
        TemplatesOnboardingOption(
          value: '45',
          label: l10n.templatesOnboardingMinutes45,
          subLabel: l10n.templatesOnboardingMinutes45Hint,
        ),
        TemplatesOnboardingOption(
          value: '60',
          label: l10n.templatesOnboardingMinutes60,
          subLabel: l10n.templatesOnboardingMinutes60Hint,
        ),
        // Stored as 75 — the lower bound of "75 o más".
        TemplatesOnboardingOption(
          value: '75',
          label: l10n.templatesOnboardingMinutes75,
          subLabel: l10n.templatesOnboardingMinutes75Hint,
        ),
      ],
    ),
    TemplatesOnboardingStep(
      dimension: TemplatesOnboardingDimension.goal,
      cardLabel: l10n.templatesOnboardingStep3Label,
      title: l10n.templatesOnboardingStep3Title,
      body: l10n.templatesOnboardingStep3Body,
      options: [
        for (final goal in RoutineGoal.displayOrder)
          TemplatesOnboardingOption(
            value: goal.wireKey,
            label: templatesGoalLabel(l10n, goal),
          ),
      ],
    ),
    TemplatesOnboardingStep(
      dimension: TemplatesOnboardingDimension.zones,
      cardLabel: l10n.templatesOnboardingStep4Label,
      title: l10n.templatesOnboardingStep4Title,
      body: l10n.templatesOnboardingStep4Body,
      multiSelect: true,
      options: [
        for (final group in templatesOnboardingZones)
          TemplatesOnboardingOption(
            value: group.key,
            label: templatesZoneLabel(l10n, group),
          ),
      ],
    ),
  ];
}

/// Localised label for a goal.
///
/// A switch rather than a field on the enum: `RoutineGoal` stays free of UI
/// copy so ES and EN live together in `lib/l10n`.
String templatesGoalLabel(AppL10n l10n, RoutineGoal goal) => switch (goal) {
      RoutineGoal.health => l10n.templatesGoalHealth,
      RoutineGoal.injuryPrevention => l10n.templatesGoalInjuryPrevention,
      RoutineGoal.aesthetics => l10n.templatesGoalAesthetics,
      RoutineGoal.sport => l10n.templatesGoalSport,
      RoutineGoal.wellbeing => l10n.templatesGoalWellbeing,
    };

/// Localised label for a priority zone.
///
/// `MuscleGroup.label` is Spanish-only (it predates l10n), so the six zones this
/// flow offers get their own entries. Unlisted groups fall back to the enum's
/// label rather than throwing — this helper must never be the reason a picker
/// crashes.
String templatesZoneLabel(AppL10n l10n, MuscleGroup group) => switch (group) {
      MuscleGroup.espalda => l10n.templatesZoneBack,
      MuscleGroup.pecho => l10n.templatesZoneChest,
      MuscleGroup.hombros => l10n.templatesZoneShoulders,
      MuscleGroup.gluteos => l10n.templatesZoneGlutes,
      MuscleGroup.cuadriceps => l10n.templatesZoneQuads,
      MuscleGroup.abdominales => l10n.templatesZoneCore,
      _ => group.label,
    };
