import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../feed/presentation/widgets/post_avatar.dart';
import '../../application/trainer_discovery_providers.dart';
import '../../domain/trainer_public_profile.dart';
import '../../domain/trainer_specialty.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../coach_hub/presentation/sections/pagos/widgets/payment_format.dart'
    show fmtArs;

/// Bottom sheet draggable estilo Google Maps / Uber para la vista MAPA de
/// Discovery.
///
/// Usa [DraggableScrollableSheet] con snap en 3 alturas:
///   - colapsado  ~12 %  → solo handle + count
///   - medio      ~30 %  → header + algunos cards visibles
///   - expandido  ~85 %  → lista completa scrolleable
///
/// El parent ([TrainersMapView]) provee el [DraggableScrollableController]
/// para leer la fracción actual y posicionar el FAB.
///
/// El padding inferior suma `MediaQuery.paddingOf(context).bottom` para que
/// el contenido nunca quede tapado por la navbar flotante del shell.
class TrainersMapBottomSheet extends ConsumerWidget {
  const TrainersMapBottomSheet({
    super.key,
    required this.controller,
  });

  /// Controller externo — el parent lo usa para leer la fracción actual del
  /// sheet y calcular el offset del FAB.
  final DraggableScrollableController controller;

  // ── Snap points ────────────────────────────────────────────────────────────
  // Piso a 0.22 (no 0.12): a 0.12 el panel bajaba tanto que el header
  // "X cerca" quedaba pegado a la navbar y era incómodo volver a subirlo.
  static const double minChildSize = 0.22;
  static const double initialChildSize = 0.30;
  static const double maxChildSize = 0.85;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final discoveryAsync = ref.watch(trainerDiscoveryProvider);
    final hasLocation = ref.watch(
          athleteLocationProvider.select((s) => s.valueOrNull),
        ) !=
        null;

    return discoveryAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (trainers) {
        final visible =
            trainers.where((t) => effectiveLocationsOf(t).isNotEmpty).toList();

        return DraggableScrollableSheet(
          controller: controller,
          initialChildSize: initialChildSize,
          minChildSize: minChildSize,
          maxChildSize: maxChildSize,
          snap: true,
          snapSizes: const [minChildSize, initialChildSize, maxChildSize],
          expand: false,
          builder: (context, scrollController) {
            final bottomPad = MediaQuery.paddingOf(context).bottom;
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
              clipBehavior: Clip.hardEdge,
              child: CustomScrollView(
                controller: scrollController,
                slivers: [
                  // ── Handle + header ─────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
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
                          _Header(
                            count: visible.length,
                            hasLocation: hasLocation,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // ── Lista vertical de coaches ────────────────────────────
                  if (visible.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyState(palette: palette),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          final isLast = i == visible.length - 1;
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _TrainerMapListTile(trainer: visible[i]),
                              if (!isLast)
                                Divider(
                                  height: 1,
                                  thickness: 1,
                                  indent: 72,
                                  endIndent: 16,
                                  color: palette.border,
                                ),
                              if (isLast) SizedBox(height: bottomPad + 8),
                            ],
                          );
                        },
                        childCount: visible.length,
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.count, required this.hasLocation});
  final int count;
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

// ── Empty state ───────────────────────────────────────────────────────────────

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

// ── Trainer list tile — formato vertical full-width ───────────────────────────
//
// No se reutiliza `TrainerListTile` del feature lista porque ese tile requiere
// `distanceKm`, `locationLabel` y `gymsById` que la vista MAPA no calcula.
// Este tile usa solo los datos disponibles en `TrainerPublicProfile`.

class _TrainerMapListTile extends StatelessWidget {
  const _TrainerMapListTile({required this.trainer});
  final TrainerPublicProfile trainer;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final specialty = trainer.trainerSpecialty;
    final rate = trainer.trainerMonthlyRate;

    return InkWell(
      onTap: () => context.go('/coach/trainer/${trainer.uid}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            PostAvatar(
              authorDisplayName: trainer.displayName ?? '',
              authorAvatarUrl: trainer.avatarUrl,
              size: 48,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trainer.displayName ?? '',
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      letterSpacing: 0.5,
                      color: palette.textPrimary,
                    ),
                  ),
                  if (specialty != null) ...[
                    const SizedBox(height: 4),
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
            if (rate != null) ...[
              const SizedBox(width: 8),
              Text(
                '${fmtArs(rate)}${l10n.coachMonthlyRateUnit}',
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: palette.accent,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
