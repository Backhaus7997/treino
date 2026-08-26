import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_background.dart';
import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/tokens/tokens.dart';
import '../../../core/utils/kg_format.dart';
import '../../../core/widgets/motion/treino_fade_slide_in.dart';
import '../../../core/widgets/motion/treino_state_switcher.dart';
import '../../../core/widgets/treino_icon.dart';
import '../application/exercise_feedback_providers.dart';
import '../application/session_providers.dart';
import '../domain/exercise_feedback.dart';
import '../domain/session.dart';
import '../domain/set_log.dart';
import 'utils/date_helpers.dart';
import 'widgets/feedback_load_error_note.dart';
import 'widgets/session_exercise_block.dart';
import 'widgets/session_stats_card.dart';
import 'widgets/stat_tile.dart';
import '../../../l10n/app_l10n.dart';

class SessionDetailScreen extends ConsumerWidget {
  const SessionDetailScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUidProvider) ?? '';
    final summaryAsync = ref.watch(
      sessionSummaryProvider((uid: uid, sessionId: sessionId)),
    );
    // #628 — el alumno tiene que poder releer lo que él mismo reportó: si sólo
    // lo ve el PF, la persona no tiene registro de lo que dijo que le pasó.
    // Va la variante de dueño (`uid` propio), no la del PF, y se watchea
    // aparte de la sesión a propósito: un fallo leyendo reportes degrada a
    // "sin reportes" y NO tumba el detalle, igual que en las dos superficies
    // del PF — pero se AVISA, también igual que en las dos del PF. Que la
    // persona relea "no reporté nada" cuando en realidad no se pudo leer es el
    // mismo silencio, sólo que del lado del que escribió.
    final feedbackAsync = ref.watch(
      sessionExerciseFeedbackProvider((uid: uid, sessionId: sessionId)),
    );
    final feedback = feedbackAsync.valueOrNull ?? const <ExerciseFeedback>[];
    final feedbackFailed = feedbackAsync.hasError;

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: TreinoStateSwitcher(
            childKey: ValueKey(summaryAsync.when(
              loading: () => 'loading',
              error: (_, __) => 'error',
              data: (data) => data.session == null ? 'notfound' : 'data',
            )),
            child: summaryAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _DetailError(
                onRetry: () => ref.invalidate(
                  sessionSummaryProvider((uid: uid, sessionId: sessionId)),
                ),
              ),
              data: (data) {
                final session = data.session;
                if (session == null) {
                  return const _DetailNotFound();
                }
                return _DetailLoaded(
                  session: session,
                  setLogs: data.setLogs,
                  feedback: feedback,
                  feedbackFailed: feedbackFailed,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ── Loaded body ───────────────────────────────────────────────────────────────

class _DetailLoaded extends StatelessWidget {
  const _DetailLoaded({
    required this.session,
    required this.setLogs,
    this.feedback = const <ExerciseFeedback>[],
    this.feedbackFailed = false,
  });

  final Session session;
  final List<SetLog> setLogs;

  /// Lo que el alumno reportó en esta sesión (#628). Ya filtrado por sesión;
  /// el reparto por ejercicio y por serie lo hace [SessionExerciseBlock].
  final List<ExerciseFeedback> feedback;

  /// `true` cuando la lectura de [feedback] falló y la lista vacía de arriba
  /// NO significa "no reportó nada". Se renderiza como aviso propio, arriba de
  /// los bloques: la sesión se sigue viendo entera.
  final bool feedbackFailed;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    // #628 — se agrupa por `exerciseId` y no por `exerciseName` como antes:
    // los reportes se anclan al id, así que sin él no hay forma de pegarle a
    // cada bloque lo suyo. De paso deja de fusionar dos ejercicios distintos
    // que casualmente compartan nombre, y queda igual que las dos superficies
    // del PF. La lista incluye al final los ejercicios que SÓLO tienen
    // reportes (serie pendiente, miembro de superset, serie borrada).
    // Indexado para el stagger de abajo — lista eager (no builder), así que
    // TreinoFadeSlideIn es seguro (docs/design-system.md).
    final groupedList =
        buildSessionExerciseGroups(sets: setLogs, feedback: feedback);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Back button — top-left
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon: Icon(TreinoIcon.back, color: palette.textPrimary),
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go('/workout'),
            ),
          ),
          const SizedBox(height: 8),

          // Header: date + time + routineName. startedAt is a real instant
          // (UTC via TimestampConverter) — convert to the viewer's local time
          // before formatting, or it reads +3h in Argentina (#380).
          TreinoFadeSlideIn(
            child: Column(
              children: [
                Text(
                  formatSessionDate(session.startedAt.toLocal()),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: palette.textMuted,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatTime(session.startedAt.toLocal()),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: palette.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  session.routineName,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w800,
                    fontSize: 28,
                    color: palette.textPrimary,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 4 stats agrupadas en una tarjeta 2×2.
          TreinoFadeSlideIn(
            delay: AppMotion.stagger(1),
            child: SessionStatsCard(
              tiles: [
                StatTile(
                  icon: TreinoIcon.clock,
                  label: l10n.workoutDetailStatDurationMin,
                  value: session.durationMin.toString(),
                ),
                StatTile(
                  icon: TreinoIcon.statSets,
                  label: l10n.workoutDetailStatSets,
                  value: setLogs.length.toString(),
                ),
                StatTile(
                  icon: TreinoIcon.dumbbell,
                  label: l10n.workoutDetailStatVolumeKg,
                  value: formatVolumeKg(session.totalVolumeKg),
                ),
                StatTile(
                  icon: TreinoIcon.statPr,
                  label: l10n.workoutDetailStatPrsToday,
                  value: l10n.workoutStatPrsTodayStub,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // El aviso de reportes ilegibles va antes de los bloques y también
          // cuando la sesión quedó vacía: son dos hechos distintos.
          if (feedbackFailed) ...[
            FeedbackLoadErrorNote(message: l10n.sessionFeedbackLoadError),
            const SizedBox(height: AppSpacing.s8),
          ],

          // Exercise blocks — or empty state when no sets were logged.
          if (groupedList.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                l10n.sessionDetailNoSets,
                textAlign: TextAlign.center,
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: palette.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
            )
          else
            ...groupedList.asMap().entries.map(
                  (indexed) => TreinoFadeSlideIn(
                    delay: AppMotion.stagger(indexed.key + 2),
                    child: SessionExerciseBlock(
                      exerciseName: indexed.value.exerciseName,
                      sets: indexed.value.sets,
                      feedback: indexed.value.feedback,
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

// ── Not-found state ───────────────────────────────────────────────────────────

class _DetailNotFound extends StatelessWidget {
  const _DetailNotFound();

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

class _DetailError extends StatelessWidget {
  const _DetailError({required this.onRetry});
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

// ── Time helper ───────────────────────────────────────────────────────────────

String _formatTime(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
