// NOTE: Scaffold y SafeArea los provee CoachHubScaffold (ADR-CHW-005).
// Todas las strings en español hardcodeado + // i18n.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
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
              style: GoogleFonts.barlow(color: palette.textMuted, fontSize: 14),
            ),
          ),
          const SizedBox(height: 20),
          TreinoStateSwitcher(
            childKey: ValueKey(_stateKeyOf(linksAsync, athletes)),
            child: _RutinasBody(linksAsync: linksAsync, athletes: athletes),
          ),
        ],
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
          if (i != 0) const SizedBox(height: AppSpacing.s8),
          TreinoFadeSlideIn(
            delay: AppMotion.stagger(i),
            child: _AthleteRow(athleteId: athletes[i].athleteId),
          ),
        ],
      ],
    );
  }
}

/// Fila de un alumno — tap abre el editor de rutinas para ese alumno.
class _AthleteRow extends ConsumerWidget {
  const _AthleteRow({required this.athleteId});

  final String athleteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final profileAsync = ref.watch(userPublicProfileProvider(athleteId));
    final rawName = profileAsync.valueOrNull?.displayName ?? '';
    final name = rawName.isEmpty ? 'Alumno' : rawName; // i18n
    final initial = name.substring(0, 1).toUpperCase();

    return TreinoListRow(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: palette.bg,
        child: Text(
          initial,
          style: TextStyle(color: palette.accent, fontWeight: FontWeight.w700),
        ),
      ),
      title: name,
      trailing:
          Icon(TreinoIcon.chevronRight, size: 18, color: palette.textMuted),
      onTap: () => context.push('/rutinas/$athleteId'),
    );
  }
}
