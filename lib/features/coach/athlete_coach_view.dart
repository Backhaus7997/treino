import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_palette.dart';
import '../../core/widgets/treino_icon.dart';
import '../profile/application/user_public_profile_providers.dart';
import '../profile/domain/user_public_profile.dart';
import 'application/trainer_link_providers.dart';
import 'domain/trainer_link.dart';
import 'domain/trainer_link_status.dart';
import 'presentation/trainers_list_screen.dart';

/// Tab Coach del atleta. Combina la discovery (Dev A, Etapa 2) con el
/// estado del vínculo (Etapa 3):
/// - Sin vínculo → renderiza `TrainersListScreen` para que el atleta
///   busque y elija PF. Es el entry natural al flow de Discovery.
/// - status pending → card "esperando confirmación" + botón cancelar.
/// - status active → card con info del PF + botón terminar vínculo.
class AthleteCoachView extends ConsumerWidget {
  const AthleteCoachView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final linkAsync = ref.watch(currentAthleteLinkProvider);

    return linkAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: palette.accent),
      ),
      error: (_, __) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'No pudimos cargar tu vínculo.',
            style: GoogleFonts.barlow(fontSize: 14, color: palette.textMuted),
            textAlign: TextAlign.center,
          ),
        ),
      ),
      data: (link) {
        // Sin vínculo → el athlete ve la discovery directamente (entry
        // natural al flow de elegir PF). El botón "PEDIR VÍNCULO" vive
        // dentro de TrainerPublicProfile y al disparar request crea el
        // doc en `trainer_links`; al volver a esta tab, linkAsync emite
        // pending y mostramos la card.
        if (link == null) return const TrainersListScreen();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _LinkStateCard(link: link),
        );
      },
    );
  }
}

// ── Link state card — pending o active ────────────────────────────────────────

class _LinkStateCard extends ConsumerWidget {
  const _LinkStateCard({required this.link});
  final TrainerLink link;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final pubAsync = ref.watch(userPublicProfileProvider(link.trainerId));

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 20),
      physics: const ClampingScrollPhysics(),
      children: [
        Container(
          decoration: BoxDecoration(
            color: palette.bgCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: palette.border, width: 1),
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _statusLabel(link.status),
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 1.2,
                  color: link.status == TrainerLinkStatus.active
                      ? palette.accent
                      : palette.textMuted,
                ),
              ),
              const SizedBox(height: 14),
              _TrainerHeader(pubAsync: pubAsync, link: link),
              const SizedBox(height: 18),
              _ActionRow(link: link),
            ],
          ),
        ),
      ],
    );
  }

  String _statusLabel(TrainerLinkStatus s) => switch (s) {
        TrainerLinkStatus.pending => 'SOLICITUD ENVIADA',
        TrainerLinkStatus.active => 'TU PERSONAL TRAINER',
        TrainerLinkStatus.paused => 'VÍNCULO PAUSADO',
        TrainerLinkStatus.terminated => 'VÍNCULO TERMINADO',
      };
}

class _TrainerHeader extends StatelessWidget {
  const _TrainerHeader({required this.pubAsync, required this.link});
  final AsyncValue<UserPublicProfile?> pubAsync;
  final TrainerLink link;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final name = pubAsync.valueOrNull?.displayName ?? '...';
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: palette.bg,
            border: Border.all(color: palette.border, width: 1),
          ),
          alignment: Alignment.center,
          child:
              Icon(TreinoIcon.tabProfile, size: 28, color: palette.textMuted),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: GoogleFonts.barlow(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: palette.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                link.status == TrainerLinkStatus.pending
                    ? 'Esperando confirmación'
                    : 'Vinculado desde ${_formatDate(link.acceptedAt ?? link.requestedAt)}',
                style: GoogleFonts.barlow(
                  fontWeight: FontWeight.w400,
                  fontSize: 12,
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    final d = dt.toLocal();
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }
}

class _ActionRow extends ConsumerWidget {
  const _ActionRow({required this.link});
  final TrainerLink link;

  Future<void> _onCancel(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirm(
      context,
      'Cancelar solicitud',
      '¿Seguro que querés cancelar tu solicitud de vínculo? Vas a poder hacer otra después.',
    );
    if (!confirmed) return;
    await ref.read(trainerLinkRepositoryProvider).cancel(link.id);
    ref.invalidate(currentAthleteLinkProvider);
  }

  Future<void> _onTerminate(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirm(
      context,
      'Terminar vínculo',
      '¿Seguro que querés terminar tu vínculo con este Personal Trainer? Podés volver a pedirle vínculo más adelante.',
    );
    if (!confirmed) return;
    await ref
        .read(trainerLinkRepositoryProvider)
        .terminate(link.id, reason: 'athlete-terminated');
    ref.invalidate(currentAthleteLinkProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    if (link.status == TrainerLinkStatus.pending) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: () => _onCancel(context, ref),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: palette.highlight, width: 1),
            foregroundColor: palette.highlight,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9999),
            ),
          ),
          child: Text(
            'CANCELAR SOLICITUD',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              letterSpacing: 0.8,
            ),
          ),
        ),
      );
    }
    if (link.status == TrainerLinkStatus.active) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: () => _onTerminate(context, ref),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: palette.highlight, width: 1),
            foregroundColor: palette.highlight,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9999),
            ),
          ),
          child: Text(
            'TERMINAR VÍNCULO',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              letterSpacing: 0.8,
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

Future<bool> _confirm(BuildContext context, String title, String body) async {
  final palette = AppPalette.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: palette.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        title,
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: palette.textPrimary,
        ),
      ),
      content: Text(
        body,
        style: GoogleFonts.barlow(fontSize: 14, color: palette.textPrimary),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(
            'Cancelar',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: palette.textPrimary,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: palette.highlight,
            foregroundColor: palette.bg,
          ),
          child: Text(
            'Confirmar',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}
