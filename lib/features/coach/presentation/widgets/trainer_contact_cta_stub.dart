import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/analytics/analytics_service.dart';
import '../../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../../application/trainer_discovery_providers.dart';
import '../../application/trainer_link_providers.dart';
import '../../domain/trainer_link.dart';
import '../../domain/trainer_link_status.dart';
import '../../../../l10n/app_l10n.dart';

/// CTA "PEDIR VÍNCULO" en el TrainerPublicProfile. Crea un doc en
/// `trainer_links` con status pending. Disabled si el athlete ya tiene
/// un vínculo (active o pending) con cualquier PF — un athlete puede
/// vincularse con un solo PF a la vez en MVP.
///
/// Cambio de Etapa 3 (Fase 5): antes era stub que solo mostraba
/// "próximamente". Mantenemos el nombre de la clase + archivo para no
/// romper imports del resto del feature (rename queda como cleanup
/// futuro).
class TrainerContactCtaStub extends ConsumerStatefulWidget {
  const TrainerContactCtaStub({super.key, required this.trainerId});

  /// uid del PF a quien se le pide el vínculo.
  final String trainerId;

  @override
  ConsumerState<TrainerContactCtaStub> createState() =>
      _TrainerContactCtaStubState();
}

class _TrainerContactCtaStubState extends ConsumerState<TrainerContactCtaStub> {
  bool _submitting = false;

  Future<void> _onPressed() async {
    if (_submitting) return;
    final athleteId = ref.read(currentUidProvider);
    if (athleteId == null) return;
    if (athleteId == widget.trainerId) return; // defensivo

    setState(() => _submitting = true);
    try {
      await ref
          .read(trainerLinkRepositoryProvider)
          .request(trainerId: widget.trainerId, athleteId: athleteId);
      ref.read(analyticsServiceProvider).logLinkRequested(
            trainerId: widget.trainerId,
            athleteId: athleteId,
          );
      ref.invalidate(currentAthleteLinkProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Solicitud enviada. Te avisamos cuando el PF responda.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No pudimos enviar la solicitud: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final linkAsync = ref.watch(currentAthleteLinkProvider);

    // Disabled si: ya hay vínculo en pending/active, está submitting, o
    // el provider todavía no resolvió.
    final existingLink = linkAsync.valueOrNull;
    final hasActiveOrPending = existingLink != null &&
        (existingLink.status == TrainerLinkStatus.pending ||
            existingLink.status == TrainerLinkStatus.active);
    final disabled = _submitting || !linkAsync.hasValue || hasActiveOrPending;

    // El atleta está bloqueado porque ya tiene un vínculo con OTRO PF: no
    // dejamos un botón disabled sin explicación. Mostramos una línea de ayuda
    // debajo del botón con el motivo y a quién terminar el vínculo (constraint
    // de un único PF activo a la vez en MVP).
    final blockedByOtherTrainer =
        hasActiveOrPending && existingLink.trainerId != widget.trainerId;

    final label = hasActiveOrPending
        ? _existingLinkLabel(existingLink)
        : l10n.coachCtaLabel;

    final button = OutlinedButton(
      onPressed: disabled ? null : _onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.accent,
        side: BorderSide(
          color: disabled ? palette.border : palette.accent,
        ),
        disabledForegroundColor: palette.textMuted,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
      ),
      child: _submitting
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: palette.accent,
              ),
            )
          : Text(
              label,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                letterSpacing: 1.5,
              ),
            ),
    );

    if (!blockedByOtherTrainer) return button;

    // Resolvemos el nombre del PF vinculado actual para la línea de ayuda.
    // Si todavía no resolvió, usamos un placeholder neutro en lugar del id.
    final currentTrainerAsync =
        ref.watch(trainerByIdProvider(existingLink.trainerId));
    final currentTrainerName =
        currentTrainerAsync.valueOrNull?.displayName?.trim();
    final trainerName =
        (currentTrainerName == null || currentTrainerName.isEmpty)
            ? l10n.athleteCoachViewTrainerFallbackName
            : currentTrainerName;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        button,
        const SizedBox(height: 8),
        Semantics(
          liveRegion: true,
          child: Text(
            l10n.trainerCtaExistingLinkExplanation(trainerName),
            textAlign: TextAlign.center,
            style: GoogleFonts.barlow(
              fontSize: 13,
              color: palette.textMuted,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  String _existingLinkLabel(TrainerLink link) {
    if (link.trainerId == widget.trainerId) {
      return link.status == TrainerLinkStatus.pending
          ? 'SOLICITUD PENDIENTE'
          : 'TU PERSONAL TRAINER';
    }
    return 'YA TENÉS UN PF';
  }
}
