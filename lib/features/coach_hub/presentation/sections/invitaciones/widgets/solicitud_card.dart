// SolicitudCard — tarjeta presentational de una solicitud (WU-03, Fase 4).
//
// Sigue el patrón de `_PendingRequestTile` (dashboard_pending.dart) pero SIN
// acceso a repo: expone callbacks `onAccept`/`onDecline` — el caller
// (InvitacionesScreen, WU-04) es responsable de invocar
// `trainerLinkRepositoryProvider.accept/decline` y de manejar el estado
// `busy`/snackbars/analytics. Esto la deja reutilizable (el dashboard podría
// adoptarla luego, plan-fase4.md §2 "segundo copy-paste del tile").
//
// Estados (mutuamente excluyentes):
// - `busy == true` → spinner, sin importar `status`.
// - `status == pending && !busy` → botones Aceptar/Rechazar del kit
//   (TreinoInteractiveState — NO ElevatedButton/TextButton core).
// - cualquier otro `status` → pill de estado read-only (historial,
//   ADR-F4-02: Aceptadas/Rechazadas no tienen acciones de gestión).
//
// Reusa `TrainerLinkStatus` (no un enum propio) — la tarjeta es 1:1 con el
// vínculo real. Keys preservadas para tests/evidencia:
// `solicitud_card_{id}` / `accept_{id}` / `decline_{id}`.
library;

import 'package:flutter/material.dart';

import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/components/treino_card_tokens.dart';
import 'package:treino/app/theme/tokens/components/treino_focus_tokens.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/widgets/treino_interactive_state.dart';
import 'package:treino/features/feed/presentation/widgets/post_avatar.dart';
import 'package:treino/l10n/app_l10n.dart';

class SolicitudCard extends StatelessWidget {
  const SolicitudCard({
    super.key,
    required this.id,
    required this.displayName,
    this.avatarUrl,
    required this.requestedAt,
    required this.status,
    this.busy = false,
    this.onAccept,
    this.onDecline,
  });

  /// Id del [TrainerLink] — sufijo de las keys de test/evidencia.
  final String id;

  /// Nombre a mostrar — `userPublicProfileProvider(athleteId).displayName`.
  final String displayName;

  /// Avatar opcional — `userPublicProfileProvider(athleteId).avatarUrl`.
  final String? avatarUrl;

  /// Momento en que se creó la solicitud — `TrainerLink.requestedAt`.
  final DateTime requestedAt;

  /// Estado real del vínculo — determina si se muestran acciones o pill.
  final TrainerLinkStatus status;

  /// `true` mientras el caller espera la respuesta de accept/decline —
  /// reemplaza los botones por un spinner (patrón dashboard).
  final bool busy;

  /// Callback de "Aceptar". `null` = deshabilitado (TreinoInteractiveState).
  final VoidCallback? onAccept;

  /// Callback de "Rechazar". `null` = deshabilitado (TreinoInteractiveState).
  final VoidCallback? onDecline;

  bool get _isPending => status == TrainerLinkStatus.pending;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return Container(
      key: Key('solicitud_card_$id'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s14,
        vertical: AppSpacing.s12,
      ),
      decoration: BoxDecoration(
        color: TreinoCardTokens.background(context),
        borderRadius: BorderRadius.circular(TreinoCardTokens.borderRadius),
        border: Border.all(color: TreinoCardTokens.border(context)),
      ),
      child: Row(
        children: [
          Semantics(
            image: true,
            label: l10n.a11yAvatarLabel(displayName),
            child: PostAvatar(
              authorDisplayName: displayName,
              authorAvatarUrl: avatarUrl,
              size: 40,
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayName,
                  style: TextStyle(
                    fontFamily: AppFonts.barlow,
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.hairline),
                Text(
                  _relativeTime(requestedAt),
                  style: TextStyle(
                    fontFamily: AppFonts.barlow,
                    color: palette.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          if (busy)
            Semantics(
              label: l10n.commonProcessing,
              liveRegion: true,
              child: SizedBox(
                key: Key('solicitud_busy_$id'),
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: palette.accent,
                ),
              ),
            )
          else if (_isPending)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SolicitudActionButton(
                  actionKey: Key('decline_$id'),
                  label: l10n.coachHubActionReject,
                  color: palette.textMuted,
                  onTap: onDecline,
                ),
                const SizedBox(width: AppSpacing.hairline),
                _SolicitudActionButton(
                  actionKey: Key('accept_$id'),
                  label: l10n.coachHubActionAccept,
                  color: palette.accent,
                  foregroundColor: palette.bg,
                  filled: true,
                  onTap: onAccept,
                ),
              ],
            )
          else
            _StatusPill(status: status, palette: palette),
        ],
      ),
    );
  }
}

/// Botón de acción de [SolicitudCard] (Aceptar/Rechazar). Estado de
/// interacción vía [TreinoInteractiveState] (fuente única de verdad,
/// ADR-SH-002) — NO usa ElevatedButton/TextButton core (ADR-F4-06).
class _SolicitudActionButton extends StatelessWidget {
  const _SolicitudActionButton({
    required this.actionKey,
    required this.label,
    required this.color,
    required this.onTap,
    this.filled = false,
    this.foregroundColor,
  });

  final Key actionKey;
  final String label;
  final Color color;
  final Color? foregroundColor;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final focusTokens = TreinoFocusTokens.of(context);

    return TreinoInteractiveState(
      onTap: onTap,
      builder: (ctx, states) {
        final highlighted = states.hovered || states.pressed;

        Color? bg;
        if (filled) {
          bg = color;
        } else if (highlighted) {
          bg = color.withValues(alpha: 0.08);
        }

        final fg = filled ? (foregroundColor ?? color) : color;

        return Container(
          key: actionKey,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s12,
            vertical: AppSpacing.s8,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius:
                BorderRadius.circular(filled ? AppRadius.full : AppRadius.sm),
            border: states.focused
                ? Border.all(
                    color: focusTokens.ring,
                    width: TreinoFocusTokens.ringWidth,
                  )
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: AppFonts.barlow,
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: fg,
            ),
          ),
        );
      },
    );
  }
}

/// Pill de estado read-only para solicitudes ya resueltas (Aceptadas/
/// Rechazadas, ADR-F4-02) — sin acciones, solo informativa.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, required this.palette});

  final TrainerLinkStatus status;
  final AppPalette palette;

  (String, Color) _labelAndColor() => switch (status) {
        TrainerLinkStatus.pending => ('PENDIENTE', palette.warning),
        TrainerLinkStatus.active => ('ACEPTADA', palette.accent),
        TrainerLinkStatus.paused => ('PAUSADA', palette.warning),
        TrainerLinkStatus.terminated => ('RECHAZADA', palette.danger),
      }; // i18n: Fase 4 — literales de estado, sin key l10n dedicada (ADR-F4-05).

  @override
  Widget build(BuildContext context) {
    final (label, color) = _labelAndColor();

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.hairline - 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppFonts.barlow,
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Tiempo relativo desde [createdAt] — mismo formato que `post_card.dart`
/// (`_relativeTime`), duplicado intencional: es un helper privado trivial de
/// una línea por rama, no un widget (la regla "segundo copy-paste = extraer
/// componente" del plan aplica a widgets del kit, no a este tipo de helper).
String _relativeTime(DateTime createdAt) {
  final delta = DateTime.now().difference(createdAt);
  if (delta.inMinutes < 1) return 'recién';
  if (delta.inHours < 1) return 'hace ${delta.inMinutes}m';
  if (delta.inDays < 1) return 'hace ${delta.inHours}h';
  if (delta.inDays < 7) return 'hace ${delta.inDays}d';
  final d = createdAt.day.toString().padLeft(2, '0');
  final m = createdAt.month.toString().padLeft(2, '0');
  return '$d/$m';
}
