// PerfilPublicoScreen — sección «Perfil público» del Coach Hub web
// (Fase 11, WU-01).
//
// Versión MÍNIMA pre-rediseño (ADR-F11-01): muestra en texto plano los
// campos del PF logueado que alimentan su ficha pública en TREINO Coach
// Discovery (displayName, bio, especialidad, tarifa, modalidad). Es el
// baseline "before" de la fase — WU-02..05 agregan el editor tokenizado + el
// preview de Coach Discovery reales.
//
// Sigue el patrón de screens de sección (nutricion_screen.dart,
// alumnos_screen.dart): `ConsumerWidget` sin `Scaffold` (ADR-CHW-005),
// renderiza dentro de `CoachHubScaffold`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/theme/app_motion.dart';
import '../../../../../app/theme/app_palette.dart';
import '../../../../../app/theme/tokens/primitives.dart';
import '../../../../../core/widgets/motion/treino_fade_slide_in.dart';
import '../../../../../core/widgets/motion/treino_shimmer.dart';
import '../../../../../core/widgets/motion/treino_state_switcher.dart';
import '../../../../../core/widgets/treino_icon.dart';
import '../../../../profile/application/user_providers.dart';
import '../../../../profile/domain/user_profile.dart';
import '../../widgets/coach_hub_widgets.dart';
import 'widgets/coach_discovery_preview_card.dart';
import 'widgets/identidad_card.dart';

/// Pantalla «Perfil público» (`/perfil-publico`) — Fase 11 WU-01.
class PerfilPublicoScreen extends ConsumerWidget {
  const PerfilPublicoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final profileAsync = ref.watch(userProfileProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s20,
        vertical: AppSpacing.s20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TreinoFadeSlideIn(
            delay: AppMotion.stagger(0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const TreinoSectionHeader(
                  title: 'Perfil público', // i18n: Fase 11
                ),
                const SizedBox(height: AppSpacing.hairline),
                Text(
                  'Así te ven los alumnos potenciales en TREINO Coach '
                  'Discovery.', // i18n: Fase 11
                  style: TextStyle(color: palette.textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s18),
          TreinoStateSwitcher(
            childKey:
                ValueKey('perfil_publico_state_${_stateKeyOf(profileAsync)}'),
            child: profileAsync.when(
              loading: () => const _PerfilPublicoLoading(),
              error: (_, __) => TreinoEmptyState(
                key: const Key('perfil_publico_error'),
                icon: TreinoIcon.errorState,
                title: 'No pudimos cargar tu perfil público.', // i18n: Fase 11
                ctaLabel: 'Reintentar', // i18n: Fase 11
                onCtaTap: () => ref.invalidate(userProfileProvider),
              ),
              data: (profile) => profile == null
                  ? const TreinoEmptyState(
                      key: Key('perfil_publico_empty'),
                      icon: TreinoIcon.emptyState,
                      title: 'No encontramos tu perfil.', // i18n: Fase 11
                    )
                  : _PerfilPublicoDosColumnas(profile: profile),
            ),
          ),
        ],
      ),
    );
  }
}

String _stateKeyOf(AsyncValue<Object?> value) {
  if (value.hasError) return 'error';
  if (value.isLoading && !value.hasValue) return 'loading';
  return 'data';
}

/// Skeleton de carga — shimmer sobre el bloque de datos plano.
class _PerfilPublicoLoading extends StatelessWidget {
  const _PerfilPublicoLoading();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      key: const Key('perfil_publico_loading'),
      padding: const EdgeInsets.all(AppSpacing.s18),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: TreinoShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < 5; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.s12),
              Container(
                width: i.isEven ? 220.0 : 320.0,
                height: 14,
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Layout de dos columnas — WU-02: izquierda edición (bloque plano
/// pre-rediseño, WU-03/04 lo reemplaza por el editor tokenizado), derecha
/// `CoachDiscoveryPreviewCard` (el norte visual real del mockup).
class _PerfilPublicoDosColumnas extends StatelessWidget {
  const _PerfilPublicoDosColumnas({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              IdentidadCard(profile: profile),
              const SizedBox(height: AppSpacing.s18),
              _PerfilPublicoPlano(profile: profile),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.s18),
        SizedBox(
          width: 320,
          child: CoachDiscoveryPreviewCard(profile: profile),
        ),
      ],
    );
  }
}

/// Bloque de datos en texto plano — versión pre-rediseño (baseline BEFORE).
class _PerfilPublicoPlano extends StatelessWidget {
  const _PerfilPublicoPlano({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final bio = profile.trainerBio?.trim();
    final specialty = profile.trainerSpecialty?.trim();
    final rate = profile.trainerMonthlyRate;

    return Container(
      key: const Key('perfil_publico_plano'),
      padding: const EdgeInsets.all(AppSpacing.s18),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            profile.displayName ?? '—',
            key: const Key('perfil_publico_display_name'),
            style: TextStyle(
              fontFamily: AppFonts.barlowCondensed,
              fontWeight: AppFonts.w700,
              fontSize: 20,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.s14),
          _Field(
            key: const Key('perfil_publico_bio'),
            label: 'Bio', // i18n: Fase 11
            value: (bio != null && bio.isNotEmpty)
                ? bio
                : 'Todavía no cargaste una bio.', // i18n: Fase 11
          ),
          _Field(
            key: const Key('perfil_publico_specialty'),
            label: 'Especialidad', // i18n: Fase 11
            value: (specialty != null && specialty.isNotEmpty)
                ? specialty
                : 'Sin especialidad cargada.', // i18n: Fase 11
          ),
          _Field(
            key: const Key('perfil_publico_rate'),
            label: 'Tarifa mensual', // i18n: Fase 11
            value: rate != null
                ? '\$$rate/mes'
                : 'Sin tarifa cargada.', // i18n: Fase 11
          ),
          _Field(
            key: const Key('perfil_publico_offers_online'),
            label: 'Modalidad', // i18n: Fase 11
            value: profile.trainerOffersOnline
                ? 'Ofrece online' // i18n: Fase 11
                : 'Solo presencial', // i18n: Fase 11
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontFamily: AppFonts.barlow,
              fontWeight: AppFonts.w600,
              fontSize: 11,
              letterSpacing: 0.5,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.hairline),
          Text(
            value,
            style: TextStyle(color: palette.textPrimary, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
