/// The five trainer screens the tour previews.
///
/// Every string here is verbatim from the handoff, including the sample data.
/// The numbers are populated on purpose — the real screenshots the design was
/// built from were nearly empty ("0 pendientes", "Nadie entrenó hoy todavía"),
/// and the handoff is explicit that the tour shows the product inhabited.
/// Changing a name or a figure here changes the design.
///
/// Drawn rather than composed from real screens — see `trainer_preview_kit.dart`
/// for why that reversal is deliberate.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import 'widgets/onboarding_nav_bar.dart';
import 'widgets/onboarding_pulsing_dot.dart';
import 'widgets/trainer_preview_kit.dart';
import '../../../app/theme/tokens/primitives.dart';

// ── 1 — Inicio · resumen del día ────────────────────────────────────────────

class TrainerHomePreview extends StatelessWidget {
  const TrainerHomePreview({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return _Shell(
      activeTab: 2,
      children: [
        Text(
          'MIÉRCOLES 12 AGOSTO',
          style: GoogleFonts.barlowCondensed(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
            color: palette.accent,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                'HOLA, MATEO',
                style: GoogleFonts.barlowCondensed(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  height: 1.0,
                  color: palette.textPrimary,
                ),
              ),
            ),
            Icon(TreinoIcon.bell, size: 22, color: palette.textPrimary),
            const SizedBox(width: 12),
            const TAvatar(initials: 'MP', size: 40, ring: true),
          ],
        ),
        const SizedBox(height: 16),
        TCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RESUMEN DEL DÍA',
                style: GoogleFonts.barlowCondensed(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.6,
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _Stat(value: '3', label: 'PENDIENTES', color: palette.accent),
                  _VDivider(palette: palette),
                  _Stat(
                    value: '5',
                    label: 'COMPLETADAS',
                    color: palette.textPrimary,
                  ),
                  _VDivider(palette: palette),
                  _Stat(
                    value: '1',
                    label: 'CANCELADAS',
                    color: palette.danger,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const TSectionHeader(title: 'PRÓXIMAS SESIONES', action: 'Agenda'),
        const SizedBox(height: 8),
        const TCard(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            children: [
              _SessionRow(
                time: '12:00',
                initials: 'LU',
                name: 'Lucía Ammal',
                meta: 'Hoy · 60 min',
                imminent: true,
              ),
              SizedBox(height: 10),
              THairline(),
              SizedBox(height: 10),
              _SessionRow(
                time: '17:30',
                initials: 'AG',
                name: 'Agustín Sosa',
                meta: 'Hoy · 45 min',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const TSectionHeader(
          title: 'ENTRENARON HOY',
          action: 'Dejar feedback',
        ),
        const SizedBox(height: 8),
        const TCard(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            children: [
              _TrainedRow(
                initials: 'F',
                name: 'Franco Molina',
                meta: 'Push A · 52 min · 3.240 kg',
              ),
              SizedBox(height: 10),
              THairline(),
              SizedBox(height: 10),
              _TrainedRow(
                initials: 'L',
                name: 'Lucía Ammal',
                meta: 'Full Body B · 47 min · 2.610 kg',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const TSectionHeader(title: 'PAGOS POR COBRAR', action: '+ Cobro'),
        const SizedBox(height: 8),
        TCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '2 cobros pendientes',
                      style: GoogleFonts.barlow(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Agustín · vence 15/08 · Lucía · vence 20/08',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.barlow(
                        fontSize: 12,
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                r'$64.000',
                style: GoogleFonts.barlowCondensed(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                  color: palette.highlight,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const TButton(label: 'ASIGNAR RUTINA', icon: TreinoIcon.plus),
      ],
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.time,
    required this.initials,
    required this.name,
    required this.meta,
    this.imminent = false,
  });

  final String time;
  final String initials;
  final String name;
  final String meta;

  /// The next session up — carries the pulsing dot.
  final bool imminent;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Row(
      children: [
        Text(
          time,
          style: GoogleFonts.barlowCondensed(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            height: 1.0,
            color: palette.accent,
          ),
        ),
        const SizedBox(width: 10),
        TAvatar(initials: initials, size: 32, gradient: false),
        const SizedBox(width: 10),
        Expanded(child: TRowText(title: name, subtitle: meta)),
        if (imminent) ...[
          const OnboardingPulsingDot(),
          const SizedBox(width: 8),
        ],
        Icon(
          TreinoIcon.chevronRight,
          size: 16,
          color: palette.textMuted.withValues(alpha: 0.6),
        ),
      ],
    );
  }
}

class _TrainedRow extends StatelessWidget {
  const _TrainedRow({
    required this.initials,
    required this.name,
    required this.meta,
  });

  final String initials;
  final String name;
  final String meta;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Row(
      children: [
        TAvatar(initials: initials, size: 32),
        const SizedBox(width: 10),
        Expanded(child: TRowText(title: name, subtitle: meta)),
        Icon(TreinoIcon.check, size: 18, color: palette.accent),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.color});

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.barlowCondensed(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              height: 1.0,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.barlowCondensed(
              fontSize: 10,
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

class _VDivider extends StatelessWidget {
  const _VDivider({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 34, color: palette.border);
}

// ── 2 — Entrenar · crear planes ─────────────────────────────────────────────

class TrainerWorkoutPreview extends StatelessWidget {
  const TrainerWorkoutPreview({super.key});

  static const _templates = <({String name, String meta})>[
    (name: 'Fuerza · Bloque 2', meta: '4 días · 6 ejercicios'),
    (name: 'Full Body express', meta: '2 días · 5 ejercicios'),
    (name: 'Hipertrofia PPL', meta: '6 días · 8 ejercicios'),
    (name: 'Vuelta a la actividad', meta: '3 días · 5 ejercicios'),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return _Shell(
      activeTab: 0,
      children: [
        Text(
          'CREAR PLANES',
          style: GoogleFonts.barlowCondensed(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            height: 1.0,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Tu espacio para armar plantillas de rutina y asignarlas a tus '
          'alumnos.',
          style: GoogleFonts.barlow(
            fontSize: 13,
            height: 1.45,
            color: palette.textMuted,
          ),
        ),
        const SizedBox(height: 16),
        TCard(
          borderColor: palette.accent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(TreinoIcon.users, size: 18, color: palette.accent),
                  const SizedBox(width: 8),
                  Text(
                    'ASIGNAR A UN ALUMNO',
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                      color: palette.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Elegí un alumno y armale el plan en su perfil. La plantilla '
                'queda guardada y la podés reutilizar.',
                style: GoogleFonts.barlow(
                  fontSize: 12,
                  height: 1.45,
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(height: 12),
              const TButton(label: 'VER ALUMNOS'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'TU BIBLIOTECA DE PLANTILLAS',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '+ NUEVA',
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: palette.accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Visible para tus alumnos',
                          style: GoogleFonts.barlow(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Tus alumnos ven todas tus plantillas en su Workout.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.barlow(
                            fontSize: 11,
                            color: palette.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  const _ToggleOn(),
                ],
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < _templates.length; i++) ...[
                if (i > 0) ...[
                  const SizedBox(height: 10),
                  const THairline(),
                  const SizedBox(height: 10),
                ],
                _TemplateRow(
                  name: _templates[i].name,
                  meta: _templates[i].meta,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The "Visible para tus alumnos" switch, drawn in its ON state.
class _ToggleOn extends StatelessWidget {
  const _ToggleOn();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Container(
      width: 40,
      height: 23,
      padding: const EdgeInsets.all(2),
      alignment: Alignment.centerRight,
      decoration: BoxDecoration(
        color: palette.accent,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Container(
        width: 19,
        height: 19,
        decoration: BoxDecoration(
          // The knob sits on accent, so it takes `palette.bg`.
          color: palette.bg,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _TemplateRow extends StatelessWidget {
  const _TemplateRow({required this.name, required this.meta});

  final String name;
  final String meta;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Row(
      children: [
        Expanded(child: TRowText(title: name, subtitle: meta)),
        const SizedBox(width: 8),
        Text(
          'ASIGNAR',
          style: GoogleFonts.barlowCondensed(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: palette.accent,
          ),
        ),
        const SizedBox(width: 6),
        Icon(TreinoIcon.dotsThree, size: 16, color: palette.textMuted),
      ],
    );
  }
}

// ── 3 — Feed ────────────────────────────────────────────────────────────────

class TrainerFeedPreview extends StatelessWidget {
  const TrainerFeedPreview({super.key});

  static const _gymPeople = <({String initial, String name})>[
    (initial: 'A', name: 'AGUSTÍN'),
    (initial: 'C', name: 'CAMILA'),
    (initial: 'J', name: 'JULIÁN'),
    (initial: 'S', name: 'SOFÍA'),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return _Shell(
      activeTab: 1,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'FEED',
                style: GoogleFonts.barlowCondensed(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  height: 1.0,
                  color: palette.textPrimary,
                ),
              ),
            ),
            Icon(TreinoIcon.bell, size: 20, color: palette.textPrimary),
            const SizedBox(width: 12),
            Icon(TreinoIcon.chat, size: 20, color: palette.textPrimary),
            const SizedBox(width: 12),
            Icon(TreinoIcon.search, size: 20, color: palette.textPrimary),
            const SizedBox(width: 12),
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palette.accent,
                shape: BoxShape.circle,
              ),
              // "+" on accent — `palette.bg`.
              child: Icon(TreinoIcon.plus, size: 16, color: palette.bg),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            TChip(
              // Espeja `feedSegmentFollowing` del pill real (SEGUIDORES). Si
              // ese label cambia, este chip queda desactualizado en silencio —
              // es la contracara de dibujar la pantalla en vez de capturarla.
              label: 'SEGUIDORES',
              color: palette.accent,
              filled: true,
              fontSize: 11,
            ),
            const SizedBox(width: 8),
            TChip(label: 'MI GYM', color: palette.textMuted, fontSize: 11),
            const SizedBox(width: 8),
            TChip(label: 'PÚBLICO', color: palette.textMuted, fontSize: 11),
          ],
        ),
        const SizedBox(height: 14),
        TCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const TAvatar(initials: 'L', size: 34),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: TRowText(
                      title: 'Lucía Ammal',
                      subtitle: 'TU ALUMNA · hace 2h',
                    ),
                  ),
                  const SizedBox(width: 8),
                  TChip(label: 'ALUMNA', color: palette.highlight),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Full Body B terminado. Subí 5 kg en remo con barra 💪',
                style: GoogleFonts.barlow(
                  fontSize: 13,
                  height: 1.45,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              const _PostStats(items: ['2.610 kg', '47 min', '5 ej.']),
              const SizedBox(height: 10),
              const _Reactions(counts: [18, 7, 2]),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  TAvatar(initials: 'F', size: 34),
                  SizedBox(width: 10),
                  Expanded(
                    child: TRowText(
                      title: 'Franco Molina',
                      subtitle: 'GYM SUR · hace 5h',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius:
                    BorderRadius.circular(AppDecorativeRadii.previewPhoto),
                child: const SizedBox(
                  height: 180,
                  width: double.infinity,
                  // Bundled, not fetched: a preview has to render offline and
                  // identically on every run.
                  child: Image(
                    image: AssetImage('assets/onboarding/feed-post-photo.png'),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Última serie de la semana. Bloque 2 cerrado, gracias coach.',
                style: GoogleFonts.barlow(
                  fontSize: 13,
                  height: 1.45,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              const _Reactions(counts: [31, 14]),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const TSectionHeader(title: 'PERSONAS DE TU GYM'),
        const SizedBox(height: 8),
        TCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            children: [
              for (var i = 0; i < _gymPeople.length; i++) ...[
                if (i > 0) ...[
                  const SizedBox(height: 10),
                  const THairline(),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    TAvatar(initials: _gymPeople[i].initial, size: 30),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _gymPeople[i].name,
                        style: GoogleFonts.barlowCondensed(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    Icon(
                      TreinoIcon.chevronRight,
                      size: 15,
                      color: palette.textMuted.withValues(alpha: 0.6),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PostStats extends StatelessWidget {
  const _PostStats({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Row(
      children: [
        for (final item in items) ...[
          Text(
            item,
            style: GoogleFonts.barlowCondensed(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(width: 14),
        ],
      ],
    );
  }
}

class _Reactions extends StatelessWidget {
  const _Reactions({required this.counts});

  /// Heart, flame, comment — in the handoff's order. A two-item list drops the
  /// comment icon, which is what the photo post shows.
  final List<int> counts;

  static const _icons = [
    TreinoIcon.reactionLike,
    TreinoIcon.reactionFire,
    TreinoIcon.chat,
  ];

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Row(
      children: [
        for (var i = 0; i < counts.length; i++) ...[
          Icon(_icons[i], size: 16, color: palette.textMuted),
          const SizedBox(width: 5),
          Text(
            '${counts[i]}',
            style: GoogleFonts.barlow(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(width: 16),
        ],
      ],
    );
  }
}

// ── 4 — Coach · alumnos ─────────────────────────────────────────────────────

class TrainerCoachPreview extends StatelessWidget {
  const TrainerCoachPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return _Shell(
      activeTab: 3,
      children: [
        const _SegmentedPill(labels: ['ALUMNOS', 'AGENDA']),
        const SizedBox(height: 14),
        const _StudentCard(
          name: 'Agustín Sosa',
          since: 'Vinculado desde 27/07/2026',
          chip: 'ACTIVO',
          plan: 'Fuerza · Bloque 2',
          progress: '4 de 5 sesiones',
        ),
        const SizedBox(height: 12),
        const _StudentCard(
          name: 'Lucía Ammal',
          since: 'Vinculado desde 27/07/2026',
          chip: 'ACTIVA',
          plan: 'Full Body express',
          progress: '2 de 3 sesiones',
        ),
        const SizedBox(height: 12),
        TCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: palette.highlight.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  TreinoIcon.users,
                  size: 18,
                  color: palette.highlight,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: TRowText(
                  title: '1 solicitud entrante',
                  subtitle: 'Camila Duarte quiere vincularse',
                ),
              ),
              Icon(
                TreinoIcon.chevronRight,
                size: 16,
                color: palette.textMuted.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StudentCard extends StatelessWidget {
  const _StudentCard({
    required this.name,
    required this.since,
    required this.chip,
    required this.plan,
    required this.progress,
  });

  final String name;
  final String since;
  final String chip;
  final String plan;
  final String progress;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return TCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: palette.border),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  TreinoIcon.tabProfile,
                  size: 18,
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: TRowText(title: name, subtitle: since)),
              const SizedBox(width: 8),
              TChip(label: chip, color: palette.accent),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  plan,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.barlow(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                progress,
                style: GoogleFonts.barlow(
                  fontSize: 12,
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TButton(
                  label: 'PAUSAR VÍNCULO',
                  filled: false,
                  outlineColor: palette.accent,
                  height: 34,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: TButton(
                  label: 'TERMINAR VÍNCULO',
                  filled: false,
                  height: 34,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Two-segment pill, first segment active.
class _SegmentedPill extends StatelessWidget {
  const _SegmentedPill({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius:
            BorderRadius.circular(AppDecorativeRadii.previewCardFrame),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: i == 0 ? palette.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Center(
                  child: Text(
                    labels[i],
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      // Label on accent — `palette.bg`.
                      color: i == 0 ? palette.bg : palette.textMuted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── 5 — Perfil · yo ─────────────────────────────────────────────────────────

class TrainerProfilePreview extends StatelessWidget {
  const TrainerProfilePreview({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return _Shell(
      activeTab: 4,
      children: [
        Text(
          'TU CUENTA',
          style: GoogleFonts.barlowCondensed(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
            color: palette.accent,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'YO',
          style: GoogleFonts.barlowCondensed(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            height: 1.0,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        TCard(
          child: Row(
            children: [
              TAvatar(initials: 'MP', size: 48, solid: palette.highlight),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TRowText(
                      title: 'mateo presset',
                      subtitle: 'Coach · Plan Pro',
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        _InlineStat(value: '12', label: 'ALUMNOS'),
                        SizedBox(width: 14),
                        _InlineStat(value: '4,8', label: 'RATING'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        TCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'PERFIL PÚBLICO',
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                  TChip(label: 'VISIBLE', color: palette.accent),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Aparecés en Coach Discovery · Presencial · Online',
                style: GoogleFonts.barlow(
                  fontSize: 12,
                  height: 1.4,
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(height: 12),
              const Row(
                children: [
                  Expanded(
                    child: TButton(
                      label: 'VER PREVIEW',
                      filled: false,
                      height: 34,
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(child: TButton(label: 'EDITAR', height: 34)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const _Tile(
          icon: TreinoIcon.users,
          label: 'Solicitudes entrantes',
          badge: '1',
        ),
        const SizedBox(height: 10),
        const _Tile(icon: TreinoIcon.calendar, label: 'Disponibilidad'),
        const SizedBox(height: 10),
        const _Tile(icon: TreinoIcon.tabWorkout, label: 'Mis ejercicios'),
        const SizedBox(height: 10),
        _Tile(
          icon: TreinoIcon.signOut,
          label: 'Cerrar sesión',
          color: palette.highlight,
        ),
        const SizedBox(height: 10),
        _Tile(
          icon: TreinoIcon.trash,
          label: 'Eliminar cuenta',
          color: palette.danger,
        ),
      ],
    );
  }
}

class _InlineStat extends StatelessWidget {
  const _InlineStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: GoogleFonts.barlowCondensed(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            height: 1.0,
            color: palette.accent,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.barlowCondensed(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: palette.textMuted,
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    this.badge,
    this.color,
  });

  final IconData icon;
  final String label;
  final String? badge;

  /// Overrides the neutral treatment — the handoff tints the destructive rows.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final tint = color ?? palette.accent;
    final labelColor = color ?? palette.textPrimary;

    return TCard(
      radius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 15, color: tint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.barlow(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: labelColor,
              ),
            ),
          ),
          if (badge case final b?) ...[
            TChip(label: b, color: palette.highlight, fontSize: 11),
            const SizedBox(width: 8),
          ],
          Icon(
            TreinoIcon.chevronRight,
            size: 16,
            color: palette.textMuted.withValues(alpha: 0.6),
          ),
        ],
      ),
    );
  }
}

// ── Shared shell ────────────────────────────────────────────────────────────

/// Screen body plus the nav, laid out the way the athlete previews are.
///
/// The body is deliberately NOT scrollable and NOT unbounded: it is clipped by
/// the device frame. See `onboarding_previews.dart` for the full account of why
/// an unbounded body froze the athlete tour.
class _Shell extends StatelessWidget {
  const _Shell({required this.activeTab, required this.children});

  final int activeTab;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: 0,
              maxHeight: 1700,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: children,
                ),
              ),
            ),
          ),
        ),
        OnboardingNavBar(activeIndex: activeTab),
      ],
    );
  }
}
