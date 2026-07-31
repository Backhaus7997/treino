import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_background.dart';
import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_palette.dart';
import '../../../core/utils/kg_format.dart';
import '../../../core/widgets/motion/treino_confetti.dart';
import '../../../core/widgets/motion/treino_fade_slide_in.dart';
import '../../../core/widgets/motion/treino_success_check.dart';
import '../../../core/widgets/treino_icon.dart';
import '../application/post_workout_notifier.dart';
import '../application/session_highlights.dart';
import '../application/session_muscle_distribution.dart';
import '../application/session_providers.dart';
import '../application/session_recognition.dart';
import '../domain/session.dart';
import '../domain/set_log.dart';
import 'widgets/session_highlights_section.dart';
import 'widgets/session_muscle_distribution_section.dart';
import 'widgets/session_stats_card.dart';
import 'widgets/stat_tile.dart';
import '../../../l10n/app_l10n.dart';

class PostWorkoutSummaryScreen extends ConsumerWidget {
  const PostWorkoutSummaryScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUidProvider) ?? '';
    final summaryAsync = ref.watch(
      sessionSummaryProvider((uid: uid, sessionId: sessionId)),
    );
    final isSharing = ref.watch(postWorkoutNotifierProvider).isLoading;
    // Best-effort: mientras carga (o si el catálogo/rutina falla) la sección
    // simplemente no aparece — el gráfico jamás bloquea ni rompe el resumen.
    final muscleDistribution = ref
        .watch(sessionMuscleDistributionProvider(
          (uid: uid, sessionId: sessionId),
        ))
        .valueOrNull;
    // Mismo contrato best-effort para récords/reconocimiento: mientras el
    // scan de historial corre (o si falla), el tile PRS HOY muestra "—" y las
    // secciones de PRs/ejercicios no aparecen — nada bloquea el resumen.
    final highlights = ref
        .watch(sessionHighlightsProvider((uid: uid, sessionId: sessionId)))
        .valueOrNull;

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: summaryAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _ErrorState(
              onRetry: () => ref.invalidate(
                sessionSummaryProvider((uid: uid, sessionId: sessionId)),
              ),
            ),
            data: (data) {
              final session = data.session;
              if (session == null) {
                return const _NotFoundState();
              }
              final loadedBody = _LoadedBody(
                session: session,
                setLogs: data.setLogs,
                muscleDistribution: muscleDistribution,
                highlights: highlights,
                isSharing: isSharing,
                // COMPARTIR abre el composer en vez de publicar de una: el
                // texto es editable, la foto es opcional y el detalle que
                // verá el resto se previsualiza antes de publicar. Publicar
                // (y sus snackbars) vive ahora en
                // ShareWorkoutComposerScreen.
                onShare: () =>
                    context.push('/workout/session-summary/$sessionId/share'),
              );
              // Confetti solo para el cierre exitoso — mismo gate que
              // TreinoSuccessCheck arriba en _LoadedBody. Overlay encima del
              // contenido, nunca bloquea taps (IgnorePointer interno).
              if (!session.wasFullyCompleted) return loadedBody;
              return Stack(
                children: [
                  loadedBody,
                  const Positioned.fill(child: TreinoConfetti()),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Loaded body ───────────────────────────────────────────────────────────────

class _LoadedBody extends StatelessWidget {
  const _LoadedBody({
    required this.session,
    required this.setLogs,
    required this.muscleDistribution,
    required this.highlights,
    required this.isSharing,
    required this.onShare,
  });

  final Session session;
  final List<SetLog> setLogs;
  final SessionMuscleDistribution? muscleDistribution;
  final SessionHighlights? highlights;
  final bool isSharing;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final distribution = muscleDistribution;
    final highlights = this.highlights;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Close icon
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              icon: Icon(TreinoIcon.close, color: palette.textPrimary),
              tooltip: l10n.commonClose,
              onPressed: isSharing ? null : () => context.go('/workout'),
            ),
          ),
          const SizedBox(height: 8),

          // Header — entrada fade+slide sobria (TreinoFadeSlideIn respeta
          // reduce-motion: visible al primer frame, sin delay).
          TreinoFadeSlideIn(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Check que se dibuja one-shot — solo para el cierre exitoso;
                // una sesión abandonada no festeja lo que no se cumplió.
                if (session.wasFullyCompleted) ...[
                  const Center(child: TreinoSuccessCheck()),
                  const SizedBox(height: 12),
                ],
                Text(
                  session.wasFullyCompleted
                      ? l10n.workoutSummaryHeaderCompleted
                      : l10n.workoutSummaryHeaderAbandoned,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w800,
                    fontSize: 32,
                    color: palette.accent,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  session.routineName,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          _RecognitionSlot(highlights: highlights),
          const SizedBox(height: 32),

          // 2×2 stat grid, agrupado en una sola tarjeta para que los números
          // no queden sueltos sobre el fondo.
          SessionStatsCard(
            animateTiles: true,
            entryDelay: AppMotion.stagger(1),
            tiles: [
              StatTile(
                icon: TreinoIcon.clock,
                label: l10n.workoutStatDurationMin,
                value: session.durationMin.toString(),
                countUpValue: session.durationMin,
              ),
              StatTile(
                icon: TreinoIcon.dumbbell,
                label: l10n.workoutStatVolumeKg,
                value: formatVolumeKg(session.totalVolumeKg),
                countUpValue: session.totalVolumeKg,
                countUpFormatter: (v) => formatVolumeKg(v.toDouble()),
              ),
              StatTile(
                icon: TreinoIcon.statSets,
                label: l10n.workoutStatSets,
                value: setLogs.length.toString(),
                countUpValue: setLogs.length,
              ),
              StatTile(
                icon: TreinoIcon.statPr,
                label: l10n.workoutStatPrsToday,
                // null → "—": mientras el scan de récords corre (o falló),
                // y para sesiones que no cuentan como entreno (#372 — un
                // "0" en una sesión abandonada afirmaría una medición que
                // no se hizo).
                value: highlights == null || !session.countsAsWorkout
                    ? null
                    : highlights.recordCount.toString(),
                countUpValue: highlights == null || !session.countsAsWorkout
                    ? null
                    : highlights.recordCount,
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Slots SIEMPRE presentes (shrink cuando no aplican): la cantidad
          // de hijos del Column no cambia cuando la data async llega, así los
          // hermanos de abajo conservan su State y sus entradas one-shot
          // (TreinoFadeSlideIn) no se re-disparan.
          _DistributionSlot(distribution: distribution),
          _PrsSlot(session: session, highlights: highlights),
          _ExercisesSlot(highlights: highlights),

          // Mood row — 5 emojis, visual only (decorative, non-interactive).
          // Flexible + FittedBox per emoji: when a glyph measures wider than
          // expected (tofu .notdef, large font scale) the row scales down
          // instead of overflowing (#456).
          TreinoFadeSlideIn(
            delay: AppMotion.stagger(5),
            child: const ExcludeSemantics(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Flexible(child: _MoodEmoji('😞')),
                  Flexible(child: _MoodEmoji('😕')),
                  Flexible(child: _MoodEmoji('😐')),
                  Flexible(child: _MoodEmoji('🙂')),
                  Flexible(child: _MoodEmoji('😄')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 40),

          // LISTO button (filled)
          FilledButton(
            onPressed: isSharing ? null : () => context.go('/workout'),
            child: Text(l10n.workoutButtonDone),
          ),
          const SizedBox(height: 12),

          // COMPARTIR button (outlined) — disabled with spinner while sharing
          OutlinedButton(
            onPressed: isSharing ? null : onShare,
            child: isSharing
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: palette.accent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(l10n.commonLoading),
                    ],
                  )
                : Text(l10n.workoutButtonShare),
          ),
        ],
      ),
    );
  }
}

// ── Async slots ───────────────────────────────────────────────────────────────
// Cada slot es un hijo fijo del Column que renderiza SizedBox.shrink hasta que
// su data llega; el contenido monta con su propia entrada TreinoFadeSlideIn y
// lleva su spacing adentro (así "ausente" no deja huecos).

class _RecognitionSlot extends StatelessWidget {
  const _RecognitionSlot({required this.highlights});

  final SessionHighlights? highlights;

  @override
  Widget build(BuildContext context) {
    final highlights = this.highlights;
    if (highlights == null ||
        highlights.recognition.kind == SessionRecognitionKind.none) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TreinoFadeSlideIn(
        distance: AppMotion.slideSm,
        child: SessionRecognitionBanner(recognition: highlights.recognition),
      ),
    );
  }
}

class _DistributionSlot extends StatelessWidget {
  const _DistributionSlot({required this.distribution});

  final SessionMuscleDistribution? distribution;

  @override
  Widget build(BuildContext context) {
    final distribution = this.distribution;
    if (distribution == null || distribution.setsByAxis.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: TreinoFadeSlideIn(
        child: SessionMuscleDistributionSection(distribution: distribution),
      ),
    );
  }
}

class _PrsSlot extends StatelessWidget {
  const _PrsSlot({required this.session, required this.highlights});

  final Session session;
  final SessionHighlights? highlights;

  @override
  Widget build(BuildContext context) {
    final highlights = this.highlights;
    // Sin sets no hay nada que contar, y una sesión que no cuenta como
    // entreno (#372) no reclama PRs — misma regla que Insights.
    if (highlights == null ||
        highlights.exercises.isEmpty ||
        !session.countsAsWorkout) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: TreinoFadeSlideIn(
        child: SessionPrsSection(highlights: highlights),
      ),
    );
  }
}

class _ExercisesSlot extends StatelessWidget {
  const _ExercisesSlot({required this.highlights});

  final SessionHighlights? highlights;

  @override
  Widget build(BuildContext context) {
    final highlights = this.highlights;
    if (highlights == null || highlights.exercises.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: TreinoFadeSlideIn(
        child: SessionExercisesSection(exercises: highlights.exercises),
      ),
    );
  }
}

// ── Mood emoji ────────────────────────────────────────────────────────────────

class _MoodEmoji extends StatelessWidget {
  const _MoodEmoji(this.emoji);

  final String emoji;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        emoji,
        // #456: on the iOS simulator (iPhone 16e / iOS 26.3) these glyphs can
        // render as tofu "?" — the theme's Barlow families carry no emoji and
        // the automatic platform fallback doesn't kick in there (likely an
        // engine/Impeller simulator issue). The explicit fallback pins the
        // system emoji font; physical-device verification is still pending.
        style: const TextStyle(
          fontSize: 28,
          fontFamilyFallback: ['Apple Color Emoji'],
        ),
      ),
    );
  }
}

// ── Not-found state ───────────────────────────────────────────────────────────

class _NotFoundState extends StatelessWidget {
  const _NotFoundState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.workoutNotFoundTitle),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => context.go('/workout'),
            child: Text(l10n.workoutButtonBackToWorkout),
          ),
        ],
      ),
    );
  }
}

// ── Error state ───────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.workoutErrorTitle),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onRetry,
            child: Text(l10n.workoutButtonRetry),
          ),
        ],
      ),
    );
  }
}
