import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';

/// A schematic of the "Nuevo ejercicio" screen, drawn for the feature
/// onboarding.
///
/// Same reasoning as [OnboardingIllustration] — widgets and [AppPalette] rather
/// than a screenshot, so it is correct in both themes, carries nobody's data,
/// and cannot go stale in silence (see `docs/onboarding-tour.md`).
///
/// ── Why this one is NOT abstract ────────────────────────────────────────────
/// The welcome-tour illustrations are deliberately blocks-not-text: they answer
/// "what is the shape of that screen". These answer a different question —
/// "which fields does the form have, and what goes in them" — and a grey block
/// cannot say `Grupo muscular`. So the labels here are legible and are copied
/// verbatim from the real screen.
///
/// Every string below is quoted from
/// `lib/features/workout/presentation/custom_exercise_editor_screen.dart`:
/// header `NUEVO EJERCICIO` (:178), `Nombre` (:193) with hint
/// `Ej: Sentadilla búlgara` (:197), `Grupo muscular` (:200),
/// `Equipamiento (opcional)` (:226), `Descripción / cues` (:234),
/// `Video del ejercicio` (:242) with hint `Pegá un link de YouTube` (:246),
/// `Subir mi propio video` (:857) and `MP4 / MOV — reproduce inline en TREINO`
/// (:868). **If a label changes there, change it here.**
///
/// The sample values (`Sentadilla búlgara`, `Cuádriceps`, `Mancuernas`) come
/// from the design handoff, not from the app — they are illustrative content,
/// not UI chrome.
class CustomExerciseOnboardingArt extends StatelessWidget {
  const CustomExerciseOnboardingArt._(this._variant);

  /// Slide 1 — the empty form with `Nombre` focused and filled in.
  const CustomExerciseOnboardingArt.form() : this._(_Variant.form);

  /// Slide 2 — the video section: link field, upload affordance, player.
  const CustomExerciseOnboardingArt.video() : this._(_Variant.video);

  /// Slide 3 — the finished exercise sitting in a routine day.
  const CustomExerciseOnboardingArt.library() : this._(_Variant.library);

  final _Variant _variant;

  /// Fixed design canvas. Everything inside is laid out against these numbers
  /// and then scaled by the [FittedBox] to whatever room the slide has — one
  /// guard instead of N, exactly as `OnboardingIllustration` does it. Without
  /// it every fixed dimension in here is its own overflow waiting for a 320x568
  /// screen at 2x text scale.
  static const _canvas = Size(320, 236);

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Center(
      child: AspectRatio(
        aspectRatio: _canvas.width / _canvas.height,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            // Tinted card, not `bgCard`: this sits ON a sheet that is already
            // `bgCard`, so a same-colour panel would vanish. Tinting off
            // `textPrimary` inverts with the theme for free.
            color: palette.textPrimary.withValues(alpha: 0.05),
            border: Border.all(
              color: palette.textPrimary.withValues(alpha: 0.10),
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          // The frame (border, radius) stays outside the FittedBox so it renders
          // at true scale and never goes blurry.
          child: FittedBox(
            child: SizedBox(
              width: _canvas.width,
              height: _canvas.height,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _ArtHeader(),
                    const SizedBox(height: 12),
                    Expanded(
                      child: switch (_variant) {
                        _Variant.form => const _FormBody(),
                        _Variant.video => const _VideoBody(),
                        _Variant.library => const _LibraryBody(),
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _Variant { form, video, library }

/// `‹ NUEVO EJERCICIO` — the real screen's back affordance and title.
class _ArtHeader extends StatelessWidget {
  const _ArtHeader();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final muted = palette.textPrimary.withValues(alpha: 0.55);

    return Row(
      children: [
        Icon(TreinoIcon.back, size: 13, color: muted),
        const SizedBox(width: 8),
        Text(
          'NUEVO EJERCICIO', // i18n
          style: GoogleFonts.barlowCondensed(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
            height: 1.0,
            color: muted,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────── slide 1 · form

class _FormBody extends StatelessWidget {
  const _FormBody();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel('Nombre'), // i18n
        SizedBox(height: 8),
        _FocusedNameField(),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _LabelledField(
                label: 'Grupo muscular', // i18n
                value: 'Cuádriceps',
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _LabelledField(
                label: 'Equipamiento (opcional)', // i18n
                value: 'Mancuernas',
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        _FieldLabel('Descripción / cues'), // i18n
        SizedBox(height: 8),
        Expanded(
          child: _Box(
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: _Placeholder('Torso firme, rodilla alineada…'),
            ),
          ),
        ),
      ],
    );
  }
}

/// The `Nombre` input in focus: 1.5px accent border plus the accent halo the
/// real form draws, and a caret so it reads as "you are typing here".
class _FocusedNameField extends StatelessWidget {
  const _FocusedNameField();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: palette.textPrimary.withValues(alpha: 0.04),
        border: Border.all(color: palette.accent, width: 1.5),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: palette.accent.withValues(alpha: 0.14),
            spreadRadius: 3,
          ),
        ],
      ),
      child: Row(
        children: [
          Text(
            'Sentadilla búlgara',
            style: GoogleFonts.barlow(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              height: 1.0,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(width: 4),
          Container(width: 1.5, height: 15, color: palette.accent),
        ],
      ),
    );
  }
}

/// A label over a filled, unfocused field — the two dropdowns of the real form.
class _LabelledField extends StatelessWidget {
  const _LabelledField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label),
        const SizedBox(height: 8),
        _Box(
          height: 32,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.barlow(
                      fontSize: 12,
                      height: 1.0,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
                Icon(
                  TreinoIcon.chevronDown,
                  size: 10,
                  color: palette.textPrimary.withValues(alpha: 0.45),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────── slide 2 · video

class _VideoBody extends StatelessWidget {
  const _VideoBody();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel('Video del ejercicio'), // i18n
        const SizedBox(height: 8),
        const _Box(
          height: 32,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _Placeholder('Pegá un link de YouTube'), // i18n
            ),
          ),
        ),
        const SizedBox(height: 12),
        _DashedBox(
          color: palette.accent,
          fill: palette.accent.withValues(alpha: 0.10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: palette.accent,
                    borderRadius: BorderRadius.circular(9999),
                  ),
                  // Ink on accent — never `palette.bg`, which is near-white in
                  // the light theme and drops this to 1.6:1.
                  child: const Icon(
                    TreinoIcon.plus,
                    size: 13,
                    color: _onAccent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Subir mi propio video', // i18n
                        style: GoogleFonts.barlow(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          height: 1.0,
                          color: palette.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const _Placeholder(
                        'MP4 / MOV — reproduce inline en TREINO', // i18n
                        size: 9,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Expanded(child: _VideoPlayer()),
      ],
    );
  }
}

class _VideoPlayer extends StatelessWidget {
  const _VideoPlayer();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        // The player letterbox is dark in BOTH themes — video needs it.
        color: palette.scrimDark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            TreinoIcon.play,
            size: 24,
            color: AppColors.bone.withValues(alpha: 0.90),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: palette.highlight.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(9999),
              ),
              child: Text(
                'TU VIDEO', // i18n
                style: GoogleFonts.barlow(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  height: 1.0,
                  // `bone`, not `highlight`: magenta on its own 22% tint is
                  // under 2:1. The letterbox is dark in both themes, so a fixed
                  // light foreground is the readable one here.
                  color: AppColors.bone,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────── slide 3 · library

class _LibraryBody extends StatelessWidget {
  const _LibraryBody();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'DÍA 1 · EMPUJE', // i18n
              style: GoogleFonts.barlowCondensed(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                height: 1.0,
                color: palette.textPrimary.withValues(alpha: 0.55),
              ),
            ),
            const _Placeholder('3 ejercicios', size: 9), // i18n
          ],
        ),
        const SizedBox(height: 12),
        const _ExerciseRow(
          title: 'Sentadilla búlgara',
          detail: '3 × 10 · Cuádriceps',
          isOwn: true,
        ),
        const SizedBox(height: 8),
        const _ExerciseRow(title: 'Press banca', detail: '4 × 8 · Pecho'),
        const SizedBox(height: 8),
        _DashedBox(
          color: palette.textPrimary.withValues(alpha: 0.22),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(TreinoIcon.plus, size: 12, color: palette.accent),
                const SizedBox(width: 8),
                Text(
                  'Agregar ejercicio', // i18n
                  style: GoogleFonts.barlow(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                    color: palette.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One row of a routine day. [isOwn] is the exercise the user just created:
/// accent thumbnail, accent outline and a `MÍO` badge.
class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({
    required this.title,
    required this.detail,
    this.isOwn = false,
  });

  final String title;
  final String detail;
  final bool isOwn;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: palette.textPrimary.withValues(alpha: 0.07),
        border: isOwn
            ? Border.all(color: palette.accent.withValues(alpha: 0.35))
            : null,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isOwn
                  ? palette.accent
                  : palette.textPrimary.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: isOwn
                ? const Icon(TreinoIcon.play, size: 12, color: _onAccent)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.barlow(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                _Placeholder(detail, size: 9),
              ],
            ),
          ),
          if (isOwn) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(9999),
              ),
              child: Text(
                'MÍO', // i18n
                style: GoogleFonts.barlow(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  height: 1.0,
                  color: palette.accent,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────── shared

/// Ink for foregrounds sitting on [AppPalette.accent].
///
/// NOT `palette.bg`: that is the repo's habit (~30 call sites) but it resolves
/// to the light theme's near-white background, giving **1.57:1** against mint —
/// a WCAG AA failure. `AppColors.ink` against the same mint gives **12.1:1**,
/// and unlike `bg` it does not flip with the theme, which is the whole point:
/// the accent does not flip either.
///
/// When this branch is reconciled with `origin/main` this becomes
/// `TreinoButtonTokens.foreground(context)`, which resolves to the same ink.
const _onAccent = AppColors.ink;

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.barlow(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        height: 1.0,
        color: palette.textPrimary.withValues(alpha: 0.50),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder(this.text, {this.size = 12});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.barlow(
        fontSize: size,
        height: 1.0,
        color: palette.textPrimary.withValues(alpha: 0.45),
      ),
    );
  }
}

/// An empty outlined field.
class _Box extends StatelessWidget {
  const _Box({required this.child, this.height});

  final Widget child;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Container(
      height: height,
      width: double.infinity,
      alignment: height == null ? Alignment.topLeft : Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border.all(
          color: palette.textPrimary.withValues(alpha: 0.14),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

/// Dashed-outline container. Flutter ships no dashed border, and both the
/// upload affordance and the "add exercise" row are dashed in the handoff —
/// the dashes are what marks them as "not filled in yet".
class _DashedBox extends StatelessWidget {
  const _DashedBox({required this.color, required this.child, this.fill});

  final Color color;
  final Color? fill;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(color: color, fill: fill),
      child: SizedBox(width: double.infinity, child: child),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, this.fill});

  final Color color;
  final Color? fill;

  static const _radius = 12.0;
  static const _dash = 4.0;
  static const _gap = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(_radius),
    );

    if (fill != null) {
      canvas.drawRRect(rrect, Paint()..color = fill!);
    }

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + _dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), stroke);
        distance = end + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.fill != fill;
}
