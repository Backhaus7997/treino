// CoachDiscoveryPreviewCard — columna derecha de PerfilPublicoScreen
// (Fase 11, WU-02).
//
// "Así te ven los alumnos potenciales en TREINO Coach Discovery" — el norte
// visual del mockup (docs/web-trainer/screens/perfil-publico/). Data 100%
// real:
///  - identidad/bio/specialty/rate/online → llegan como prop (`profile`),
///    mismo `UserProfile` que alimenta el bloque de edición (ADR-F11-01).
///  - rating/reseñas → `trainerByIdProvider(uid)` (CF-written, ADR-RV-005).
///  - alumnos activos → `trainerLinksStreamProvider`, mismo conteo que
///    `DashboardKpiStrip` (solo `status == active`).
//
// Sin años/experiencia — no cableado a ningún dato real (fantasía del
// mockup, ADR-F11-01). Botón "Solicitar contacto" queda deshabilitado: es
// un preview de cómo lo ve un alumno, no un flujo real desde el hub.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/widgets/motion/treino_shimmer.dart';
import 'package:treino/core/widgets/motion/treino_state_switcher.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach/application/trainer_discovery_providers.dart'
    show trainerByIdProvider;
import 'package:treino/features/coach/application/trainer_link_providers.dart'
    show trainerLinksStreamProvider;
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach/domain/trainer_public_profile.dart';
import 'package:treino/features/coach/domain/trainer_specialty.dart';
import 'package:treino/features/coach/presentation/widgets/trainer_specialty_chips.dart'
    show SpecialtyLabels;
import 'package:treino/features/feed/presentation/widgets/post_avatar.dart';
import 'package:treino/features/profile/domain/user_profile.dart';

const double _bannerHeight = 56;
const double _avatarSize = 64;

/// Card "PREVIEW EN TREINO COACH DISCOVERY" — WU-02.
class CoachDiscoveryPreviewCard extends ConsumerWidget {
  const CoachDiscoveryPreviewCard({super.key, required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final trainerAsync = ref.watch(trainerByIdProvider(profile.uid));
    final linksAsync = ref.watch(trainerLinksStreamProvider);

    final alumnosCount = linksAsync.valueOrNull
            ?.where((l) => l.status == TrainerLinkStatus.active)
            .length ??
        0;

    final specialtyLabel = _specialtyLabelOf(profile.trainerSpecialty);
    final modalidad = _modalidadOf(profile);
    final rate = profile.trainerMonthlyRate;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PREVIEW EN TREINO COACH DISCOVERY', // i18n: Fase 11
          style: TextStyle(
            fontFamily: AppFonts.barlowCondensed,
            fontWeight: AppFonts.w700,
            fontSize: 12,
            letterSpacing: 0.5,
            color: palette.textMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            decoration: BoxDecoration(
              color: palette.bgCard,
              border: Border.all(color: palette.border),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      height: _bannerHeight,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [palette.accent, palette.highlight],
                        ),
                      ),
                    ),
                    Positioned(
                      left: AppSpacing.s18,
                      top: _bannerHeight - (_avatarSize / 2),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: palette.bgCard, width: 3),
                        ),
                        child: PostAvatar(
                          authorDisplayName: profile.displayName ?? '',
                          authorAvatarUrl: profile.avatarUrl,
                          size: _avatarSize,
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.s18,
                    AppSpacing.s18,
                    AppSpacing.s18,
                    AppSpacing.s18,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              profile.displayName ?? '—',
                              key: const Key('coach_discovery_display_name'),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: AppFonts.barlowCondensed,
                                fontWeight: AppFonts.w700,
                                fontSize: 20,
                                color: palette.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.hairline),
                          Icon(
                            TreinoIcon.verified,
                            size: 16,
                            color: palette.accent,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.hairline),
                      Text(
                        specialtyLabel != null
                            ? 'Personal Trainer · $specialtyLabel' // i18n: Fase 11
                            : 'Personal Trainer', // i18n: Fase 11
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 13,
                        ),
                      ),
                      if (modalidad != null) ...[
                        const SizedBox(height: AppSpacing.hairline),
                        Row(
                          children: [
                            Icon(
                              TreinoIcon.mapPin,
                              size: 14,
                              color: palette.textMuted,
                            ),
                            const SizedBox(width: AppSpacing.hairline),
                            Text(
                              modalidad,
                              style: TextStyle(
                                color: palette.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: AppSpacing.s18),
                      Row(
                        children: [
                          Expanded(
                            child: _StatItem(
                              label: 'ALUMNOS', // i18n: Fase 11
                              value: alumnosCount.toString(),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: TreinoStateSwitcher(
                              childKey: ValueKey(
                                'coach_discovery_rating_state_'
                                '${_ratingStateKeyOf(trainerAsync)}',
                              ),
                              child: _RatingReviewsBlock(
                                trainerAsync: trainerAsync,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (specialtyLabel != null) ...[
                        const SizedBox(height: AppSpacing.s18),
                        Text(
                          'ESPECIALIDAD', // i18n: Fase 11
                          style: TextStyle(
                            fontFamily: AppFonts.barlow,
                            fontWeight: AppFonts.w600,
                            fontSize: 11,
                            letterSpacing: 0.5,
                            color: palette.textMuted,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.hairline),
                        _SpecialtyChip(label: specialtyLabel),
                      ],
                      if (rate != null) ...[
                        const SizedBox(height: AppSpacing.s18),
                        Text(
                          'PLANES DESDE', // i18n: Fase 11
                          style: TextStyle(
                            fontFamily: AppFonts.barlow,
                            fontWeight: AppFonts.w600,
                            fontSize: 11,
                            letterSpacing: 0.5,
                            color: palette.textMuted,
                          ),
                        ),
                        Text(
                          '\$$rate/mes', // i18n: Fase 11
                          style: TextStyle(
                            fontFamily: AppFonts.barlowCondensed,
                            fontWeight: AppFonts.w700,
                            fontSize: 20,
                            color: palette.textPrimary,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.s18),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: palette.accent,
                            disabledBackgroundColor:
                                palette.accent.withValues(alpha: 0.4),
                            foregroundColor: palette.bg,
                            disabledForegroundColor:
                                palette.bg.withValues(alpha: 0.7),
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.s12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                          ),
                          child: const Text(
                            'Solicitar contacto', // i18n: Fase 11
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Devuelve el label en español de la especialidad, con fallback a la
/// capitalización cruda del string si no matchea el enum fijo de 10
/// valores (D13).
String? _specialtyLabelOf(String? wireValue) {
  if (wireValue == null || wireValue.trim().isEmpty) return null;
  final parsed = trainerSpecialtyFromString(wireValue);
  if (parsed != null) return SpecialtyLabels.of(parsed);
  final trimmed = wireValue.trim();
  return trimmed[0].toUpperCase() + trimmed.substring(1);
}

/// Resumen de modalidad: "Online", "Presencial", "Online + Presencial", o
/// `null` si no hay ninguna cableada.
String? _modalidadOf(UserProfile profile) {
  final parts = <String>[
    if (profile.trainerOffersOnline) 'Online', // i18n: Fase 11
    if (profile.trainerLocations.isNotEmpty) 'Presencial', // i18n: Fase 11
  ];
  return parts.isEmpty ? null : parts.join(' + ');
}

String _ratingStateKeyOf(AsyncValue<Object?> value) {
  if (value.hasError) return 'error';
  if (value.isLoading && !value.hasValue) return 'loading';
  return 'data';
}

/// Bloque RATING + RESEÑAS — envuelve el `.when()` de [trainerByIdProvider]
/// (ADR-RV-011: "—" si `reviewCount == 0` o `averageRating == null`).
class _RatingReviewsBlock extends StatelessWidget {
  const _RatingReviewsBlock({required this.trainerAsync});

  final AsyncValue<TrainerPublicProfile?> trainerAsync;

  @override
  Widget build(BuildContext context) {
    return trainerAsync.when(
      loading: () => const Row(
        children: [
          Expanded(
            child: TreinoShimmer(
              child: _StatItem(label: 'RATING', value: '—'), // i18n: Fase 11
            ),
          ),
          Expanded(
            child: TreinoShimmer(
              child: _StatItem(label: 'RESEÑAS', value: '—'), // i18n: Fase 11
            ),
          ),
        ],
      ),
      error: (_, __) => const Row(
        children: [
          Expanded(child: _StatItem(label: 'RATING', value: '—')),
          Expanded(child: _StatItem(label: 'RESEÑAS', value: '—')),
        ],
      ),
      data: (t) {
        final reviewCount = t?.reviewCount ?? 0;
        final hasRating = reviewCount > 0 && t?.averageRating != null;
        final ratingValue =
            hasRating ? t!.averageRating!.toStringAsFixed(1) : '—';
        final reviewsValue = reviewCount > 0 ? reviewCount.toString() : '—';
        return Row(
          children: [
            Expanded(
              child: _StatItem(
                label: 'RATING', // i18n: Fase 11
                value: ratingValue,
                icon: TreinoIcon.starFill,
              ),
            ),
            Expanded(
              child: _StatItem(
                label: 'RESEÑAS', // i18n: Fase 11
                value: reviewsValue,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value, this.icon});

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: palette.accent),
              const SizedBox(width: AppSpacing.hairline),
            ],
            Text(
              value,
              style: TextStyle(
                fontFamily: AppFonts.barlowCondensed,
                fontWeight: AppFonts.w700,
                fontSize: 16,
                color: palette.textPrimary,
              ),
            ),
          ],
        ),
        Text(
          label,
          style: TextStyle(
            fontFamily: AppFonts.barlow,
            fontWeight: AppFonts.w600,
            fontSize: 10,
            letterSpacing: 0.5,
            color: palette.textMuted,
          ),
        ),
      ],
    );
  }
}

class _SpecialtyChip extends StatelessWidget {
  const _SpecialtyChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.hairline,
      ),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: palette.accent.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppFonts.barlow,
          fontWeight: AppFonts.w600,
          fontSize: 12,
          color: palette.accent,
        ),
      ),
    );
  }
}
