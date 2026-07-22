// PerfilPublicoScreen — sección «Perfil público» del Coach Hub web
// (Fase 11, WU-01..05).
//
// Muestra en dos columnas los campos del PF logueado que alimentan su ficha
// pública en TREINO Coach Discovery (displayName, bio, especialidad,
// tarifa, modalidad): izquierda = editor tokenizado (IdentidadCard +
// EspecialidadPrecioCard + bloque plano legado), derecha =
// CoachDiscoveryPreviewCard (el norte visual real del mockup).
//
// WU-05 remata la pantalla: estados completos (loading shimmer de grilla,
// error + retry, empty honesto) vía TreinoStateSwitcher, banner de perfil
// incompleto (UserProfileTrainerCompleteness), motion staggered en las
// secciones eager y layout responsive (dos columnas en desktop, apilado por
// debajo de `_kColumnsBreakpoint`).
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
import '../../../../profile/domain/user_profile_trainer_completeness.dart';
import '../../widgets/coach_hub_widgets.dart';
import 'widgets/coach_discovery_preview_card.dart';
import 'widgets/especialidad_precio_card.dart';
import 'widgets/identidad_card.dart';

/// Breakpoint interno de esta sección (WU-05): por debajo, el editor
/// (izquierda) y el preview de Coach Discovery (derecha) se apilan en una
/// sola columna. Es un umbral PROPIO de esta sección — deliberadamente
/// distinto de `kMobileBreakpoint`/`kDesktopBreakpoint` de
/// `presentation/shell/responsive.dart`, que gobiernan el ancho de VENTANA
/// completo (`CoachHubScaffold` ya oculta <768px detrás de `MobileBanner`).
/// Acá medimos el ancho disponible para el CONTENIDO de la sección —
/// siempre menor al de la ventana (descuenta sidebar + padding) — elegido
/// para que el editor conserve un ancho legible (~500px) junto al preview
/// de ancho fijo (320px) + gap.
const double _kColumnsBreakpoint = 900;

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
                  : _PerfilPublicoContent(profile: profile),
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

/// Skeleton de carga (WU-05) — imita la grilla real de dos columnas (dos
/// cards a la izquierda + una card de preview a la derecha), respetando el
/// mismo layout responsive que el estado con datos. Nada de spinner seco.
class _PerfilPublicoLoading extends StatelessWidget {
  const _PerfilPublicoLoading();

  @override
  Widget build(BuildContext context) {
    return const _PerfilPublicoLayout(
      key: Key('perfil_publico_loading'),
      left: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SkeletonCard(lines: 4),
          SizedBox(height: AppSpacing.s18),
          _SkeletonCard(lines: 3),
        ],
      ),
      right: _SkeletonCard(lines: 5, height: 260),
    );
  }
}

/// Card skeleton genérica del shimmer de carga — mismo chrome (bgCard +
/// border + radius md) que las cards reales, para que el salto
/// loading→data no "salte" de tamaño.
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.lines, this.height});

  final int lines;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      height: height,
      padding: const EdgeInsets.all(AppSpacing.s18),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: TreinoShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < lines; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.s12),
              Container(
                width: i.isEven ? 180.0 : 260.0,
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

/// Contenido con datos (WU-05): banner de perfil incompleto (si aplica) +
/// el layout de dos columnas.
class _PerfilPublicoContent extends StatelessWidget {
  const _PerfilPublicoContent({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final incomplete = !profile.trainerProfileComplete;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (incomplete) ...[
          TreinoFadeSlideIn(
            delay: AppMotion.stagger(0),
            child: const _PerfilIncompleteBanner(),
          ),
          const SizedBox(height: AppSpacing.s18),
        ],
        _PerfilPublicoDosColumnas(profile: profile),
      ],
    );
  }
}

/// Banner honesto (WU-05) — el perfil del PF no llega al mínimo para
/// aparecer en TREINO Coach Discovery (`UserProfileTrainerCompleteness`:
/// falta bio, especialidad, precio o modalidad).
class _PerfilIncompleteBanner extends StatelessWidget {
  const _PerfilIncompleteBanner();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      key: const Key('perfil_publico_incomplete_banner'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s18,
        vertical: AppSpacing.s14,
      ),
      decoration: BoxDecoration(
        color: palette.warning.withValues(alpha: 0.12),
        border: Border.all(color: palette.warning.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(TreinoIcon.warning, size: 18, color: palette.warning),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Text(
              'Tu perfil todavía no aparece en TREINO Coach Discovery: '
              'completá bio, especialidad, precio y modalidad para que '
              'los alumnos puedan encontrarte.', // i18n: Fase 11
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Layout responsive de dos columnas (WU-05): `left` flexible + `right` de
/// ancho fijo (~320px) en desktop; apilados en una sola columna
/// (`left` arriba, `right` abajo) por debajo de `_kColumnsBreakpoint` — la
/// legibilidad del editor pesa más que la del preview cuando el espacio
/// escasea, así que el editor queda primero en el orden de lectura.
class _PerfilPublicoLayout extends StatelessWidget {
  const _PerfilPublicoLayout({
    super.key,
    required this.left,
    required this.right,
  });

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= _kColumnsBreakpoint;
        if (desktop) {
          return Row(
            key: const Key('perfil_publico_columns_desktop'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              const SizedBox(width: AppSpacing.s18),
              SizedBox(width: 320, child: right),
            ],
          );
        }
        return Column(
          key: const Key('perfil_publico_columns_stacked'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [left, const SizedBox(height: AppSpacing.s18), right],
        );
      },
    );
  }
}

/// Layout de dos columnas con datos — WU-02..05: izquierda editor tokenizado
/// (`IdentidadCard` + `EspecialidadPrecioCard` + bloque plano legado),
/// derecha `CoachDiscoveryPreviewCard` (el norte visual real del mockup).
class _PerfilPublicoDosColumnas extends StatelessWidget {
  const _PerfilPublicoDosColumnas({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    return _PerfilPublicoLayout(
      left: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IdentidadCard(profile: profile),
          const SizedBox(height: AppSpacing.s18),
          EspecialidadPrecioCard(profile: profile),
          const SizedBox(height: AppSpacing.s18),
          TreinoFadeSlideIn(
            delay: AppMotion.stagger(2),
            child: _PerfilPublicoPlano(profile: profile),
          ),
        ],
      ),
      right: TreinoFadeSlideIn(
        delay: AppMotion.stagger(0),
        child: CoachDiscoveryPreviewCard(profile: profile),
      ),
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
