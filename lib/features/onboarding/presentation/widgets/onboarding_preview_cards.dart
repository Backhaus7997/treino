/// Cards the handoff adds to the previews that the app does not have yet.
///
/// They live here, in `features/onboarding/`, rather than in the feature they
/// depict. The instruction for this pass was explicit: change the onboarding
/// slides, do not change the app. Dropping a VOLUMEN SEMANAL card into the real
/// workout screen because a tour mock shows one would be shipping a feature
/// through the back door of an onboarding ticket.
///
/// When one of these graduates into the product, it moves to its own feature
/// and the preview imports it from there — the same way the previews already
/// use `EstaSemanaCard`, `PostCard` and the rest.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';

/// The card shell these share: `bgCard`, hairline border, rounded.
///
/// The radius and padding are parameters rather than constants: the handoff
/// gives the VOLUMEN SEMANAL card r-16/p-14 so it matches the routine cards
/// stacked above it, while the Coach cards keep r-20/p-18.
class _Card extends StatelessWidget {
  const _Card({required this.child, this.radius = 20, this.padding = 18});

  final Widget child;
  final double radius;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }
}

// ── Slide 2 — Entrenar ──────────────────────────────────────────────────────

/// VOLUMEN SEMANAL: label + accent delta, a five-bar mini chart whose last two
/// bars are accent-filled, and a caption.
class OnboardingVolumeCard extends StatelessWidget {
  const OnboardingVolumeCard({super.key});

  /// Relative bar heights. The last two are the accent-filled ones, which is
  /// what makes the "+8%" read as a trend rather than a number.
  static const _bars = <double>[0.42, 0.58, 0.50, 0.78, 1.0];

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return _Card(
      radius: 16,
      padding: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'VOLUMEN SEMANAL', // i18n
                style: GoogleFonts.barlowCondensed(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: palette.textMuted,
                ),
              ),
              Text(
                '+8%', // i18n
                style: GoogleFonts.barlowCondensed(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: palette.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 56,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < _bars.length; i++) ...[
                  Expanded(
                    child: FractionallySizedBox(
                      heightFactor: _bars[i],
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: i >= _bars.length - 2
                              ? palette.accent
                              : palette.textMuted.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                  if (i != _bars.length - 1) const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '10.250 kg movidos en 3 sesiones', // i18n
            style: GoogleFonts.barlow(
              fontSize: 13,
              color: palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Slide 4 — Coach ─────────────────────────────────────────────────────────

/// PLAN ASIGNADO: week chip, block title, progress bar, caption.
class OnboardingAssignedPlanCard extends StatelessWidget {
  const OnboardingAssignedPlanCard({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Flexible, not bare: the label and the chip share one line, and
              // a wider font must shrink the label rather than overflow.
              Flexible(
                child: Text(
                  'PLAN ASIGNADO', // i18n
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.barlowCondensed(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    color: palette.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: palette.highlight.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'SEMANA 3', // i18n
                  style: GoogleFonts.barlowCondensed(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: palette.highlight,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'FUERZA · BLOQUE 2', // i18n
            style: GoogleFonts.barlowCondensed(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              height: 1.0,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 8,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ColoredBox(
                      color: palette.textMuted.withValues(alpha: 0.15),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: 0.62,
                    child: ColoredBox(color: palette.accent),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '3 de 5 sesiones completadas esta semana', // i18n
            style: GoogleFonts.barlow(
              fontSize: 13,
              color: palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// ÚLTIMO MENSAJE: the trainer's last line, quoted, plus who and when.
class OnboardingLastMessageCard extends StatelessWidget {
  const OnboardingLastMessageCard({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ÚLTIMO MENSAJE', // i18n
            style: GoogleFonts.barlowCondensed(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '«Metele con la técnica en sentadilla, la semana que viene '
            'subimos carga.»', // i18n
            style: GoogleFonts.barlow(
              fontSize: 15,
              height: 1.45,
              fontStyle: FontStyle.italic,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Valentina · hace 1 día', // i18n
            style: GoogleFonts.barlow(
              fontSize: 13,
              color: palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Slide 3 — Feed ──────────────────────────────────────────────────────────

/// One inline comment under a post: small avatar, name, comment text.
///
/// Rendered as a strip below the real `PostCard` rather than inside it —
/// `PostCard` has no comment-preview slot, and adding one would be a change to
/// the feed, not to the onboarding.
class OnboardingInlineComment extends StatelessWidget {
  const OnboardingInlineComment({
    super.key,
    required this.author,
    required this.text,
  });

  final String author;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.accent,
              shape: BoxShape.circle,
            ),
            child: Text(
              author.substring(0, 1).toUpperCase(),
              style: GoogleFonts.barlowCondensed(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.0,
                // Initials on accent — `onPrimary: palette.bg`.
                color: palette.bg,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$author ',
                    style: GoogleFonts.barlow(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: palette.textPrimary,
                    ),
                  ),
                  TextSpan(
                    text: text,
                    style: GoogleFonts.barlow(
                      fontSize: 13,
                      height: 1.4,
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Slide 3 — the photo post ────────────────────────────────────────────────

/// The photo the handoff's third post shows, bundled so the preview renders
/// offline and identically on every run.
const kOnboardingFeedPhoto = 'assets/onboarding/feed-post-photo.png';

/// A post with an attached photo, drawn for the preview.
///
/// The real `PostCard` DOES model a photo — `Post.photoUrl` exists and the card
/// renders it — but it loads it with `CachedNetworkImage`, whose `errorWidget`
/// collapses the image to nothing when the URL is not reachable. A bundled
/// asset is not a URL, so inside the tour the real card silently drops the
/// photo, which is exactly what showed up on device: a photo post with no
/// photo.
///
/// Teaching `PostCard` to read assets would be changing the feed to satisfy a
/// tour, so the photo variant is drawn here instead. It mirrors the real card's
/// anatomy: header, text, photo, reactions.
class OnboardingPhotoPost extends StatelessWidget {
  const OnboardingPhotoPost({
    super.key,
    required this.author,
    required this.meta,
    required this.text,
    required this.reactions,
  });

  final String author;
  final String meta;
  final String text;

  /// Icon + count pairs, in the order the real card lays them out.
  final List<({IconData icon, int count})> reactions;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [palette.accent, palette.highlight],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    author.substring(0, 1).toUpperCase(),
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                      // Initials on accent — `onPrimary: palette.bg`.
                      color: palette.bg,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.barlow(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: palette.textPrimary,
                        ),
                      ),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.barlow(
                          fontSize: 13,
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              text,
              style: GoogleFonts.barlow(
                fontSize: 15,
                height: 1.45,
                color: palette.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: 190,
                width: double.infinity,
                child: Image.asset(kOnboardingFeedPhoto, fit: BoxFit.cover),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            child: Row(
              children: [
                for (final r in reactions) ...[
                  Icon(r.icon, size: 20, color: palette.textMuted),
                  const SizedBox(width: 6),
                  Text(
                    '${r.count}',
                    style: GoogleFonts.barlow(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: palette.textMuted,
                    ),
                  ),
                  const SizedBox(width: 18),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Slide 5 — Perfil ────────────────────────────────────────────────────────

/// SESIONES · VOLUMEN KG · RACHA.
///
/// The last figure is drawn in `highlight`, not `accent` — the handoff singles
/// the streak out that way, and it is the one place on the slide where the
/// magenta half of the palette appears.
class OnboardingProfileStats extends StatelessWidget {
  const OnboardingProfileStats({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return _Card(
      radius: 16,
      padding: 14,
      child: Row(
        children: [
          _Stat(value: '48', label: 'SESIONES', color: palette.textPrimary),
          _Divider(palette: palette),
          _Stat(value: '38k', label: 'VOLUMEN KG', color: palette.textPrimary),
          _Divider(palette: palette),
          _Stat(value: '4', label: 'RACHA', color: palette.highlight),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    required this.color,
  });

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
              fontSize: 11,
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

class _Divider extends StatelessWidget {
  const _Divider({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 34, color: palette.border);
  }
}
