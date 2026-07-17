// NOTE: Scaffold y SafeArea los provee CoachHubScaffold (ADR-CHW-005).
// Todas las strings en español hardcodeado + // i18n. No AppL10n (constraint C-6).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';
import 'package:treino/core/widgets/motion/treino_state_switcher.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/sections/routine_editor/routine_web_editability.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_status.dart';

/// Rutinas ya asignadas a UN alumno (Coach Hub web).
///
/// Punto intermedio del flujo del sidebar «Rutinas»: elegís un alumno y acá ves
/// sus rutinas activas. Desde acá podés crear una nueva (`/routine-editor/:id`)
/// o editar una existente (`/routine-editor/:id/:routineId`, solo las
/// "web-editables" — las periodizadas se editan en mobile, ver
/// [isRoutineWebEditable]).
class AthleteRoutinesScreen extends ConsumerWidget {
  const AthleteRoutinesScreen({super.key, required this.athleteId});

  final String athleteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final profileAsync = ref.watch(userPublicProfileProvider(athleteId));
    final rawName = profileAsync.valueOrNull?.displayName ?? '';
    final name = rawName.isEmpty ? 'el alumno' : rawName; // i18n
    final routinesAsync = ref.watch(assignedRoutinesProvider(athleteId));
    final active = (routinesAsync.valueOrNull ?? const <Routine>[])
        .where((r) => r.status == RoutineStatus.active)
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header: back + título + "Nueva rutina" ──────────────────────
          TreinoFadeSlideIn(
            delay: AppMotion.stagger(0),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(TreinoIcon.arrowLeft, color: palette.textMuted),
                  onPressed: () => context.pop(),
                ),
                const SizedBox(width: AppSpacing.hairline),
                Expanded(
                  child: TreinoSectionHeader(
                    title: 'Rutinas de $name', // i18n
                    count: routinesAsync.hasValue ? active.length : null,
                    action: TreinoSectionHeaderAction(
                      label: 'Nueva rutina', // i18n
                      onTap: () => context.push('/routine-editor/$athleteId'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s20),
          TreinoStateSwitcher(
            childKey: ValueKey(_stateKeyOf(routinesAsync, active)),
            child: _AthleteRoutinesBody(
              routinesAsync: routinesAsync,
              active: active,
              athleteId: athleteId,
            ),
          ),
        ],
      ),
    );
  }
}

/// Key del [TreinoStateSwitcher]: `loading` sólo en la primera carga (sin
/// data previa), luego `error`/`empty`/`data` según corresponda.
String _stateKeyOf(
  AsyncValue<List<Routine>> routinesAsync,
  List<Routine> active,
) {
  if (routinesAsync.isLoading && !routinesAsync.hasValue) return 'loading';
  if (routinesAsync.hasError) return 'error';
  if (active.isEmpty) return 'empty';
  return 'data';
}

/// Contenido bajo el header — resuelve loading/error/empty/data.
class _AthleteRoutinesBody extends ConsumerWidget {
  const _AthleteRoutinesBody({
    required this.routinesAsync,
    required this.active,
    required this.athleteId,
  });

  final AsyncValue<List<Routine>> routinesAsync;
  final List<Routine> active;
  final String athleteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (routinesAsync.isLoading && !routinesAsync.hasValue) {
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

    if (routinesAsync.hasError) {
      return TreinoEmptyState(
        icon: TreinoIcon.errorState,
        title: 'No pudimos cargar las rutinas.', // i18n
        ctaLabel: 'Reintentar', // i18n
        onCtaTap: () => ref.invalidate(assignedRoutinesProvider(athleteId)),
      );
    }

    if (active.isEmpty) {
      return const TreinoEmptyState(
        icon: TreinoIcon.emptyState,
        title: 'Todavía no le cargaste ninguna rutina.', // i18n
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < active.length; i++) ...[
          if (i != 0) const SizedBox(height: AppSpacing.s8),
          TreinoFadeSlideIn(
            delay: AppMotion.stagger(i),
            child: _RoutineRow(routine: active[i], athleteId: athleteId),
          ),
        ],
      ],
    );
  }
}

/// Fila de una rutina asignada — tap abre el editor (web-editables), las
/// periodizadas quedan view-only con un hint "Editá en la app".
class _RoutineRow extends StatelessWidget {
  const _RoutineRow({required this.routine, required this.athleteId});

  final Routine routine;
  final String athleteId;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final editable = isRoutineWebEditable(routine);
    final weeks = routine.numWeeks == 1 ? 'semana' : 'semanas'; // i18n

    return TreinoListRow(
      title: routine.name,
      subtitle:
          '${routine.days.length} días · ${routine.numWeeks} $weeks', // i18n
      trailing: editable
          ? Icon(TreinoIcon.edit, size: 18, color: palette.textMuted)
          : Text(
              'Editá en la app', // i18n
              style: TextStyle(
                fontFamily: AppFonts.barlow,
                fontSize: 12,
                color: palette.textMuted,
              ),
            ),
      onTap: editable
          ? () => context.push('/routine-editor/$athleteId/${routine.id}')
          : null,
    );
  }
}
