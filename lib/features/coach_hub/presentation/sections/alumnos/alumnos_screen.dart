import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
import 'package:treino/features/gyms/application/gym_providers.dart';
import '../../../../../l10n/app_l10n.dart';
import 'package:treino/features/payments/application/pagos_por_cobrar_provider.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/session_providers.dart';

/// Estado compuesto de un alumno en el roster (link + billing).
///
/// Fase W2 PR1: `vencido` (cobro vencido) y `adherencia`/`plan`/`objetivo` se
/// difieren porque dependen de data que todavía no existe (ver data-map).
enum AlumnoEstado { activo, conDeuda, pausado, inactivo }

extension AlumnoEstadoX on AlumnoEstado {
  String label(AppL10n l10n) => switch (this) {
        AlumnoEstado.activo => l10n.coachHubAlumnosStatusActive,
        AlumnoEstado.conDeuda => l10n.coachHubAlumnosStatusDebt,
        AlumnoEstado.pausado => l10n.coachHubAlumnosStatusPaused,
        AlumnoEstado.inactivo => l10n.coachHubAlumnosStatusInactive,
      };

  Color color(AppPalette p) => switch (this) {
        AlumnoEstado.activo => p.accent,
        AlumnoEstado.conDeuda => p.warning,
        AlumnoEstado.pausado => p.highlight,
        AlumnoEstado.inactivo => p.textMuted,
      };
}

/// Filtro de estado del roster (chips).
enum RosterFiltro { todos, activos, pausados, inactivos, conDeuda }

/// Estado compuesto de un link, derivado de su `status` + billing.
AlumnoEstado estadoForLink(TrainerLink link, Set<String> conDeudaIds) {
  switch (link.status) {
    case TrainerLinkStatus.paused:
      return AlumnoEstado.pausado;
    case TrainerLinkStatus.terminated:
    case TrainerLinkStatus.pending:
      return AlumnoEstado.inactivo;
    case TrainerLinkStatus.active:
      return conDeudaIds.contains(link.athleteId)
          ? AlumnoEstado.conDeuda
          : AlumnoEstado.activo;
  }
}

/// Los chips particionan el roster: «Activos» y «Con deuda» son DISJUNTOS — un
/// alumno con deuda cuenta solo bajo «Con deuda», igual que el mockup
/// (view-general.png: Activos 14 · Con deuda 2 · … = total).
bool _matchesFiltro(AlumnoEstado e, RosterFiltro f) => switch (f) {
      RosterFiltro.todos => true,
      RosterFiltro.activos => e == AlumnoEstado.activo,
      RosterFiltro.pausados => e == AlumnoEstado.pausado,
      RosterFiltro.inactivos => e == AlumnoEstado.inactivo,
      RosterFiltro.conDeuda => e == AlumnoEstado.conDeuda,
    };

final _filtroProvider =
    StateProvider.autoDispose<RosterFiltro>((_) => RosterFiltro.todos);
final _queryProvider = StateProvider.autoDispose<String>((_) => '');

/// Alumno + su estado compuesto ya resuelto (evita recalcular
/// `estadoForLink` por columna/celda).
typedef _RosterEntry = ({TrainerLink link, AlumnoEstado estado});

/// Roster del Coach Hub web (`/alumnos`).
///
/// Tabla de alumnos vinculados (kit v2, Fase 3 WU-03: `CoachHubDataTable` +
/// `TreinoFilterChips`) con estado compuesto, último entreno (Hoy) y acciones
/// de vínculo (pausar/reanudar/terminar). Renderiza DENTRO del shell — sin
/// Scaffold (ADR-CHW-005). Columnas Plan/Objetivo/Adherencia y el toggle de
/// cards del mockup quedan fuera de alcance: dependen de data inexistente
/// (ADR-A3-01).
class AlumnosScreen extends ConsumerWidget {
  const AlumnosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final linksAsync = ref.watch(trainerLinksStreamProvider);

    return TreinoStateSwitcher(
      childKey: ValueKey('alumnos_links_${_stateKeyOf(linksAsync)}'),
      child: linksAsync.when(
        loading: () => const _RosterFrame(
          roster: [],
          profiles: {},
          gymNameById: {},
          tableLoading: true,
        ),
        error: (e, _) => _RosterFrame(
          roster: const [],
          profiles: const {},
          gymNameById: const {},
          errorMessage: l10n.coachHubAlumnosLoadError,
          onRetry: () => ref.invalidate(trainerLinksStreamProvider),
        ),
        data: (links) => _LinksLoaded(links: links),
      ),
    );
  }
}

String _stateKeyOf(AsyncValue<Object?> value) {
  if (value.hasError) return 'error';
  if (value.isLoading && !value.hasValue) return 'loading';
  return 'data';
}

/// Resuelve perfiles + gyms + deuda una vez que el stream de links ya emitió,
/// y cross-fadea la tabla entre loading/error/data de los perfiles.
class _LinksLoaded extends ConsumerWidget {
  const _LinksLoaded({required this.links});

  final List<TrainerLink> links;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);

    // Un alumno = una fila: colapsamos a su link más reciente (el stream
    // viene requestedAt DESC) y excluimos `pending` (esos son solicitudes,
    // sección aparte). Sin esto, un alumno re-vinculado (terminado + nuevo
    // activo) aparecería dos veces e infla los contadores.
    final seen = <String>{};
    final roster = [
      for (final l in links)
        if (l.status != TrainerLinkStatus.pending && seen.add(l.athleteId)) l,
    ];
    final ids = (roster.map((l) => l.athleteId).toSet().toList()..sort());
    final profilesAsync =
        ref.watch(userPublicProfilesBatchProvider(ids.join(',')));
    final conDeudaIds = <String>{
      for (final c in ref.watch(pagosPorCobrarProvider).valueOrNull ?? const [])
        c.athleteId,
    };

    // Una sola lectura del catálogo de gimnasios (~20 docs) en vez de un
    // gymByIdProvider por fila (N+1) — mismo criterio que el batch de perfiles.
    final gyms = ref.watch(gymsProvider).valueOrNull ?? const [];
    final gymNameById = {for (final g in gyms) g.id: g.name};

    final rosterWithEstado = [
      for (final l in roster) (link: l, estado: estadoForLink(l, conDeudaIds)),
    ];

    return TreinoStateSwitcher(
      childKey: ValueKey('alumnos_profiles_${_stateKeyOf(profilesAsync)}'),
      child: profilesAsync.when(
        loading: () => _RosterFrame(
          roster: rosterWithEstado,
          profiles: const {},
          gymNameById: gymNameById,
          tableLoading: true,
        ),
        error: (e, _) => _RosterFrame(
          roster: rosterWithEstado,
          profiles: const {},
          gymNameById: gymNameById,
          errorMessage: l10n.coachHubAlumnosProfilesLoadError,
          onRetry: () =>
              ref.invalidate(userPublicProfilesBatchProvider(ids.join(','))),
        ),
        data: (profiles) => _RosterFrame(
          roster: rosterWithEstado,
          profiles: profiles,
          gymNameById: gymNameById,
        ),
      ),
    );
  }
}

/// Header (título CAPS + subtítulo) + filtros + búsqueda + tabla.
///
/// El bloque header/filtros/búsqueda entra con `TreinoFadeSlideIn` staggered
/// (índices 0/1/2); la tabla queda fuera de ese stagger — su propio
/// cross-fade lo resuelve el `TreinoStateSwitcher` del caller.
class _RosterFrame extends ConsumerWidget {
  const _RosterFrame({
    required this.roster,
    required this.profiles,
    required this.gymNameById,
    this.tableLoading = false,
    this.errorMessage,
    this.onRetry,
  });

  final List<_RosterEntry> roster;
  final Map<String, UserPublicProfile> profiles;
  final Map<String, String> gymNameById;
  final bool tableLoading;
  final String? errorMessage;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final filtro = ref.watch(_filtroProvider);
    final query = ref.watch(_queryProvider).trim().toLowerCase();

    String? gymNameFor(TrainerLink l) {
      final gid = profiles[l.athleteId]?.gymId;
      return gid == null ? null : gymNameById[gid];
    }

    int countFor(RosterFiltro f) =>
        roster.where((e) => _matchesFiltro(e.estado, f)).length;

    final visibles = roster.where((e) {
      if (!_matchesFiltro(e.estado, filtro)) return false;
      if (query.isEmpty) return true;
      final name =
          (profiles[e.link.athleteId]?.displayName ?? '').toLowerCase();
      return name.contains(query);
    }).toList();

    final activos = roster.where((e) => e.estado == AlumnoEstado.activo).length;

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
                TreinoSectionHeader(
                  title: l10n.coachHubAlumnosTitle,
                  count: roster.length,
                ),
                const SizedBox(height: AppSpacing.hairline),
                Text(
                  l10n.coachHubAlumnosSummary(roster.length, activos),
                  style: TextStyle(color: palette.textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s18),
          TreinoFadeSlideIn(
            delay: AppMotion.stagger(1),
            child: _FiltroChips(filtro: filtro, countFor: countFor),
          ),
          const SizedBox(height: AppSpacing.s12),
          TreinoFadeSlideIn(
            delay: AppMotion.stagger(2),
            child: const _SearchField(),
          ),
          const SizedBox(height: AppSpacing.s14),
          _RosterTable(
            visibles: visibles,
            profiles: profiles,
            gymNameFor: gymNameFor,
            loading: tableLoading,
            errorMessage: errorMessage,
            onRetry: onRetry,
            emptyMessage: roster.isEmpty
                ? l10n.coachHubAlumnosEmpty
                : l10n.coachHubAlumnosEmptyFiltered,
          ),
        ],
      ),
    );
  }
}

class _FiltroChips extends ConsumerWidget {
  const _FiltroChips({required this.filtro, required this.countFor});

  final RosterFiltro filtro;
  final int Function(RosterFiltro) countFor;

  // Orden de chips como el mockup; labels vía AppL10n.
  List<(RosterFiltro, String)> _chips(AppL10n l10n) => [
        (RosterFiltro.todos, l10n.coachHubAlumnosFilterAll),
        (RosterFiltro.activos, l10n.coachHubAlumnosFilterActivos),
        (RosterFiltro.conDeuda, l10n.coachHubAlumnosFilterConDeuda),
        (RosterFiltro.pausados, l10n.coachHubAlumnosFilterPausados),
        (RosterFiltro.inactivos, l10n.coachHubAlumnosFilterInactivos),
      ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final chips = _chips(l10n);
    final labelByFiltro = {for (final (f, label) in chips) f: label};
    final filtroByLabel = {for (final (f, label) in chips) label: f};

    return TreinoFilterChips(
      options: [for (final (_, label) in chips) label],
      selected: {labelByFiltro[filtro]!},
      badgeCounts: {
        for (final (f, label) in chips) label: countFor(f),
      },
      onChanged: (newSelected) {
        // Single-select: TreinoFilterChips permite deseleccionar el chip
        // activo (queda `{}`) — el roster siempre necesita un filtro activo,
        // así que un tap que vacía la selección es un no-op.
        if (newSelected.isEmpty) return;
        final f = filtroByLabel[newSelected.first];
        if (f != null) ref.read(_filtroProvider.notifier).state = f;
      },
    );
  }
}

class _SearchField extends ConsumerStatefulWidget {
  const _SearchField();

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return TextField(
      controller: _controller,
      onChanged: (v) => ref.read(_queryProvider.notifier).state = v,
      style: TextStyle(color: palette.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: l10n.coachHubAlumnosSearchHint,
        hintStyle: TextStyle(color: palette.textMuted),
        prefixIcon: Icon(TreinoIcon.search, color: palette.textMuted, size: 18),
        isDense: true,
        filled: true,
        fillColor: palette.bgCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: palette.accent),
        ),
      ),
    );
  }
}

/// Tabla del roster — `CoachHubDataTable` con celdas-widget (ADR-A3-02) para
/// Alumno (avatar + nombre + gym), Estado (dot + label) y Acciones (íconos).
/// Loading/error/empty los resuelve el kit (shimmer/retry/EmptyState).
class _RosterTable extends ConsumerWidget {
  const _RosterTable({
    required this.visibles,
    required this.profiles,
    required this.gymNameFor,
    required this.loading,
    required this.errorMessage,
    required this.emptyMessage,
    this.onRetry,
  });

  final List<_RosterEntry> visibles;
  final Map<String, UserPublicProfile> profiles;
  final String? Function(TrainerLink) gymNameFor;
  final bool loading;
  final String? errorMessage;
  final String emptyMessage;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return CoachHubDataTable(
      columns: [
        CoachHubColumn(
          key: 'alumno',
          label: l10n.coachHubAlumnosColumnStudent,
          flex: 4,
        ),
        CoachHubColumn(
          key: 'estado',
          label: l10n.coachHubAlumnosColumnStatus,
          flex: 2,
        ),
        CoachHubColumn(
          key: 'ultimoEntreno',
          label: l10n.coachHubAlumnosColumnLastWorkout,
          flex: 2,
        ),
        CoachHubColumn(
          key: 'acciones',
          label: l10n.coachHubAlumnosColumnActions,
          flex: 2,
        ),
      ],
      rows: [
        for (final entry in visibles)
          _rowFor(context, ref, palette, l10n, entry, gymNameFor(entry.link)),
      ],
      loading: loading,
      errorMessage: errorMessage,
      onRetry: onRetry,
      emptyMessage: emptyMessage,
      onRowTap: (id) => context.go('/alumnos/$id'),
    );
  }

  CoachHubRow _rowFor(
    BuildContext context,
    WidgetRef ref,
    AppPalette palette,
    AppL10n l10n,
    _RosterEntry entry,
    String? gymName,
  ) {
    final link = entry.link;
    final estado = entry.estado;
    final profile = profiles[link.athleteId];
    final name = profile?.displayName ?? l10n.coachHubAlumnosNameFallback;
    final trainedToday =
        (ref.watch(finishedTodayByUidProvider(link.athleteId)).valueOrNull ??
                const [])
            .isNotEmpty;

    return CoachHubRow(
      id: link.athleteId,
      cells: {
        'alumno': name,
        'estado': estado.label(l10n),
        'ultimoEntreno':
            trainedToday ? l10n.coachHubAlumnosLastWorkoutToday : '—',
      },
      cellWidgets: {
        'alumno': _AlumnoCell(
          name: name,
          url: profile?.avatarUrl,
          gymName: gymName,
          palette: palette,
        ),
        'estado': _EstadoBadge(estado: estado, palette: palette),
        'acciones': _RowActions(link: link, palette: palette),
      },
    );
  }
}

/// Celda «Alumno»: avatar + nombre + gym (si se conoce).
class _AlumnoCell extends StatelessWidget {
  const _AlumnoCell({
    required this.name,
    required this.url,
    required this.gymName,
    required this.palette,
  });

  final String name;
  final String? url;
  final String? gymName;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Avatar(name: name, url: url, palette: palette),
        const SizedBox(width: AppSpacing.s12),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (gymName != null)
                Text(
                  gymName!,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.textMuted, fontSize: 12),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.url, required this.palette});

  final String name;
  final String? url;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return CircleAvatar(
      radius: 18,
      backgroundColor: palette.bg,
      backgroundImage:
          (url != null && url!.isNotEmpty) ? NetworkImage(url!) : null,
      child: (url == null || url!.isEmpty)
          ? Text(
              initial,
              style: TextStyle(
                color: palette.accent,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            )
          : null,
    );
  }
}

class _EstadoBadge extends StatelessWidget {
  const _EstadoBadge({required this.estado, required this.palette});

  final AlumnoEstado estado;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final color = estado.color(palette);
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.hairline + AppSpacing.hairline),
          Flexible(
            child: Text(
              estado.label(l10n),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _RowActions extends ConsumerWidget {
  const _RowActions({required this.link, required this.palette});

  final TrainerLink link;
  final AppPalette palette;

  Future<void> _pause(BuildContext context, WidgetRef ref) async {
    final l10n = AppL10n.of(context);
    final ok = await _confirmAction(
      context,
      title: l10n.coachHubDashboardPauseLinkTitle,
      body: l10n.coachHubDashboardPauseLinkBody,
      confirmLabel: l10n.coachHubActionPause,
    );
    if (!ok) return;
    await ref.read(trainerLinkRepositoryProvider).pause(link.id);
  }

  Future<void> _resume(WidgetRef ref) =>
      ref.read(trainerLinkRepositoryProvider).resume(link.id);

  Future<void> _terminate(BuildContext context, WidgetRef ref) async {
    final l10n = AppL10n.of(context);
    final ok = await _confirmAction(
      context,
      title: l10n.coachHubDashboardTerminateLinkTitle,
      body: l10n.coachHubDashboardTerminateLinkBody,
      confirmLabel: l10n.coachHubActionTerminate,
    );
    if (!ok) return;
    await ref
        .read(trainerLinkRepositoryProvider)
        .terminate(link.id, reason: 'trainer-terminated');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final status = link.status;
    final buttons = <Widget>[];
    if (status == TrainerLinkStatus.active) {
      buttons.add(_IconAction(
        icon: TreinoIcon.pause,
        tooltip: l10n.coachHubActionPause,
        color: palette.textMuted,
        onPressed: () => _pause(context, ref),
      ));
    } else if (status == TrainerLinkStatus.paused) {
      buttons.add(_IconAction(
        icon: TreinoIcon.play,
        tooltip: l10n.coachHubActionResume,
        color: palette.accent,
        onPressed: () => _resume(ref),
      ));
    }
    if (status == TrainerLinkStatus.active ||
        status == TrainerLinkStatus.paused) {
      buttons.add(_IconAction(
        icon: TreinoIcon.signOut,
        tooltip: l10n.coachHubActionTerminate,
        color: palette.highlight,
        onPressed: () => _terminate(context, ref),
      ));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: buttons,
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 18, color: color),
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Diálogo de confirmación — kit v2 (`showTreinoDialog`/`TreinoDialog`,
/// mismo patrón que el resto del Coach Hub web).
Future<bool> _confirmAction(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
}) async {
  final l10n = AppL10n.of(context);
  final result = await showTreinoDialog<bool>(
    context,
    builder: (ctx) => TreinoDialog(
      title: title,
      body: Text(body),
      primaryLabel: confirmLabel,
      onPrimaryTap: () => Navigator.of(ctx).pop(true),
      secondaryLabel: l10n.coachHubActionCancel,
      onSecondaryTap: () => Navigator.of(ctx).pop(false),
    ),
  );
  return result ?? false;
}
