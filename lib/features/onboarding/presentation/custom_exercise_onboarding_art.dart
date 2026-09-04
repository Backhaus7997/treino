import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../app/theme/tokens/primitives.dart';

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

  /// Slide 4 — one-line entry converted into a complete prescription.
  const CustomExerciseOnboardingArt.quickEntry()
      : this._(_Variant.quickEntry);

  /// Slide 5 — a routine row being moved by its drag handle.
  const CustomExerciseOnboardingArt.drag() : this._(_Variant.drag);

  /// Slide 6 — the overflow menu containing the remaining editor actions.
  const CustomExerciseOnboardingArt.menu() : this._(_Variant.menu);

  /// The set chip opened on its four types.
  const CustomExerciseOnboardingArt.setTypes() : this._(_Variant.setTypes);

  /// The accessory bar that only exists while the keyboard is up.
  const CustomExerciseOnboardingArt.keyboardBar()
      : this._(_Variant.keyboardBar);

  /// Week tabs plus the scope question that adding an exercise triggers.
  const CustomExerciseOnboardingArt.weeks() : this._(_Variant.weeks);

  /// Coach Hub only — the exercise panel pinned open beside the day.
  const CustomExerciseOnboardingArt.sidePanel()
      : this._(_Variant.sidePanel);

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
            borderRadius: BorderRadius.circular(AppRadius.md),
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
                    _ArtHeader(_variant),
                    const SizedBox(height: 12),
                    Expanded(
                      child: switch (_variant) {
                        _Variant.form => const _FormBody(),
                        _Variant.video => const _VideoBody(),
                        _Variant.library => const _LibraryBody(),
                        _Variant.quickEntry => const _QuickEntryBody(),
                        _Variant.drag => const _DragBody(),
                        _Variant.menu => const _MenuBody(),
                        _Variant.setTypes => const _SetTypesBody(),
                        _Variant.keyboardBar => const _KeyboardBarBody(),
                        _Variant.weeks => const _WeeksBody(),
                        _Variant.sidePanel => const _SidePanelBody(),
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

enum _Variant {
  form,
  video,
  library,
  quickEntry,
  drag,
  menu,
  setTypes,
  keyboardBar,
  weeks,
  sidePanel,
}

/// `‹ NUEVO EJERCICIO` — the real screen's back affordance and title.
class _ArtHeader extends StatelessWidget {
  const _ArtHeader(this.variant);

  final _Variant variant;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final muted = palette.textPrimary.withValues(alpha: 0.55);

    return Row(
      children: [
        Icon(TreinoIcon.back, size: 13, color: muted),
        const SizedBox(width: 8),
        // Flexible: el título más largo del set —`PLAN DE VARIAS SEMANAS`—
        // desbordaba esta fila. Acá pasa con la fuente de fallback de los
        // tests y no en producción, pero un header que se recorta es mejor que
        // uno que esconde contenido, y así el próximo título largo tampoco
        // rompe nada.
        Flexible(
            child: Text(
          switch (variant) {
            _Variant.form || _Variant.video => 'NUEVO EJERCICIO',
            _Variant.library ||
            _Variant.drag ||
            _Variant.menu ||
            _Variant.setTypes ||
            _Variant.keyboardBar =>
              'EDITOR DE RUTINA',
            _Variant.quickEntry => 'ENTRADA RÁPIDA',
            _Variant.weeks => 'PLAN DE VARIAS SEMANAS',
            _Variant.sidePanel => 'EDITOR EN LA WEB',
          }, // i18n
          style: GoogleFonts.barlowCondensed(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
            height: 1.0,
            color: muted,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        )),
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
        borderRadius: BorderRadius.circular(AppRadius.sm),
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
          const SizedBox(width: AppSpacing.hairline),
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
                    borderRadius: BorderRadius.circular(AppRadius.full),
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
                      const SizedBox(height: AppSpacing.hairline),
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
        borderRadius: BorderRadius.circular(AppRadius.sm),
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
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: AppSpacing.hairline),
              decoration: BoxDecoration(
                color: palette.highlight.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(AppRadius.full),
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

// ─────────────────────────────────────────────────── slide 4 · quick entry

class _QuickEntryBody extends StatelessWidget {
  const _QuickEntryBody();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel('Escribí ejercicio, series, reps y peso'), // i18n
        const SizedBox(height: 8),
        _Box(
          height: 38,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'press de banca 4x10 55',
                    style: GoogleFonts.barlow(
                      fontSize: 12,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
                Icon(TreinoIcon.specialty, size: 14, color: palette.accent),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            'SE CONVIERTE EN', // i18n
            style: GoogleFonts.barlowCondensed(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: palette.accent,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const _ExerciseRow(
          title: 'Press de banca',
          detail: '4 series × 10 reps · 55 kg',
          isOwn: true,
        ),
      ],
    );
  }
}

// ───────────────────────────────────────────────────────── slide 5 · drag

class _DragBody extends StatelessWidget {
  const _DragBody();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Column(
      children: [
        const _ExerciseRow(
          title: 'Press militar',
          detail: '3 × 10',
          showDragHandle: true,
        ),
        const SizedBox(height: 8),
        _DashedBox(
          color: palette.accent.withValues(alpha: 0.55),
          fill: palette.accent.withValues(alpha: 0.06),
          child: const SizedBox(height: 38),
        ),
        const SizedBox(height: 8),
        const _ExerciseRow(
          title: 'Press de banca',
          detail: '4 × 10 · moviendo',
          showDragHandle: true,
          lifted: true,
        ),
      ],
    );
  }
}

// ───────────────────────────────────────────────────────── slide 6 · menu

class _MenuBody extends StatelessWidget {
  const _MenuBody();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Stack(
      children: [
        const _ExerciseRow(
          title: 'Press de banca',
          detail: '4 × 10 · 55 kg',
          showMenuButton: true,
        ),
        Align(
          alignment: Alignment.bottomRight,
          child: SizedBox(
            width: 190,
            child: _Box(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _MenuAction('Cambiar ejercicio'), // i18n
                    const SizedBox(height: 8),
                    const _MenuAction('Copiar sets del anterior'), // i18n
                    const SizedBox(height: 8),
                    const _MenuAction('Subir / bajar'), // i18n
                    const SizedBox(height: 8),
                    const _MenuAction('Unir en superserie'), // i18n
                    const SizedBox(height: 8),
                    _MenuAction(
                      'Separar del grupo', // i18n
                      color: palette.highlight,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MenuAction extends StatelessWidget {
  const _MenuAction(this.label, {this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Text(
      label,
      style: GoogleFonts.barlow(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        height: 1.0,
        color: color ?? palette.textPrimary,
      ),
    );
  }
}

// ───────────────────────────────────────────────── slide · tipos de serie

/// La tabla de series con el chip abierto en sus cuatro tipos.
///
/// Los cuatro labels son verbatim de `intl_es_AR.arb`:
/// `routineEditorSetTypeNormal` … `routineEditorSetTypeFailure`. **Si cambian
/// ahí, cambian acá.** Las letras entre paréntesis no son decoración: son la
/// glifo que el chip muestra de verdad (`setChipLabel`).
class _SetTypesBody extends StatelessWidget {
  const _SetTypesBody();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    // En COLUMNA y no en `Stack`: con tres filas de series arriba, el menú
    // anclado abajo se les montaba encima y el dibujo se leía como un bug.
    // Una fila alcanza para decir "esto es una serie"; el menú abajo dice
    // "tocá el número y aparece esto".
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SetRow(chip: '1', kg: '55', reps: '10', esTipo: true),
        const SizedBox(height: 10),
        SizedBox(
          width: 158,
          child: _Box(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _MenuAction('Normal'), // i18n
                  const SizedBox(height: 7),
                  const _MenuAction('Entrada en calor (W)'), // i18n
                  const SizedBox(height: 7),
                  const _MenuAction('Drop (D)'), // i18n
                  const SizedBox(height: 7),
                  _MenuAction(
                    'Al fallo (F)', // i18n
                    color: palette.accent,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Una fila de la tabla de series: chip + kg + reps.
///
/// [esTipo] pinta el chip en acento, que es lo que hace en la pantalla real
/// cuando la serie NO es normal — es la única señal de que ese glifo cambió.
class _SetRow extends StatelessWidget {
  const _SetRow({
    required this.chip,
    required this.kg,
    required this.reps,
    this.esTipo = false,
  });

  final String chip;
  final String kg;
  final String reps;
  final bool esTipo;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: esTipo
                ? palette.accent.withValues(alpha: 0.18)
                : palette.textPrimary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Text(
            chip,
            style: GoogleFonts.barlowCondensed(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              height: 1.0,
              color: esTipo ? palette.accent : palette.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: _Box(height: 22, child: _Celda('$kg kg'))),
        const SizedBox(width: 6),
        Expanded(child: _Box(height: 22, child: _Celda('$reps reps'))),
      ],
    );
  }
}

class _Celda extends StatelessWidget {
  const _Celda(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: _Placeholder(texto, size: 10),
      );
}

// ──────────────────────────────────────────── slide · barra sobre el teclado

/// La barra de accesorio, con la celda enfocada arriba.
///
/// El label de contexto tiene la forma real que documenta `FocusedSetCell`:
/// `Press de banca con barra · set 3 · kg`. Los pasos son los de verdad —
/// 2,5 en kilos (un par de discos de 1,25), 1 en repeticiones — y `A TODAS`
/// es `routineEditorFillColumnLabel` verbatim.
class _KeyboardBarBody extends StatelessWidget {
  const _KeyboardBarBody();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SetRow(chip: '3', kg: '55', reps: '10'),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: palette.textPrimary.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FieldLabel('Press de banca · set 3 · kg'), // i18n
              SizedBox(height: 8),
              Row(
                children: [
                  _BarButton('−2,5'), // i18n
                  SizedBox(width: 6),
                  _BarButton('+2,5'), // i18n
                  Spacer(),
                  _BarButton(
                    'A TODAS', // i18n
                    acento: true,
                    icono: TreinoIcon.copy,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(TreinoIcon.check, size: 11, color: palette.accent),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Peso replicado en todos los sets.', // i18n
                style: GoogleFonts.barlow(
                  fontSize: 9,
                  height: 1.0,
                  color: palette.accent,
                ),
              ),
            ),
            Text(
              'Deshacer', // i18n
              style: GoogleFonts.barlow(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                height: 1.0,
                color: palette.textPrimary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton(this.label, {this.acento = false, this.icono});

  final String label;
  final bool acento;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: acento
            ? palette.accent.withValues(alpha: 0.16)
            : palette.textPrimary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[
            Icon(icono, size: 10, color: palette.accent),
            const SizedBox(width: 4),
          ],
          // `Flexible` + elipsis en vez de un `Text` suelto: con dos de estos
          // en una fila angosta —el pie del panel— el label desbordaba. En
          // producción no llega a recortarse; en los tests sí, porque
          // GoogleFonts no resuelve Barlow y mide con la fuente de fallback,
          // bastante más ancha. Que degrade es correcto en los dos casos:
          // desbordar esconde contenido, elipsis no.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.barlowCondensed(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                height: 1.0,
                color: acento ? palette.accent : palette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────── slide · semanas

/// Las pestañas de semana y la pregunta de alcance.
///
/// `Semana`, `¿En qué semanas agregar?`, `Solo esta semana` y `Todas las
/// semanas` son verbatim de `routineEditorAddWeek`, `routineEditorAddScopeTitle`
/// y `routineEditorScope*`.
class _WeeksBody extends StatelessWidget {
  const _WeeksBody();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            _WeekTab('S1', activa: true),
            SizedBox(width: 6),
            _WeekTab('S2'),
            SizedBox(width: 6),
            _WeekTab('S3'),
            // Separación fija y no `Spacer`: el Spacer se quedaba con TODO el
            // sobrante y empujaba el botón contra el borde, donde desbordaba.
            SizedBox(width: 10),
            Flexible(child: _BarButton('+ Semana', acento: true)), // i18n
          ],
        ),
        const SizedBox(height: 14),
        _Box(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '¿En qué semanas agregar?', // i18n
                  style: GoogleFonts.barlowCondensed(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    height: 1.0,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                const Row(
                  children: [
                    Flexible(child: _BarButton('Solo esta semana')), // i18n
                    SizedBox(width: 6),
                    Flexible(
                      child: _BarButton('Todas las semanas', acento: true),
                    ), // i18n
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _WeekTab extends StatelessWidget {
  const _WeekTab(this.label, {this.activa = false});

  final String label;
  final bool activa;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: activa
            ? palette.accent.withValues(alpha: 0.18)
            : palette.textPrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        label,
        style: GoogleFonts.barlowCondensed(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1.0,
          color: activa ? palette.accent : palette.textPrimary,
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────── slide · panel de la web

/// El día a la izquierda y el panel de ejercicios fijo a la derecha (#860).
///
/// `Agregar (2)` y `En superserie` son los labels reales del pie del panel.
class _SidePanelBody extends StatelessWidget {
  const _SidePanelBody();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // El día: 55/45, la misma proporción que el editor real.
        const Expanded(
          flex: 55,
          child: Column(
            children: [
              _ExerciseRow(title: 'Press de banca', detail: '4 × 10 · 55 kg'),
              SizedBox(height: 6),
              _ExerciseRow(title: 'Aperturas', detail: '3 × 12'),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 45,
          child: _Box(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _FieldLabel('EJERCICIOS'), // i18n
                  const SizedBox(height: 8),
                  const _PanelRow('Press de banca', tildado: true),
                  const SizedBox(height: 5),
                  const _PanelRow('Aperturas', tildado: true),
                  const SizedBox(height: 5),
                  const _PanelRow('Fondos'),
                  const SizedBox(height: 10),
                  const Row(
                    children: [
                      Flexible(
                        child: _BarButton('Agregar (2)', acento: true), // i18n
                      ),
                      SizedBox(width: 4),
                      Flexible(
                        child: _BarButton(
                          'En superserie', // i18n
                          icono: TreinoIcon.streak,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    'Crear ejercicio nuevo', // i18n
                    style: GoogleFonts.barlow(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                      color: palette.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PanelRow extends StatelessWidget {
  const _PanelRow(this.nombre, {this.tildado = false});

  final String nombre;
  final bool tildado;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tildado
                ? palette.accent.withValues(alpha: 0.18)
                : palette.textPrimary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: tildado
              ? Icon(TreinoIcon.check, size: 8, color: palette.accent)
              : null,
        ),
        const SizedBox(width: 6),
        Expanded(child: _Placeholder(nombre, size: 9)),
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
    this.showDragHandle = false,
    this.showMenuButton = false,
    this.lifted = false,
  });

  final String title;
  final String detail;
  final bool isOwn;
  final bool showDragHandle;
  final bool showMenuButton;
  final bool lifted;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: palette.textPrimary.withValues(alpha: 0.07),
        border: isOwn || lifted
            ? Border.all(color: palette.accent.withValues(alpha: 0.35))
            : null,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        boxShadow: lifted
            ? [
                BoxShadow(
                  color: palette.scrimDark.withValues(alpha: 0.18),
                  blurRadius: 8,
                  offset: const Offset(0, AppSpacing.hairline),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          if (showDragHandle) ...[
            Icon(
              TreinoIcon.dragHandle,
              size: 14,
              color: lifted
                  ? palette.accent
                  : palette.textPrimary.withValues(alpha: 0.45),
            ),
            const SizedBox(width: 8),
          ],
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isOwn
                  ? palette.accent
                  : palette.textPrimary.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(AppRadius.sm),
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
                const SizedBox(height: AppSpacing.hairline),
                _Placeholder(detail, size: 9),
              ],
            ),
          ),
          if (isOwn) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: AppSpacing.hairline),
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(AppRadius.full),
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
          if (showMenuButton) ...[
            const SizedBox(width: 8),
            Icon(
              TreinoIcon.dotsThree,
              size: 16,
              color: palette.accent,
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
        borderRadius: BorderRadius.circular(AppRadius.sm),
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
