import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/widgets/motion/treino_shimmer.dart';
import 'package:treino/core/widgets/motion/treino_state_switcher.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/set_log.dart';

/// Tarjeta con el desglose por ejercicio de la última sesión del alumno —
/// Fase 3 WU-05 (extraído de `_UltimaSessionCard`, `alumno_detail_screen.dart`,
/// ADR-A3-04).
///
/// Reutiliza [coachSessionSetLogsProvider] — el mismo que usa
/// `_SetLogsExpansion`. Incluye el mismo manejo de permission-denied (alumno
/// no compartió historial). Opcionalmente muestra badge "+N kg" usando
/// [lastWeightByExerciseProvider].
///
/// `TreinoStateSwitcher` cross-fadea entre loading (sesiones aún cargando) /
/// error / vacío / data — con un segundo switcher anidado para el sub-estado
/// de `setLogs` (el desglose por ejercicio puede tardar más que la lista de
/// sesiones misma).
class UltimaSessionCard extends ConsumerWidget {
  const UltimaSessionCard({
    super.key,
    required this.palette,
    required this.athleteId,
    required this.sessionsAsync,
  });

  final AppPalette palette;
  final String athleteId;
  final AsyncValue<List<Session>> sessionsAsync;

  Widget _box(Widget child) => Container(
        padding: const EdgeInsets.all(AppSpacing.s14),
        decoration: BoxDecoration(
          color: palette.bgCard,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: child,
      );

  Widget _skeleton() => _box(
        TreinoShimmer(
          child: Column(
            key: const Key('ultima_sesion_skeleton'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 140,
                height: 14,
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: AppSpacing.s12),
              for (var i = 0; i < 3; i++) ...[
                Container(
                  height: 12,
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: AppSpacing.s8),
              ],
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String stateKey;
    final Widget content;

    // Las sesiones dependen de `session_shares`, que el CF borra cuando el
    // link no está `active` (p.ej. pausado) → ahí la lista da
    // permission-denied. Eso NO es un fallo real: significa que el alumno no
    // está compartiendo su historial ahora. Lo decimos explícitamente en vez
    // de un engañoso «sin sesiones registradas» (que implicaría que nunca
    // entrenó).
    if (sessionsAsync.isLoading && !sessionsAsync.hasValue) {
      stateKey = 'loading';
      content = _skeleton();
    } else if (sessionsAsync.hasError) {
      stateKey = 'error';
      final e = sessionsAsync.error;
      final noShare = e is FirebaseException && e.code == 'permission-denied';
      content = _box(Text(
        noShare
            ? 'El alumno no compartió su historial.' // i18n: Fase W2
            : 'No se pudo cargar la última sesión.', // i18n: Fase W2
        style: TextStyle(color: palette.textMuted, fontSize: 13),
      ));
    } else {
      final sessions = sessionsAsync.valueOrNull ?? const <Session>[];
      if (sessions.isEmpty) {
        stateKey = 'empty';
        content = _box(Text(
          'Sin sesiones registradas.', // i18n: Fase W2
          style: TextStyle(color: palette.textMuted, fontSize: 13),
        ));
      } else {
        stateKey = 'data';
        final lastSession = sessions.first;
        final logsAsync = ref.watch(coachSessionSetLogsProvider(
            (athleteUid: athleteId, sessionId: lastSession.id)));
        final lastWeightAsync =
            ref.watch(lastWeightByExerciseProvider(athleteId));
        final muted = TextStyle(color: palette.textMuted, fontSize: 12);

        content = _box(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                lastSession.routineName, // i18n: Fase W2
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.s8),
              TreinoStateSwitcher(
                childKey:
                    ValueKey('ultima_sesion_logs_${_logsStateKey(logsAsync)}'),
                child: logsAsync.when(
                  loading: () => Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.s8),
                    child: TreinoShimmer(
                      child: Container(
                        key: const Key('ultima_sesion_logs_skeleton'),
                        height: 36,
                        decoration: BoxDecoration(
                          color: palette.border,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
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
                      groups
                          .putIfAbsent(log.exerciseId, () => <SetLog>[])
                          .add(log);
                    }
                    final lastWeight = lastWeightAsync.valueOrNull;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final entry in groups.entries)
                          _UltimaEjercicioRow(
                            palette: palette,
                            logs: entry.value,
                            progressionKg: lastWeight?[entry.key],
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      }
    }

    return TreinoStateSwitcher(
      childKey: ValueKey('ultima_sesion_$stateKey'),
      child: content,
    );
  }

  String _logsStateKey(AsyncValue<Object?> value) {
    if (value.hasError) return 'error';
    if (value.isLoading && !value.hasValue) return 'loading';
    return 'data';
  }
}

/// Fila de un ejercicio en [UltimaSessionCard]: nombre + nro de sets +
/// badge opcional "+N kg" de progresión.
class _UltimaEjercicioRow extends StatelessWidget {
  const _UltimaEjercicioRow({
    required this.palette,
    required this.logs,
    this.progressionKg,
  });

  final AppPalette palette;
  final List<SetLog> logs;
  final double? progressionKg;

  @override
  Widget build(BuildContext context) {
    final name = logs.first.exerciseName;
    final sets = logs.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s8 - 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          Text(
            '$sets × sets', // i18n: Fase W2
            style: TextStyle(color: palette.textMuted, fontSize: 12),
          ),
          if (progressionKg != null) ...[
            const SizedBox(width: AppSpacing.hairline + 2),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.hairline + 2,
                  vertical: AppSpacing.hairline - 2),
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${progressionKg! >= 0 ? '+' : ''}${progressionKg!.toStringAsFixed(1)} kg',
                style: TextStyle(
                  color: palette.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
