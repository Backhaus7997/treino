import 'package:flutter/material.dart';

import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/payment_format.dart'
    show fmtDate, kMesesLargos;
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';

/// Timeline del tab «Historial» del alumno detail — Fase 3 WU-07b.
///
/// Agrupa TODAS las sesiones (`sessionsByUidProvider`, sin filtro) por mes
/// calendario, más nuevas arriba — anatomía del mockup `historial.png`
/// (header de mes CAPS + bullets con dot mint).
///
/// ADR-A3-01 (honestidad de datos): el mockup muestra hitos narrativos
/// ("Renovó plan Premium", "Subió 12 fotos de comida") que esta app NO
/// trackea como eventos — no hay fuente real. Cada bullet acá es un HECHO
/// real derivado de `Session` (fecha, rutina, duración, volumen, estado);
/// el conteo "Asistió N veces" del mes es un agregado real (`sessions.length`
/// del grupo), no un dato inventado. *Rechazado*: fabricar tipos de evento
/// (PR, renovación, fotos) sin backing store — violaría la norma "todo real"
/// que ya rige el resto de Fase 3.
class HistorialTimeline extends StatelessWidget {
  const HistorialTimeline({
    super.key,
    required this.sessions,
    required this.palette,
  });

  /// Sesiones ya ordenadas más nuevas primero (orden del provider).
  final List<Session> sessions;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final groups = _groupByMonth(sessions);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < groups.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.s20),
          _MonthHeader(label: groups[i].label, palette: palette),
          const SizedBox(height: AppSpacing.s8),
          Text(
            groups[i].sessions.length == 1
                ? 'Asistió 1 vez' // i18n: Fase W2
                : 'Asistió ${groups[i].sessions.length} veces', // i18n
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.s8 + 2),
          for (final s in groups[i].sessions)
            _SessionBullet(session: s, palette: palette),
        ],
      ],
    );
  }

  static List<_MonthGroup> _groupByMonth(List<Session> sessions) {
    final byKey = <String, _MonthGroup>{};
    final order = <String>[];
    for (final s in sessions) {
      final d = s.finishedAt ?? s.startedAt;
      final key = '${d.year}-${d.month}';
      if (!byKey.containsKey(key)) {
        order.add(key);
        byKey[key] = _MonthGroup(
          label: '${kMesesLargos[d.month].toUpperCase()} ${d.year}', // i18n
          sessions: [],
        );
      }
      byKey[key]!.sessions.add(s);
    }
    return [for (final key in order) byKey[key]!];
  }
}

class _MonthGroup {
  _MonthGroup({required this.label, required this.sessions});
  final String label;
  final List<Session> sessions;
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.label, required this.palette});

  final String label;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontFamily: AppFonts.barlowCondensed,
        fontWeight: FontWeight.w700,
        fontSize: 16,
        letterSpacing: 0.5,
        color: palette.textPrimary,
      ),
    );
  }
}

/// Un hecho real del historial: dot mint + fecha + rutina + estado +
/// duración/volumen. Reusa el mismo criterio de estado que
/// `HistorialSesionesTable` (Entrenamientos), sin depender de esa tabla —
/// acá la anatomía es timeline, no tabla (ADR-A3-02 no aplica: no es una
/// segunda `CoachHubDataTable`, es un paradigma visual distinto pedido por
/// el mockup).
class _SessionBullet extends StatelessWidget {
  const _SessionBullet({required this.session, required this.palette});

  final Session session;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusColor) = _statusFor(session, palette);
    final date = fmtDate(session.finishedAt ?? session.startedAt);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: palette.accent,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.hairline,
              children: [
                Text(date,
                    style: TextStyle(color: palette.textMuted, fontSize: 12)),
                Text(
                  session.routineName,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                _StatusPill(label: statusLabel, color: statusColor),
                Text(
                  '${session.durationMin} min · ${session.totalVolumeKg.round()} kg', // i18n
                  style: TextStyle(color: palette.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// `active` → «EN CURSO»; `wasFullyCompleted` → «COMPLETA»; si no,
  /// «INCOMPLETA» (el alumno abandonó la sesión).
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s8, vertical: AppSpacing.hairline - 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: color.withValues(alpha: 0.5)),
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
}
