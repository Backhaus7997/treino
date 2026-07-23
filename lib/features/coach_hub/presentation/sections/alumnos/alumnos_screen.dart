import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';
import 'package:treino/core/widgets/motion/treino_state_switcher.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/chat/chat_section_screen.dart'
    show selectedChatIdProvider;
import 'package:treino/features/coach_hub/presentation/sections/nutricion/nutricion_providers.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/marcar_pagado_actions.dart'
    show registrarPago;
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/pagos_buckets_provider.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/pagos_estado.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/payment_format.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';
import 'package:treino/features/gyms/application/gym_providers.dart';
import '../../../../../l10n/app_l10n.dart';
import 'package:treino/features/payments/application/pagos_por_cobrar_provider.dart';
import 'package:treino/features/payments/domain/payment.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/domain/routine_status.dart';

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

  // Feedback de revisión ("dot de estado con color semántico"): activo=mint,
  // pausado=warning (antes highlight — no es un estado de riesgo, pero
  // tampoco "normal"), conDeuda=danger (antes warning — más severo que un
  // pago por vencer), inactivo=textMuted. Alinea con la paleta danger/warning
  // que ya usa Pagos (`pagos_estado.dart`).
  Color color(AppPalette p) => switch (this) {
        AlumnoEstado.activo => p.accent,
        AlumnoEstado.pausado => p.warning,
        AlumnoEstado.conDeuda => p.danger,
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

    // Ventana de 30 días, día-truncada (UTC) — se computa UNA vez acá (no por
    // fila) para que la family key de finishedInWindowByUidProvider quede
    // estable entre rebuilds (mismo criterio que inactivosProvider).
    final now = DateTime.now().toUtc();
    final todayStart = DateTime.utc(now.year, now.month, now.day);
    final windowFrom = todayStart.subtract(const Duration(days: 30));
    final windowTo = todayStart.add(const Duration(days: 1));

    return CoachHubDataTable(
      columns: [
        // flex:3 (antes 4) — cede una unidad a la nueva columna Vencimiento;
        // «Alumno» ya trunca con ellipsis (`_AlumnoCell`), así que absorbe el
        // recorte sin riesgo de overflow del header («ALUMNO», 6 caracteres,
        // igual de corto que «ESTADO»/«Rutina», que ya fit en flex:1).
        CoachHubColumn(
          key: 'alumno',
          label: l10n.coachHubAlumnosColumnStudent,
          flex: 3,
        ),
        // flex:1 (antes 2) — cede una unidad a la nueva columna Nutrición
        // («Estado» es un header de 6 caracteres, igual de corto que
        // «Rutina», que ya fit en flex:1; el badge de la celda sigue con
        // ellipsis vía `_DotLabel`, sin riesgo de overflow ahí).
        CoachHubColumn(
          key: 'estado',
          label: l10n.coachHubAlumnosColumnStatus,
          flex: 1,
        ),
        CoachHubColumn(
          key: 'ultimoEntreno',
          label: l10n.coachHubAlumnosColumnLastWorkout,
          flex: 2,
        ),
        const CoachHubColumn(key: 'rutina', label: 'Rutina', flex: 1), // i18n
        // Header corto ("Plan") en vez de "Nutrición": el ancho de columna
        // disponible (flex compartido con el resto de la fila, sin
        // ellipsis en `_HeaderCell` del kit) no entra con la palabra
        // completa — el chip de la celda ("Con plan"/"Sin plan") ya deja
        // clara la semántica.
        const CoachHubColumn(key: 'nutricion', label: 'Plan', flex: 1), // i18n
        // Header corto ("Vence") por la misma razón que "Plan"/"Rutina": el
        // total de flex de la fila se mantiene en 11 (recortando 1 de
        // «Alumno») para no encoger el resto de columnas ya validado contra
        // overflow del header (ver Learned de la pieza col-nutricion).
        const CoachHubColumn(key: 'vencimiento', label: 'Vence', flex: 1),
        CoachHubColumn(
          key: 'acciones',
          label: l10n.coachHubAlumnosColumnActions,
          flex: 2,
        ),
      ],
      rows: [
        for (final entry in visibles)
          _rowFor(
            context,
            ref,
            palette,
            l10n,
            entry,
            gymNameFor(entry.link),
            todayStart: todayStart,
            windowFrom: windowFrom,
            windowTo: windowTo,
          ),
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
    String? gymName, {
    required DateTime todayStart,
    required DateTime windowFrom,
    required DateTime windowTo,
  }) {
    final link = entry.link;
    final estado = entry.estado;
    final profile = profiles[link.athleteId];
    final name = profile?.displayName ?? l10n.coachHubAlumnosNameFallback;

    // Camino barato (sin campo denormalizado): bounded query por-alumno vía
    // finishedInWindowByUidProvider, ordenada finishedAt DESC — el primer
    // elemento ya es la sesión más reciente dentro de la ventana.
    final windowKey =
        (athleteId: link.athleteId, from: windowFrom, to: windowTo);
    final sessionsInWindow =
        ref.watch(finishedInWindowByUidProvider(windowKey)).valueOrNull ??
            const [];
    final lastFinishedAt =
        sessionsInWindow.isEmpty ? null : sessionsInWindow.first.finishedAt;

    return CoachHubRow(
      id: link.athleteId,
      cells: {
        'alumno': name,
        'estado': estado.label(l10n),
        'ultimoEntreno': lastWorkoutLabel(l10n, lastFinishedAt, todayStart),
      },
      cellWidgets: {
        'alumno': _AlumnoCell(
          name: name,
          url: profile?.avatarUrl,
          gymName: gymName,
          palette: palette,
        ),
        'estado': _EstadoBadge(estado: estado, palette: palette),
        'rutina': _RutinaCell(athleteId: link.athleteId, palette: palette),
        'nutricion':
            _NutricionCell(athleteId: link.athleteId, palette: palette),
        'vencimiento':
            _VencimientoCell(athleteId: link.athleteId, palette: palette),
        'acciones': _RowActions(link: link, palette: palette),
      },
    );
  }
}

/// Etiqueta relativa de la columna «Último entreno», dado el `finishedAt` de
/// la sesión más reciente dentro de la ventana de 30 días (o `null` si no
/// hay ninguna) y el "hoy" ya día-truncado (UTC) usado para computar esa
/// ventana. Pública para testear sin pump (mismo patrón que [estadoForLink]).
///
/// "Sin entrenos" es honesto sobre el límite de la ventana: NO implica que el
/// alumno nunca entrenó, sólo que no hay sesión finalizada en los últimos 30
/// días. Labels nuevos hardcodeados es-AR (ADR-A3-03: l10n congelado, sólo
/// columnas existentes usan AppL10n) — excepto "Hoy", que ya tenía key.
String lastWorkoutLabel(
  AppL10n l10n,
  DateTime? lastFinishedAt,
  DateTime todayStart,
) {
  if (lastFinishedAt == null) return 'Sin entrenos'; // i18n
  final utc = lastFinishedAt.toUtc();
  final day = DateTime.utc(utc.year, utc.month, utc.day);
  final daysAgo = todayStart.difference(day).inDays;
  if (daysAgo <= 0) return l10n.coachHubAlumnosLastWorkoutToday;
  if (daysAgo == 1) return 'Ayer'; // i18n
  return 'Hace $daysAgo días'; // i18n
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
    // Fila del kit fija en TreinoTableTokens.rowHeight (48px, ADR-SH-003) →
    // sólo 24px de alto disponibles tras el padding vertical de la celda.
    // Nombre + gym en dos líneas (mockup original) no entra sin overflow;
    // se combinan en una sola línea con separador para respetar el token
    // de altura del kit (design system > mockup cuando chocan, CLAUDE.md).
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Feedback de revisión: avatar tintado del kit (barrel) en vez del
        // círculo apagado (fondo neutro + inicial gris) — mismo componente
        // que Chat/Rutinas, tinte determinístico por nombre.
        TreinoAvatar(displayName: name, avatarUrl: url, diameter: 36),
        const SizedBox(width: AppSpacing.s12),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: name,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (gymName != null)
                  TextSpan(
                    text: '  ·  $gymName',
                    style: TextStyle(color: palette.textMuted, fontSize: 12),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
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
    return _DotLabel(color: estado.color(palette), label: estado.label(l10n));
  }
}

/// Celda «Rutina»: chip compacto (dot + label) que deriva su estado de
/// `assignedRoutinesProvider(athleteId)` — "Activa" si el alumno tiene al
/// menos una rutina con `status == active` asignada, "Sin rutina" en
/// cualquier otro caso (incluye loading/error, `valueOrNull` — mismo
/// criterio "barato" que la celda de último entreno). Tap navega al detalle
/// de rutinas del alumno (`/rutinas/:athleteId`, deep-link) envuelto en
/// `InkWell` para que absorba el gesto y no dispare el `onRowTap` de la fila
/// (mismo patrón que `_IconAction`/`_RowActions`, que ya conviven con el
/// `onRowTap` de `CoachHubDataTable`).
class _RutinaCell extends ConsumerWidget {
  const _RutinaCell({required this.athleteId, required this.palette});

  final String athleteId;
  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routines =
        ref.watch(assignedRoutinesProvider(athleteId)).valueOrNull ?? const [];
    final activa = routines.any((r) => r.status == RoutineStatus.active);
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: () => context.go('/rutinas/$athleteId'),
      child: _DotLabel(
        color: activa ? palette.accent : palette.textMuted,
        label: activa ? 'Activa' : 'Sin rutina', // i18n
      ),
    );
  }
}

/// Celda «Nutrición»: chip compacto (dot + label) que deriva su estado del
/// overview cross-alumno de Fase 6 (`nutricionEntriesProvider`) — REUTILIZA
/// esa agregación en vez de cruzar `nutritionPlanProvider` por fila (no
/// duplica el patrón N-streams ya resuelto ahí, ADR-F6-04). "Con plan" si
/// existe una entry para este alumno con un `NutritionPlan` resuelto (no
/// loading); "Sin plan" en cualquier otro caso — incluye ausencia de entry
/// (alumno no `active`, la agregación sólo cubre vínculos activos), loading
/// o error (mismo criterio "barato" que `_RutinaCell`/último entreno). Tap
/// navega al detalle del alumno (`/alumnos/:athleteId`, deep-link al editor
/// real de Fase 3 — NO se edita en el hub, ADR-F6-03), envuelto en `InkWell`
/// para que absorba el gesto y no dispare el `onRowTap` de la fila.
class _NutricionCell extends ConsumerWidget {
  const _NutricionCell({required this.athleteId, required this.palette});

  final String athleteId;
  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(nutricionEntriesProvider).valueOrNull ?? const [];
    NutricionEntry? entry;
    for (final e in entries) {
      if (e.link.athleteId == athleteId) {
        entry = e;
        break;
      }
    }
    final conPlan = entry != null && !entry.planLoading && entry.plan != null;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: () => context.go('/alumnos/$athleteId'),
      child: _DotLabel(
        color: conPlan ? palette.accent : palette.textMuted,
        label: conPlan ? 'Con plan' : 'Sin plan', // i18n
      ),
    );
  }
}

/// Info derivada para la celda «Vencimiento»: agrega los pagos del alumno vía
/// [pagoEstadoOf] (mismo criterio dueAt-aware que Pagos, ADR-PGW-002/
/// REQ-VENC-11) y resuelve el peor caso — un pago vencido tiene prioridad
/// sobre cualquier pago por vencer (más urgente, no tiene sentido mostrar una
/// fecha futura si ya hay una cuota vencida); sin pago vencido, se toma el
/// `dueAt` más próximo entre los pagos por vencer (los legacy sin `dueAt` no
/// aportan fecha); sin ningún pago del alumno, no hay cuota
/// (`vencido: false, proximaFecha: null` → celda "—").
///
/// Pública para testear sin pump (mismo patrón que [estadoForLink] /
/// [lastWorkoutLabel]).
({bool vencido, DateTime? proximaFecha}) vencimientoInfoFor(
  List<Payment> payments,
  String athleteId,
  DateTime now,
) {
  var vencido = false;
  DateTime? proxima;
  for (final p in payments) {
    if (p.athleteId != athleteId) continue;
    final estado = pagoEstadoOf(p, now).estado;
    if (estado == PagoEstado.vencido) {
      vencido = true;
    } else if (estado == PagoEstado.porVencer && p.dueAt != null) {
      final dueAt = p.dueAt!;
      if (proxima == null || dueAt.isBefore(proxima)) proxima = dueAt;
    }
  }
  return (vencido: vencido, proximaFecha: vencido ? null : proxima);
}

/// Celda «Vencimiento»: badge "Vencido" (danger, mismo token que
/// `AlumnoEstado.conDeuda`) si el alumno tiene al menos un pago vencido; si
/// no, la fecha del próximo vencimiento pendiente (formato "22 mayo", mismo
/// `fmtDayMonth` que la sección Pagos); "—" si no tiene ninguna cuota
/// pendiente. Deriva de `pagosBucketsProvider` — a diferencia de
/// `pagosPorCobrarProvider` (usado en `_LinksLoaded` sólo para derivar el
/// estado "Con deuda"), éste SÍ trae `dueAt` (ver plan-fase9).
class _VencimientoCell extends ConsumerWidget {
  const _VencimientoCell({required this.athleteId, required this.palette});

  final String athleteId;
  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payments =
        ref.watch(pagosBucketsProvider).valueOrNull?.todos ?? const [];
    final info =
        vencimientoInfoFor(payments, athleteId, DateTime.now().toUtc());

    if (info.vencido) {
      return _DotLabel(color: palette.danger, label: 'Vencido'); // i18n
    }
    final proxima = info.proximaFecha;
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        proxima == null ? '—' : fmtDayMonth(proxima), // i18n
        style: TextStyle(
          color: proxima == null ? palette.textMuted : palette.textPrimary,
          fontSize: 13,
        ),
      ),
    );
  }
}

/// Dot + texto — celda compacta compartida por Estado/Rutina/Nutrición/
/// Vencimiento (mismo idioma visual, columna angosta de la fila fija a
/// `TreinoTableTokens.rowHeight`). Extraído tras el 2do copy-paste
/// (Estado→Rutina) — regla del kit (ADR-A3-04).
class _DotLabel extends StatelessWidget {
  const _DotLabel({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
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
              label,
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

  /// Resuelve (o crea) el chat 1-1 con el alumno vía [chatForOtherUidProvider]
  /// — mismo provider que la tab «Chat» del detalle — y navega al Chat global
  /// del Coach Hub dejando la conversación ya seleccionada
  /// (`selectedChatIdProvider`, mismo mecanismo que usa `ChatListPane` al
  /// tocar un ítem de la lista).
  Future<void> _openChat(BuildContext context, WidgetRef ref) async {
    final chat = await ref.read(chatForOtherUidProvider(link.athleteId).future);
    ref.read(selectedChatIdProvider.notifier).state = chat.chatId;
    if (!context.mounted) return;
    context.go('/chat');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final status = link.status;
    // Acciones rápidas — SIEMPRE visibles (no dependen del estado del
    // vínculo, a diferencia de pausar/reanudar/terminar más abajo): el kit
    // (`CoachHubDataTable`) no propaga hover a `cellWidgets`, así que no hay
    // forma de revelarlas sólo al pasar el mouse — quedan fijas con tooltip.
    final buttons = <Widget>[
      _IconAction(
        icon: TreinoIcon.chat,
        tooltip: 'Chat', // i18n
        color: palette.textMuted,
        onPressed: () => _openChat(context, ref),
      ),
      _IconAction(
        icon: TreinoIcon.dumbbell,
        tooltip: 'Rutinas', // i18n
        color: palette.textMuted,
        onPressed: () => context.go('/rutinas/${link.athleteId}'),
      ),
      _IconAction(
        icon: TreinoIcon.money,
        tooltip: 'Registrar pago', // i18n
        color: palette.textMuted,
        // Reusa `registrarPago` de la sección Pagos (mismo diálogo +
        // `paymentRepositoryProvider.add`) — evita duplicar el flujo de alta
        // de un pago ad-hoc ya resuelto ahí.
        onPressed: () => registrarPago(context, ref, link.athleteId),
      ),
    ];
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
    // Hasta 5 botones conviven en la columna «Acciones» (3 acciones rápidas
    // siempre visibles + hasta 2 de vínculo pausar/reanudar + terminar). Con
    // Material 3 (ADR de tema, `useMaterial3: true`), `constraints`/`padding`
    // por sí solos NO alcanzan: `MaterialTapTargetSize.padded` (default del
    // tema) fuerza un tap target mínimo de 48x48 vía `_InputPadding` —
    // invisible pero SÍ cuenta para el layout del `Row` padre, y overflowea
    // igual aunque el `IconButton` se vea de 32x32. `tapTargetSize:
    // shrinkWrap` en el `style` es lo que realmente reduce el tamaño de caja
    // que el botón reporta al `Row`.
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 18, color: color),
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
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
