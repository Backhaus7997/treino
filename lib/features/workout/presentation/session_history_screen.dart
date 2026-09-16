import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_background.dart';
import '../../../app/theme/app_palette.dart';
import '../../../core/utils/kg_format.dart';
import '../../../core/widgets/motion/treino_state_switcher.dart';
import '../../../core/widgets/motion/treino_tappable.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../../app/theme/tokens/tokens.dart';
import '../application/session_providers.dart';
import '../domain/exercise_feedback.dart';
import '../domain/session.dart';
import '../domain/session_status.dart';
import 'utils/date_helpers.dart';

/// Lista completa y sin tope de entrenamientos, en dos modos.
///
/// **Dueño** (`coachAthleteId == null`) — las sesiones terminadas y completas
/// del usuario logueado. Destino top-level (fuera del ShellRoute) al que se
/// llega por el "Ver todo" de [HistorialSection]; la sección inline de la tab
/// ENTRENAR corta en 5 y ésta es la entrada de primera clase al historial.
///
/// **PF** (`coachAthleteId != null`) — las de ESE alumno, **todas**: también
/// las en curso y las que quedaron incompletas. Se llega por el "Ver todo" de
/// la ficha del alumno, y cada fila abre
/// `/coach/athlete/:athleteId/session/:sessionId`.
///
/// Qué entra en cada modo está en [_visibles], y no es un detalle de
/// presentación: es el motivo por el que existe el modo PF.
///
/// Scaffold + [AppBackground] + botón de volver propios, igual que
/// [SessionDetailScreen].
class SessionHistoryScreen extends ConsumerWidget {
  const SessionHistoryScreen({super.key, this.coachAthleteId});

  /// Cuando NO es null, el que mira es el PF y el historial es de este alumno.
  /// Mismo contrato que [SessionDetailScreen.coachAthleteId].
  ///
  /// Cambia TRES cosas, y la del medio es la que motivó la pantalla:
  ///  1. de quién es el historial,
  ///  2. **qué sesiones entran** — ver [_visibles],
  ///  3. a dónde lleva cada fila y a dónde vuelve el back.
  final String? coachAthleteId;

  bool get _esVistaDelPf => coachAthleteId != null;

  /// Qué sesiones ve cada uno.
  ///
  /// El ALUMNO ve sólo las terminadas y completas: es su registro de lo hecho,
  /// y una sesión a medias no es un entrenamiento. Ese filtro no se toca.
  ///
  /// El PF las ve TODAS, y no es una preferencia: es el bug. Hoy las sesiones
  /// en curso e incompletas no aparecen en NINGUNA superficie del PF —
  /// `recent_activity_provider.dart:88` descarta `finishedAt == null`, y el
  /// `_isCompleted` de la ficha del alumno además exige `wasFullyCompleted`.
  /// O sea que un alumno que reporta una molestia, abandona a mitad y deja la
  /// sesión colgada genera un push sobre un dolor cuyo registro el PF no puede
  /// encontrar por ningún camino. La sesión se cierra sola como incompleta y
  /// queda invisible PARA SIEMPRE, no "hasta que termine".
  List<Session> _visibles(List<Session> todas) => _esVistaDelPf
      ? todas
      : todas
          .where(
              (s) => s.status == SessionStatus.finished && s.wasFullyCompleted)
          .toList();

  String get _rutaDeVuelta =>
      _esVistaDelPf ? '/coach/athlete/$coachAthleteId' : '/workout';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final currentUid = ref.watch(currentUidProvider) ?? '';
    final uid = coachAthleteId ?? currentUid;
    final sessionsAsync = ref.watch(sessionsByUidProvider(uid));

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: l10n.commonBack,
                      icon: Icon(TreinoIcon.back,
                          size: 20, color: palette.textPrimary),
                      onPressed: () => context.canPop()
                          ? context.pop()
                          : context.go(_rutaDeVuelta),
                    ),
                    const SizedBox(width: 6),
                    Semantics(
                      header: true,
                      child: Text(
                        l10n.workoutHistorialFullTitle,
                        style: GoogleFonts.barlowCondensed(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          letterSpacing: 1.0,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: TreinoStateSwitcher(
                  childKey: ValueKey(sessionsAsync.when(
                    loading: () => 'loading',
                    error: (_, __) => 'error',
                    data: (all) => _visibles(all).isEmpty ? 'empty' : 'data',
                  )),
                  child: sessionsAsync.when(
                    loading: () => Center(
                      child: CircularProgressIndicator(color: palette.accent),
                    ),
                    error: (_, __) => _ErrorState(
                      onRetry: () => ref.invalidate(sessionsByUidProvider(uid)),
                    ),
                    data: (all) {
                      final visibles = _visibles(all);
                      if (visibles.isEmpty) {
                        return _EmptyState(coachAthleteId: coachAthleteId);
                      }
                      // El fetch corta en `kSessionHistoryFetchLimit` y hasta
                      // acá lo hacía EN SILENCIO. Para el alumno prolífico (o
                      // para el PF que mira su historial) la lista simplemente
                      // terminaba, y una lista que termina afirma que eso es
                      // todo — o sea que el corte mentía sobre el pasado del
                      // usuario sin decir una palabra.
                      //
                      // El arreglo de fondo es paginar detrás de un cursor, y
                      // el dartdoc del propio límite ya lo tiene anotado como
                      // follow-up. Mientras tanto el tope se DECLARA: el repo
                      // ya eligió este camino en el selector de períodos de los
                      // gráficos, donde no ofrece un «todo» porque con 365 de
                      // tope «sería mentira».
                      //
                      // La comparación es contra `all` y no contra `visibles`:
                      // el tope lo aplica el fetch, antes de que `_visibles`
                      // filtre. Mirando la lista ya filtrada, el modo ALUMNO
                      // —que descarta las incompletas— nunca llegaría al número
                      // y el aviso no saldría jamás.
                      final llegoAlTope =
                          all.length >= kSessionHistoryFetchLimit;
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: visibles.length + (llegoAlTope ? 1 : 0),
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: palette.textMuted.withValues(alpha: 0.12),
                        ),
                        itemBuilder: (_, i) {
                          if (i == visibles.length) {
                            return const _TopeAlcanzado();
                          }
                          return _HistoryCard(
                            session: visibles[i],
                            coachAthleteId: coachAthleteId,
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pie que avisa que la lista pudo haber quedado cortada por el tope del fetch.
///
/// Sin él, la lista termina y punto, y una lista que termina afirma «esto es
/// todo» — el criterio de AGENTS.md §11.1 del lado de la UI.
///
/// **Pero el texto NO afirma que haya más atrás, y eso es deliberado.** Llegar
/// al tope no lo prueba: un usuario con exactamente `kSessionHistoryFetchLimit`
/// sesiones cumple la condición y no tiene ni una más. Probarlo de verdad
/// pediría un registro extra, y ese límite lo comparten Home, Insights y el
/// panel del PF. Tampoco puede prometer un número de filas: en modo alumno el
/// filtro de incompletas deja menos de las que se trajeron.
///
/// Así que informa sin asegurar. Un cartel que dice «hay más viejos» cuando no
/// los hay es la MISMA falla que este pie vino a tapar, sólo que en la otra
/// dirección — y de esas, AGENTS.md §11.1 dice que la peor es la que
/// tranquiliza (o promete) sin poder respaldarlo. Lo marcó Codex en el #1161.
///
/// Desaparece solo el día que el historial pagine detrás de un cursor.
class _TopeAlcanzado extends StatelessWidget {
  const _TopeAlcanzado();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s18),
      child: Text(
        AppL10n.of(context).workoutHistorialTopeAlcanzado,
        textAlign: TextAlign.center,
        style: GoogleFonts.barlow(
          // El token y no `12` crudo: el archivo ya está en la allowlist del
          // scan de tamaños, pero su ratchet cuenta OCURRENCIAS y su contrato
          // dice que la deuda total nunca crece. Pasar por la holgura del
          // techo no es lo mismo que no sumar deuda.
          fontSize: AppTextSize.caption,
          color: palette.textMuted,
        ),
      ),
    );
  }
}

// ── Card ──────────────────────────────────────────────────────────────────────

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.session, this.coachAthleteId});

  final Session session;
  final String? coachAthleteId;

  bool get _enCurso => session.finishedAt == null;
  bool get _incompleta =>
      session.finishedAt != null && !session.wasFullyCompleted;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    final l10n = AppL10n.of(context);
    // startedAt is a real UTC instant — localize before formatting (#380).
    final formattedDate = formatSessionDate(session.startedAt.toLocal());

    // El ✓ lleno ya no es incondicional. En la vista del PF entran sesiones en
    // curso e incompletas, y pintarles un "hecho" sería exactamente el defecto
    // que este archivo viene a arreglar: una pantalla que afirma más de lo que
    // sabe. Cada estado dice lo suyo.
    final (IconData icono, Color tinte) = switch (session) {
      _ when _enCurso => (TreinoIcon.play, palette.accent),
      _ when _incompleta => (TreinoIcon.checkCircleEmpty, palette.textMuted),
      _ => (TreinoIcon.checkCircleFill, palette.accent),
    };
    final estado = _enCurso
        ? l10n.coachSessionHistoryInProgress
        : _incompleta
            ? l10n.coachSessionHistoryIncomplete
            : null;

    final discomfort =
        session.feedbackCounts[ExerciseFeedbackKind.discomfort] ?? 0;
    final comments = session.feedbackCounts[ExerciseFeedbackKind.comment] ?? 0;

    return TreinoTappable(
      onTap: () => context.push(
        coachAthleteId != null
            ? '/coach/athlete/$coachAthleteId/session/${session.id}'
            : '/workout/historial/${session.id}',
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Icon(icono, color: tinte, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.routineName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    estado == null ? formattedDate : '$formattedDate · $estado',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            // Los reportes del alumno (#628), derivados de `feedbackCounts` —
            // que escribe el backend recontando. Sin esto el PF tiene que
            // entrar sesión por sesión a ver si hay algo adentro, que es el
            // problema original con otra cara.
            //
            // Mismo lenguaje visual que `ExerciseFeedbackNote`, donde el PF ya
            // los ve: molestia = warning en ámbar, nota = chat en acento. Un
            // segundo código para la misma cosa obligaría a aprender dos.
            if (discomfort > 0) ...[
              const SizedBox(width: 8),
              _MarcaDeReporte(
                icono: TreinoIcon.warning,
                color: palette.warning,
                cantidad: discomfort,
                semantica: l10n.exerciseFeedbackNoteTagDiscomfort,
              ),
            ],
            if (comments > 0) ...[
              const SizedBox(width: 8),
              _MarcaDeReporte(
                icono: TreinoIcon.chat,
                color: palette.accent,
                cantidad: comments,
                semantica: l10n.exerciseFeedbackNoteTagComment,
              ),
            ],
            const SizedBox(width: 8),
            Text(
              '${formatVolumeKg(session.totalVolumeKg)}${l10n.workoutHistorialCardKgSuffix}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${session.durationMin}${l10n.workoutHistorialCardMinSuffix}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

/// Marca de reporte en una fila del historial: ícono + cuántos.
///
/// El número importa y no es adorno: "una molestia" y "cuatro molestias en la
/// misma sesión" son dos conversaciones distintas con el alumno.
class _MarcaDeReporte extends StatelessWidget {
  const _MarcaDeReporte({
    required this.icono,
    required this.color,
    required this.cantidad,
    required this.semantica,
  });

  final IconData icono;
  final Color color;
  final int cantidad;
  final String semantica;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Una sola etiqueta para el par ícono+número: leídos por separado, el
    // lector de pantalla diría "2" suelto sin decir dos de qué.
    return Semantics(
      label: '$cantidad $semantica',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, color: color, size: 14),
          const SizedBox(width: AppSpacing.hairline),
          Text(
            '$cantidad',
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.coachAthleteId});

  final String? coachAthleteId;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    final esVistaDelPf = coachAthleteId != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              esVistaDelPf
                  ? AppL10n.of(context).coachSessionHistoryEmpty
                  : AppL10n.of(context).workoutHistorialEmptyMessage,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: palette.textMuted,
              ),
            ),
            // El CTA es "empezar a entrenar" y sólo tiene sentido para el
            // dueño: el PF no puede entrenar por su alumno. Un botón que no
            // hace lo que dice es peor que ninguno.
            if (!esVistaDelPf) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/workout'),
                child: Text(AppL10n.of(context).workoutHistorialEmptyCta),
              ),
            ],
          ],
        ),
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
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppL10n.of(context).workoutHistorialErrorMessage,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onRetry,
              child: Text(AppL10n.of(context).workoutHistorialErrorRetry),
            ),
          ],
        ),
      ),
    );
  }
}
