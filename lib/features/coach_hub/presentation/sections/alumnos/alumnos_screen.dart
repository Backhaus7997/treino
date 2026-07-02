import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
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

/// Roster del Coach Hub web (`/alumnos`, Fase W2 PR1).
///
/// Tabla de alumnos vinculados con estado compuesto, último entreno (Hoy) y
/// acciones de vínculo (pausar/reanudar/terminar). Renderiza DENTRO del shell —
/// sin Scaffold (ADR-CHW-005). Columnas Plan/Objetivo/Adherencia y el toggle de
/// cards llegan en PRs siguientes (dependen de data nueva).
class AlumnosScreen extends ConsumerWidget {
  const AlumnosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final linksAsync = ref.watch(trainerLinksStreamProvider);
    return linksAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _CenteredMuted(l10n.coachHubAlumnosLoadError),
      data: (links) {
        // Un alumno = una fila: colapsamos a su link más reciente (el stream
        // viene requestedAt DESC) y excluimos `pending` (esos son solicitudes,
        // sección aparte). Sin esto, un alumno re-vinculado (terminado + nuevo
        // activo) aparecería dos veces e infla los contadores.
        final seen = <String>{};
        final roster = [
          for (final l in links)
            if (l.status != TrainerLinkStatus.pending && seen.add(l.athleteId))
              l,
        ];
        final ids = (roster.map((l) => l.athleteId).toSet().toList()..sort());
        final profilesAsync =
            ref.watch(userPublicProfilesBatchProvider(ids.join(',')));
        final conDeudaIds = <String>{
          for (final c
              in ref.watch(pagosPorCobrarProvider).valueOrNull ?? const [])
            c.athleteId,
        };
        return profilesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) =>
              _CenteredMuted(l10n.coachHubAlumnosProfilesLoadError),
          data: (profiles) => _RosterView(
              roster: roster, profiles: profiles, conDeudaIds: conDeudaIds),
        );
      },
    );
  }
}

class _RosterView extends ConsumerWidget {
  const _RosterView({
    required this.roster,
    required this.profiles,
    required this.conDeudaIds,
  });

  final List<TrainerLink> roster;
  final Map<String, UserPublicProfile> profiles;
  final Set<String> conDeudaIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final filtro = ref.watch(_filtroProvider);
    final query = ref.watch(_queryProvider).trim().toLowerCase();

    // Una sola lectura del catálogo de gimnasios (~20 docs) en vez de un
    // gymByIdProvider por fila (N+1) — mismo criterio que el batch de perfiles.
    final gyms = ref.watch(gymsProvider).valueOrNull ?? const [];
    final gymNameById = {for (final g in gyms) g.id: g.name};
    String? gymNameFor(TrainerLink l) {
      final gid = profiles[l.athleteId]?.gymId;
      return gid == null ? null : gymNameById[gid];
    }

    int countFor(RosterFiltro f) => roster
        .where((l) => _matchesFiltro(estadoForLink(l, conDeudaIds), f))
        .length;

    final visibles = roster.where((l) {
      final estado = estadoForLink(l, conDeudaIds);
      if (!_matchesFiltro(estado, filtro)) return false;
      if (query.isEmpty) return true;
      final name = (profiles[l.athleteId]?.displayName ?? '').toLowerCase();
      return name.contains(query);
    }).toList();

    final activos = roster
        .where((l) => estadoForLink(l, conDeudaIds) == AlumnoEstado.activo)
        .length;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.coachHubAlumnosTitle,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.coachHubAlumnosSummary(roster.length, activos),
            style: TextStyle(color: palette.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 18),
          _FilterBar(filtro: filtro, countFor: countFor),
          const SizedBox(height: 12),
          _SearchField(),
          const SizedBox(height: 14),
          if (visibles.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: _CenteredMuted(
                roster.isEmpty
                    ? l10n.coachHubAlumnosEmpty
                    : l10n.coachHubAlumnosEmptyFiltered,
              ),
            )
          else ...[
            const _RosterHeaderRow(),
            for (final link in visibles)
              _RosterRow(
                link: link,
                profile: profiles[link.athleteId],
                estado: estadoForLink(link, conDeudaIds),
                gymName: gymNameFor(link),
              ),
          ],
        ],
      ),
    );
  }
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.filtro, required this.countFor});

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
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (f, label) in _chips(l10n))
          _Chip(
            label: '$label ${countFor(f)}',
            selected: f == filtro,
            onTap: () => ref.read(_filtroProvider.notifier).state = f,
            palette: palette,
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.palette,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? palette.bgCard : palette.bg,
          border: Border.all(color: selected ? palette.accent : palette.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? palette.accent : palette.textMuted,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _SearchField extends ConsumerStatefulWidget {
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
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.accent),
        ),
      ),
    );
  }
}

class _RosterHeaderRow extends StatelessWidget {
  const _RosterHeaderRow();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    TextStyle s() => TextStyle(
          color: palette.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Row(
        children: [
          Expanded(
              flex: 4,
              child: Text(l10n.coachHubAlumnosColumnStudent, style: s())),
          Expanded(
              flex: 2,
              child: Text(l10n.coachHubAlumnosColumnStatus, style: s())),
          Expanded(
              flex: 2,
              child: Text(l10n.coachHubAlumnosColumnLastWorkout, style: s())),
          Expanded(
            flex: 2,
            child: Text(l10n.coachHubAlumnosColumnActions,
                style: s(), textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

class _RosterRow extends ConsumerWidget {
  const _RosterRow({
    required this.link,
    required this.profile,
    required this.estado,
    required this.gymName,
  });

  final TrainerLink link;
  final UserPublicProfile? profile;
  final AlumnoEstado estado;
  final String? gymName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final name = profile?.displayName ?? l10n.coachHubAlumnosNameFallback;
    final trainedToday =
        (ref.watch(finishedTodayByUidProvider(link.athleteId)).valueOrNull ??
                const [])
            .isNotEmpty;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.go('/alumnos/${link.athleteId}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: palette.bgCard,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  _Avatar(
                      name: name, url: profile?.avatarUrl, palette: palette),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                            style: TextStyle(
                                color: palette.textMuted, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
                flex: 2, child: _EstadoBadge(estado: estado, palette: palette)),
            Expanded(
              flex: 2,
              child: Text(
                trainedToday ? l10n.coachHubAlumnosLastWorkoutToday : '—',
                style: TextStyle(
                  color: trainedToday ? palette.accent : palette.textMuted,
                  fontSize: 13,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: _RowActions(link: link, palette: palette),
            ),
          ],
        ),
      ),
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
          const SizedBox(width: 6),
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

class _CenteredMuted extends StatelessWidget {
  const _CenteredMuted(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child:
          Text(text, style: TextStyle(color: palette.textMuted, fontSize: 14)),
    );
  }
}

/// Diálogo de confirmación (mismo patrón que el dashboard, ADR-CHLM-06).
Future<bool> _confirmAction(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
}) async {
  final l10n = AppL10n.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.coachHubActionCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
