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
import 'package:treino/features/coach_hub/presentation/sections/rutinas/routine_actions_provider.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_status.dart';

/// Filtro de estado seleccionado en [AthleteRoutinesScreen] (WU-03).
/// `autoDispose` porque el filtro no debe sobrevivir a la navegación fuera
/// de esta pantalla — mismo patrón que `_filtroProvider` en AlumnosScreen.
final _statusFilterProvider =
    StateProvider.autoDispose<RoutineStatus>((_) => RoutineStatus.active);

const _kActivasLabel = 'Activas'; // i18n
const _kArchivadasLabel = 'Archivadas'; // i18n

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
    final statusFilter = ref.watch(_statusFilterProvider);
    final allRoutines = routinesAsync.valueOrNull ?? const <Routine>[];
    final active =
        allRoutines.where((r) => r.status == RoutineStatus.active).toList();
    final archived =
        allRoutines.where((r) => r.status == RoutineStatus.archived).toList();
    final visible = statusFilter == RoutineStatus.active ? active : archived;

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
                    count: routinesAsync.hasValue ? visible.length : null,
                    action: TreinoSectionHeaderAction(
                      label: 'Nueva rutina', // i18n
                      onTap: () => context.push('/routine-editor/$athleteId'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s18),
          TreinoFadeSlideIn(
            delay: AppMotion.stagger(1),
            child: TreinoFilterChips(
              options: const [_kActivasLabel, _kArchivadasLabel],
              selected: {
                statusFilter == RoutineStatus.active
                    ? _kActivasLabel
                    : _kArchivadasLabel,
              },
              badgeCounts: {
                _kActivasLabel: active.length,
                _kArchivadasLabel: archived.length,
              },
              onChanged: (newSelected) {
                // Single-select: TreinoFilterChips permite deseleccionar el
                // chip activo (queda `{}`) — siempre necesitamos un filtro
                // activo, así que un tap que vacía la selección es un no-op
                // (mismo criterio que AlumnosScreen._FiltroChips).
                if (newSelected.isEmpty) return;
                final f = newSelected.first == _kActivasLabel
                    ? RoutineStatus.active
                    : RoutineStatus.archived;
                ref.read(_statusFilterProvider.notifier).state = f;
              },
            ),
          ),
          const SizedBox(height: AppSpacing.s20),
          TreinoStateSwitcher(
            childKey:
                ValueKey(_stateKeyOf(routinesAsync, visible, statusFilter)),
            child: _AthleteRoutinesBody(
              routinesAsync: routinesAsync,
              visible: visible,
              statusFilter: statusFilter,
              athleteId: athleteId,
            ),
          ),
        ],
      ),
    );
  }
}

/// Key del [TreinoStateSwitcher]: `loading` sólo en la primera carga (sin
/// data previa), luego `error`/`empty-{filtro}`/`data-{filtro}` según
/// corresponda — el sufijo de filtro fuerza el cross-fade al cambiar entre
/// Activas/Archivadas (WU-03).
String _stateKeyOf(
  AsyncValue<List<Routine>> routinesAsync,
  List<Routine> visible,
  RoutineStatus statusFilter,
) {
  if (routinesAsync.isLoading && !routinesAsync.hasValue) return 'loading';
  if (routinesAsync.hasError) return 'error';
  final suffix =
      statusFilter == RoutineStatus.active ? 'activas' : 'archivadas';
  return visible.isEmpty ? 'empty-$suffix' : 'data-$suffix';
}

/// Contenido bajo el header — resuelve loading/error/empty/data.
class _AthleteRoutinesBody extends ConsumerWidget {
  const _AthleteRoutinesBody({
    required this.routinesAsync,
    required this.visible,
    required this.statusFilter,
    required this.athleteId,
  });

  final AsyncValue<List<Routine>> routinesAsync;
  final List<Routine> visible;
  final RoutineStatus statusFilter;
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

    if (visible.isEmpty) {
      return TreinoEmptyState(
        icon: TreinoIcon.emptyState,
        title: statusFilter == RoutineStatus.active
            ? 'Todavía no le cargaste ninguna rutina.' // i18n
            : 'No hay rutinas archivadas.', // i18n
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < visible.length; i++) ...[
          if (i != 0) const SizedBox(height: AppSpacing.s8),
          TreinoFadeSlideIn(
            delay: AppMotion.stagger(i),
            child: _RoutineRow(
              routine: visible[i],
              athleteId: athleteId,
              archived: statusFilter == RoutineStatus.archived,
            ),
          ),
        ],
      ],
    );
  }
}

/// Fila de una rutina asignada.
///
/// - Activas web-editables: tap abre el editor, trailing ícono de edición +
///   botón de archivar (WU-04, única mutación cableada desde esta pantalla).
/// - Activas periodizadas: view-only con hint "Editá en la app" (se editan
///   en mobile). Sin acción de archivar — fuera de scope de WU-04 (mockup
///   pide "web-editables" solamente).
/// - Archivadas (WU-03): SIEMPRE view-only (soft-delete, ADR-USR-04) — sin
///   tap y con trailing informativo propio (no reutiliza el hint de
///   periodizadas, que es semánticamente distinto: "existe pero se edita en
///   otro lado" vs. "ya no está activa").
class _RoutineRow extends ConsumerStatefulWidget {
  const _RoutineRow({
    required this.routine,
    required this.athleteId,
    this.archived = false,
  });

  final Routine routine;
  final String athleteId;
  final bool archived;

  @override
  ConsumerState<_RoutineRow> createState() => _RoutineRowState();
}

class _RoutineRowState extends ConsumerState<_RoutineRow> {
  /// Busy local a la fila mientras la mutación de archivar está en curso —
  /// la fila desaparece de la lista apenas termina (invalidate del
  /// provider), así que este flag sólo cubre la ventana de la llamada.
  bool _archiving = false;

  Future<void> _handleArchiveTap() async {
    final confirmed = await showTreinoDialog<bool>(
      context,
      builder: (ctx) => TreinoDialog(
        title: 'Archivar rutina', // i18n
        body: Text(
          '¿Archivar "${widget.routine.name}"? Va a dejar de estar activa y '
          'vas a poder verla en Archivadas.', // i18n
        ),
        primaryLabel: 'Archivar', // i18n
        secondaryLabel: 'Cancelar', // i18n
        destructive: true,
        onPrimaryTap: () => Navigator.of(ctx).pop(true),
        onSecondaryTap: () => Navigator.of(ctx).pop(false),
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _archiving = true);

    final ok = await ref.read(routineActionsProvider.notifier).archive(
          routineId: widget.routine.id,
          athleteId: widget.athleteId,
        );

    if (!mounted) return;
    setState(() => _archiving = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Rutina archivada.' // i18n
              : 'No pudimos archivar la rutina.', // i18n
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final routine = widget.routine;
    final archived = widget.archived;
    final editable = !archived && isRoutineWebEditable(routine);
    final weeks = routine.numWeeks == 1 ? 'semana' : 'semanas'; // i18n

    Widget trailing;
    if (archived) {
      trailing = Text(
        'Archivada', // i18n
        style: TextStyle(
          fontFamily: AppFonts.barlow,
          fontSize: 12,
          color: palette.textMuted,
        ),
      );
    } else if (!editable) {
      trailing = Text(
        'Editá en la app', // i18n
        style: TextStyle(
          fontFamily: AppFonts.barlow,
          fontSize: 12,
          color: palette.textMuted,
        ),
      );
    } else if (_archiving) {
      trailing = SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: palette.textMuted,
        ),
      );
    } else {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(TreinoIcon.edit, size: 18, color: palette.textMuted),
          const SizedBox(width: AppSpacing.s8),
          IconButton(
            key: ValueKey('routine_row_archive_button_${routine.id}'),
            tooltip: 'Archivar', // i18n
            icon: Icon(TreinoIcon.archive, size: 18, color: palette.textMuted),
            onPressed: _handleArchiveTap,
            visualDensity: VisualDensity.compact,
            splashRadius: 16,
          ),
        ],
      );
    }

    return TreinoListRow(
      title: routine.name,
      subtitle:
          '${routine.days.length} días · ${routine.numWeeks} $weeks', // i18n
      trailing: trailing,
      onTap: editable
          ? () =>
              context.push('/routine-editor/${widget.athleteId}/${routine.id}')
          : null,
    );
  }
}
