// NOTE: Scaffold y SafeArea los provee CoachHubScaffold (ADR-CHW-005).
// Todas las strings en español hardcodeado + // i18n.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';
import 'package:treino/core/widgets/motion/treino_state_switcher.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';

/// Sección «Rutinas» del Coach Hub web.
///
/// Una rutina se asigna a UN alumno, así que el flujo necesita un destino.
/// El sidebar es global (no está parado sobre ningún alumno), por eso esta
/// pantalla es el punto de entrada: lista los alumnos vinculados y, al tocar
/// uno, abre sus rutinas (`/rutinas/:athleteId`) donde el PF ve las que ya le
/// cargó y puede crear o editar. Mismo espíritu que mobile, expuesto desde el
/// menú lateral.
class RutinasScreen extends ConsumerWidget {
  const RutinasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final linksAsync = ref.watch(trainerLinksStreamProvider);

    // Una fila por alumno: colapsamos al link más reciente (el stream viene
    // requestedAt DESC) y excluimos `pending` (esas son solicitudes,
    // todavía no son alumnos).
    final athletes = _dedupedAthletes(linksAsync.valueOrNull ?? const []);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      // Ancho máximo: se acabó el borde a borde — el roster de alumnos vive
      // en una columna angosta, alineada a la izquierda con el resto del
      // padding de la página (mismo criterio de `maxWidth` que el editor de
      // rutinas web).
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TreinoFadeSlideIn(
                delay: AppMotion.stagger(0),
                child: TreinoSectionHeader(
                  title: 'Rutinas', // i18n
                  count: linksAsync.hasValue ? athletes.length : null,
                ),
              ),
              const SizedBox(height: 6),
              TreinoFadeSlideIn(
                delay: AppMotion.stagger(1),
                child: Text(
                  'Elegí un alumno para armarle una rutina.', // i18n
                  style: TextStyle(
                    fontFamily: AppFonts.barlow,
                    color: palette.textMuted,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TreinoStateSwitcher(
                childKey: ValueKey(_stateKeyOf(linksAsync, athletes)),
                child: _RutinasBody(linksAsync: linksAsync, athletes: athletes),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Alumnos no-pending, colapsados a un único link por `athleteId`.
List<TrainerLink> _dedupedAthletes(List<TrainerLink> links) {
  final seen = <String>{};
  final athletes = <TrainerLink>[];
  for (final l in links) {
    if (l.status == TrainerLinkStatus.pending) continue;
    if (seen.add(l.athleteId)) athletes.add(l);
  }
  return athletes;
}

/// Key del [TreinoStateSwitcher]: `loading` sólo en la primera carga (sin
/// data previa), luego `error`/`empty`/`data` según corresponda.
String _stateKeyOf(
  AsyncValue<List<TrainerLink>> linksAsync,
  List<TrainerLink> athletes,
) {
  if (linksAsync.isLoading && !linksAsync.hasValue) return 'loading';
  if (linksAsync.hasError) return 'error';
  if (athletes.isEmpty) return 'empty';
  return 'data';
}

/// Contenido bajo el header — resuelve loading/error/empty/data.
class _RutinasBody extends ConsumerWidget {
  const _RutinasBody({required this.linksAsync, required this.athletes});

  final AsyncValue<List<TrainerLink>> linksAsync;
  final List<TrainerLink> athletes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (linksAsync.isLoading && !linksAsync.hasValue) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < 4; i++) ...[
            if (i != 0) const SizedBox(height: AppSpacing.s8),
            const TreinoListRow(title: '', loading: true),
          ],
        ],
      );
    }

    if (linksAsync.hasError) {
      return TreinoEmptyState(
        icon: TreinoIcon.errorState,
        title: 'No pudimos cargar los alumnos.', // i18n
        ctaLabel: 'Reintentar', // i18n
        onCtaTap: () => ref.invalidate(trainerLinksStreamProvider),
      );
    }

    if (athletes.isEmpty) {
      return const TreinoEmptyState(
        icon: TreinoIcon.emptyState,
        title: 'Todavía no tenés alumnos vinculados.', // i18n
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < athletes.length; i++) ...[
          if (i != 0) const SizedBox(height: AppSpacing.s12),
          TreinoFadeSlideIn(
            delay: AppMotion.stagger(i),
            child: _AthleteRow(link: athletes[i]),
          ),
        ],
      ],
    );
  }
}

/// Color del dot de estado — mismo mapeo semántico de `estadoForLink`
/// (alumnos_screen.dart: activo=accent, pausado=highlight, resto=textMuted)
/// pero sin depender del provider de facturación (esta pantalla no necesita
/// distinguir "con deuda", solo dar una señal viva de estado del vínculo).
Color _linkStatusColor(AppPalette p, TrainerLinkStatus status) =>
    switch (status) {
      TrainerLinkStatus.active => p.accent,
      TrainerLinkStatus.paused => p.highlight,
      TrainerLinkStatus.terminated => p.textMuted,
      TrainerLinkStatus.pending => p.textMuted, // no llega acá (deduped)
    };

/// Card de un alumno — tap abre el editor de rutinas para ese alumno.
///
/// Reemplaza la fila pelada (avatar gris + nombre + chevron flotando en
/// bg negro) por una card con superficie propia (bgCard + borde), avatar
/// tintado por nombre ([TreinoAvatar], compartido con Chat) y un dot de
/// estado del vínculo — feedback de revisión en vivo: "está todo muy negro,
/// hay que darle más vida, más colores".
class _AthleteRow extends ConsumerWidget {
  const _AthleteRow({required this.link});

  final TrainerLink link;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final profileAsync = ref.watch(userPublicProfileProvider(link.athleteId));
    final resolvedName = profileAsync.valueOrNull?.displayName;
    final name = (resolvedName == null || resolvedName.isEmpty)
        ? 'Alumno'
        : resolvedName; // i18n

    return TreinoInteractiveState(
      key: Key('athlete_row_${link.athleteId}'),
      onTap: () => context.push('/rutinas/${link.athleteId}'),
      builder: (ctx, states) {
        final highlighted = states.hovered || states.pressed;

        return AnimatedContainer(
          duration:
              AppMotionTokens.resolve(ctx, AppMotionTokens.cardStateChange),
          curve: AppMotionTokens.enter,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s20,
            vertical: AppSpacing.s18,
          ),
          decoration: BoxDecoration(
            color: highlighted
                ? TreinoCardTokens.border(ctx).withValues(alpha: 0.08)
                : TreinoCardTokens.background(ctx),
            borderRadius: BorderRadius.circular(TreinoCardTokens.borderRadius),
            border: Border.all(
              color: highlighted
                  ? palette.borderHover
                  : TreinoCardTokens.border(ctx),
            ),
          ),
          child: Row(
            children: [
              TreinoAvatar(
                displayName: resolvedName == null ? null : name,
                avatarUrl: profileAsync.valueOrNull?.avatarUrl,
                diameter: 40,
                initialFontSize: 15,
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontFamily: AppFonts.barlow,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: palette.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              Container(
                key: Key('athlete_row_status_dot_${link.athleteId}'),
                width: AppSpacing.s8,
                height: AppSpacing.s8,
                decoration: BoxDecoration(
                  color: _linkStatusColor(palette, link.status),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              Icon(
                TreinoIcon.chevronRight,
                size: 18,
                color: highlighted ? palette.accent : palette.textMuted,
              ),
            ],
          ),
        );
      },
    );
  }
}
