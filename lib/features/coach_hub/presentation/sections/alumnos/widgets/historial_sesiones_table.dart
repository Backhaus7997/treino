import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/payment_format.dart'
    show fmtDate;
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/features/workout/domain/set_log.dart';
import 'package:treino/features/workout/presentation/widgets/session_exercise_block.dart';

/// Tabla «Historial de sesiones» — Fase 3 WU-07a (extraída de
/// `_HistorialTable`/`_ExpandableSessionRow`, `alumno_detail_screen.dart`,
/// ADR-A3-04). Reusada por el tab Entrenamientos (últimas 20 completas) y el
/// tab Historial (todas, `showStatusBadge: true`) — ADR-A3-02: UNA sola
/// tabla, ahora sobre `CoachHubDataTable`.
///
/// ADR-A3-10 · expand-en-línea → panel debajo de la tabla: `CoachHubDataTable`
/// fija cada fila a `TreinoTableTokens.rowHeight` (48px, ADR-SH-003) — no hay
/// slot para contenido variable DENTRO de una fila. El expand-on-tap original
/// (sets reales por fila, `_ExpandableSessionRow`) se preserva funcionalmente
/// pero se renderiza como un panel único DEBAJO de la tabla (una sesión
/// expandida a la vez, toggle con la misma fila o con el botón cerrar). Cero
/// dato inventado — mismo provider (`coachSessionSetLogsProvider`), mismo
/// contenido (`SessionExerciseBlock` por ejercicio). *Rechazado*: extender
/// `CoachHubDataTable` con una segunda variante de fila (sobre-ingeniería del
/// kit para un único consumidor).
class HistorialSesionesTable extends StatefulWidget {
  const HistorialSesionesTable({
    super.key,
    required this.sessions,
    required this.athleteId,
    required this.palette,
    this.showStatusBadge = false,
    this.loading = false,
    this.errorMessage,
    this.onRetry,
    this.emptyMessage = 'Sin sesiones registradas todavía.', // i18n: Fase W2
  });

  final List<Session> sessions;
  final String athleteId;
  final AppPalette palette;

  /// Si `true`, la celda «Sesión» antepone un badge de estado (Completa /
  /// Incompleta / En curso). Usado por el tab Historial; el tab
  /// Entrenamientos ya filtra a sesiones completas y no lo necesita.
  final bool showStatusBadge;

  final bool loading;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final String emptyMessage;

  @override
  State<HistorialSesionesTable> createState() => _HistorialSesionesTableState();
}

class _HistorialSesionesTableState extends State<HistorialSesionesTable> {
  String? _sortColumnKey;
  bool _sortAscending = true;
  String? _expandedSessionId;

  List<Session> _sorted() {
    final list = List<Session>.from(widget.sessions);
    final key = _sortColumnKey;
    if (key == null) return list;

    int cmp(Session a, Session b) {
      switch (key) {
        case 'fecha':
          return (a.finishedAt ?? a.startedAt)
              .compareTo(b.finishedAt ?? b.startedAt);
        case 'sesion':
          return a.routineName
              .toLowerCase()
              .compareTo(b.routineName.toLowerCase());
        case 'duracion':
          return a.durationMin.compareTo(b.durationMin);
        case 'volumen':
          return a.totalVolumeKg.compareTo(b.totalVolumeKg);
        default:
          return 0;
      }
    }

    list.sort(_sortAscending ? cmp : (a, b) => cmp(b, a));
    return list;
  }

  String _fechaFor(Session s) {
    if (s.finishedAt != null) return fmtDate(s.finishedAt!);
    // La sesión sigue activa (sin finishedAt): Historial cae a startedAt
    // para mostrar CUÁNDO arrancó; Entrenamientos ya filtra a completas y
    // sólo llega acá por un fixture raro — se mantiene el '—' original.
    return widget.showStatusBadge ? fmtDate(s.startedAt) : '—';
  }

  CoachHubRow _rowFor(Session s) {
    final palette = widget.palette;
    final textStyle = TextStyle(
      fontFamily: AppFonts.barlow,
      fontSize: 14,
      color: palette.textPrimary,
    );
    return CoachHubRow(
      id: s.id,
      cells: {
        'fecha': _fechaFor(s),
        'sesion': s.routineName,
        'duracion': '${s.durationMin} min', // i18n: Fase W2
        'volumen': '${s.totalVolumeKg.round()} kg', // i18n: Fase W2
      },
      cellWidgets: {
        if (widget.showStatusBadge)
          'sesion': Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SessionStatusPill(session: s, palette: palette),
              const SizedBox(width: AppSpacing.s8),
              Flexible(
                child: Text(s.routineName,
                    overflow: TextOverflow.ellipsis, style: textStyle),
              ),
            ],
          ),
        'volumen': Align(
          alignment: Alignment.centerRight,
          child:
              Text('${s.totalVolumeKg.round()} kg', style: textStyle), // i18n
        ),
        'chevron': Icon(
          _expandedSessionId == s.id
              ? TreinoIcon.chevronUp
              : TreinoIcon.chevronDown,
          size: 16,
          color: palette.textMuted,
        ),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _sorted();
    final expandedSession = widget.loading || widget.errorMessage != null
        ? null
        : sorted.where((s) => s.id == _expandedSessionId).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CoachHubDataTable(
          columns: const [
            CoachHubColumn(
                key: 'fecha', label: 'FECHA', sortable: true, flex: 3), // i18n
            CoachHubColumn(
                key: 'sesion',
                label: 'SESIÓN',
                sortable: true,
                flex: 4), // i18n
            CoachHubColumn(
                key: 'duracion',
                label: 'DURACIÓN',
                sortable: true,
                flex: 2), // i18n
            CoachHubColumn(
                key: 'volumen',
                label: 'VOLUMEN',
                sortable: true,
                flex: 2), // i18n
            CoachHubColumn(key: 'chevron', label: ''),
          ],
          rows: [for (final s in sorted) _rowFor(s)],
          loading: widget.loading,
          errorMessage: widget.errorMessage,
          onRetry: widget.onRetry,
          emptyMessage: widget.emptyMessage,
          sortColumnKey: _sortColumnKey,
          sortAscending: _sortAscending,
          onSort: (key, ascending) => setState(() {
            _sortColumnKey = key;
            _sortAscending = ascending;
          }),
          onRowTap: (id) => setState(() {
            _expandedSessionId = _expandedSessionId == id ? null : id;
          }),
        ),
        if (expandedSession != null) ...[
          const SizedBox(height: AppSpacing.s12),
          _SetLogsExpansionPanel(
            athleteId: widget.athleteId,
            session: expandedSession,
            palette: widget.palette,
            onClose: () => setState(() => _expandedSessionId = null),
          ),
        ],
      ],
    );
  }
}

/// Small pill/badge rendering the session's completion status: verde
/// «Completa», amarillo «Incompleta», naranja «En curso». Used inside the
/// Historial tab's session rows to distinguish state at a glance.
class _SessionStatusPill extends StatelessWidget {
  const _SessionStatusPill({required this.session, required this.palette});

  final Session session;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final (label, color) = _statusFor(session, palette);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s8, vertical: AppSpacing.hairline - 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  /// Returns (label, color) for the session's current state.
  /// - `active` → «En curso» (rare in Historial but we show it if we see it).
  /// - `finished + wasFullyCompleted` → «Completa».
  /// - `finished + !wasFullyCompleted` → «Incompleta» (athlete abandoned).
  static (String, Color) _statusFor(Session s, AppPalette palette) {
    if (s.status == SessionStatus.active) {
      return ('EN CURSO', palette.warning); // i18n: Fase W2
    }
    if (s.wasFullyCompleted) {
      return ('COMPLETA', palette.accent); // i18n: Fase W2
    }
    return ('INCOMPLETA', palette.danger); // i18n: Fase W2
  }
}

/// Panel único (una sesión a la vez) con el detalle REAL de sets por
/// ejercicio de la sesión seleccionada en [HistorialSesionesTable]
/// (ADR-A3-10). Reusa `coachSessionSetLogsProvider` — mismo mapeo de
/// `permission-denied` a mensaje amigable que el `_SetLogsExpansion`
/// original.
class _SetLogsExpansionPanel extends ConsumerWidget {
  const _SetLogsExpansionPanel({
    required this.athleteId,
    required this.session,
    required this.palette,
    required this.onClose,
  });

  final String athleteId;
  final Session session;
  final AppPalette palette;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(coachSessionSetLogsProvider(
        (athleteUid: athleteId, sessionId: session.id)));
    final muted = TextStyle(color: palette.textMuted, fontSize: 12);
    return Container(
      key: Key('historial_expansion_${session.id}'),
      padding: const EdgeInsets.all(AppSpacing.s14),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  session.routineName,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              IconButton(
                icon:
                    Icon(TreinoIcon.close, size: 16, color: palette.textMuted),
                onPressed: onClose,
                tooltip: 'Cerrar', // i18n: Fase W2
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          async.when(
            loading: () => Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: palette.accent),
              ),
            ),
            error: (e, _) {
              final noShare =
                  e is FirebaseException && e.code == 'permission-denied';
              return Text(
                noShare
                    ? 'El alumno no compartió su historial.' // i18n: Fase W2
                    : 'No se pudo cargar el detalle de la sesión.', // i18n: Fase W2
                style: muted,
              );
            },
            data: (logs) {
              if (logs.isEmpty) {
                return Text(
                    'Sin series registradas en esta sesión.', // i18n: Fase W2
                    style: muted);
              }
              final groups = <String, List<SetLog>>{};
              for (final log in logs) {
                groups.putIfAbsent(log.exerciseId, () => <SetLog>[]).add(log);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final entry in groups.entries)
                    SessionExerciseBlock(
                      exerciseName: entry.value.first.exerciseName,
                      sets: entry.value,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
