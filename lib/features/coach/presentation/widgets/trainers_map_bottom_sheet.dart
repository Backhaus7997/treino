import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../feed/presentation/widgets/post_avatar.dart';
import '../../application/trainer_discovery_providers.dart';
import '../../domain/trainer_public_profile.dart';
import '../../domain/trainer_specialty.dart';
import '../coach_strings.dart';

/// Bottom sheet con carousel horizontal de trainer cards.
///
/// Se overlaya sobre el bottom del `TrainersMapView` (Stack child). Lee
/// del mismo `trainerDiscoveryProvider` que los markers — solo muestra
/// trainers con lat/lon set (los que tienen pin en el mapa).
///
/// Sin drag real por ahora — el handle visual sugiere la affordance pero
/// la altura es fija (~190px). Si producto valida que se usa, agregamos
/// `DraggableScrollableSheet` con snap points en una iteración futura.
class TrainersMapBottomSheet extends ConsumerWidget {
  const TrainersMapBottomSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final discoveryAsync = ref.watch(trainerDiscoveryProvider);
    // Sin ubicación del athlete, la palabra "CERCA" pierde sentido — no
    // podemos saber qué tan cerca está cada PF. Cambiamos el label.
    // Scoped: solo rebuild en cambios reales del Position.
    final hasLocation = ref.watch(
          athleteLocationProvider.select((s) => s.valueOrNull),
        ) !=
        null;

    return discoveryAsync.when(
      // Mientras carga el provider no renderizamos sheet — el mapa solo.
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (trainers) {
        // El sheet muestra PFs con AL MENOS UNA ubicación física efectiva
        // (gym o custom). Los virtuales puros no aparecen acá — no tienen
        // pin que pueda asociarse al card.
        //
        // El modo "Online" no se chequea: cuando el atleta lo activa, el
        // screen padre hace auto-switch a LISTA y el toggle MAPA queda
        // disabled, así que este sheet nunca se rendera con virtualOnly ON.
        final visible =
            trainers.where((t) => effectiveLocationsOf(t).isNotEmpty).toList();

        return Container(
          decoration: BoxDecoration(
            color: palette.bgCard,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            border: Border(top: BorderSide(color: palette.border)),
            boxShadow: [
              BoxShadow(
                color: palette.bg.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Drag handle visual ────────────────────────────────────────
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // ── Header: count ─────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _Header(
                  count: visible.length,
                  hasLocation: hasLocation,
                ),
              ),
              const SizedBox(height: 12),
              // ── Carousel ──────────────────────────────────────────────────
              SizedBox(
                height: 110,
                child: visible.isEmpty
                    ? _EmptyState(palette: palette)
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (_, i) =>
                            _TrainerMapCard(trainer: visible[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Header ───────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.count, required this.hasLocation});
  final int count;

  /// Si el athlete tiene ubicación, el label incluye "CERCA" (proximidad
  /// tiene sentido). Sin ubicación, solo "ENTRENADORES" (no podemos saber
  /// qué tan cerca está cada PF).
  final bool hasLocation;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final singular = count == 1;
    final String label;
    if (hasLocation) {
      label = singular ? 'ENTRENADOR CERCA' : 'ENTRENADORES CERCA';
    } else {
      label = singular ? 'ENTRENADOR' : 'ENTRENADORES';
    }
    return Text(
      '$count $label',
      style: GoogleFonts.barlowCondensed(
        fontWeight: FontWeight.w700,
        fontSize: 13,
        letterSpacing: 1.2,
        color: palette.textPrimary,
      ),
    );
  }
}

// ── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          'Sin entrenadores con ubicación en esta zona.',
          textAlign: TextAlign.center,
          style: GoogleFonts.barlow(
            fontSize: 13,
            color: palette.textMuted,
          ),
        ),
      ),
    );
  }
}

// ── Trainer card — usada en el carousel ──────────────────────────────────────

class _TrainerMapCard extends StatelessWidget {
  const _TrainerMapCard({required this.trainer});
  final TrainerPublicProfile trainer;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final specialty = trainer.trainerSpecialty;
    final rate = trainer.trainerMonthlyRate;

    return InkWell(
      onTap: () => context.go('/coach/trainer/${trainer.uid}'),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: palette.bg,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PostAvatar(
                  authorDisplayName: trainer.displayName ?? '',
                  authorAvatarUrl: trainer.avatarUrl,
                  size: 44,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trainer.displayName ?? '',
                        style: GoogleFonts.barlowCondensed(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          letterSpacing: 0.4,
                          color: palette.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (specialty != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          TrainerSpecialtyX.toWire(specialty),
                          style: GoogleFonts.barlow(
                            fontSize: 12,
                            color: palette.textMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const Spacer(),
            if (rate != null)
              Text(
                '\$$rate${CoachStrings.monthlyRateUnit}',
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: palette.highlight,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
