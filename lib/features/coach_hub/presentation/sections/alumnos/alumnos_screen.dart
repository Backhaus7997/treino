import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';
import 'package:treino/core/widgets/motion/treino_state_switcher.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/data/trainer_link_promotion_service.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_entitlement.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/chat/abrir_chat_con_alumno.dart';
import 'package:treino/features/coach_hub/presentation/sections/nutricion/nutricion_providers.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/marcar_pagado_actions.dart'
    show registrarPago;
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/pagos_buckets_provider.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/pagos_estado.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/payment_format.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';
import 'package:treino/features/coach_hub/presentation/widgets/invite_athlete_dialog.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/plan_limit_paywall.dart';
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
enum AlumnoEstado { activo, conDeuda, pausado, bloqueado, inactivo }

extension AlumnoEstadoX on AlumnoEstado {
  String label(AppL10n l10n) => switch (this) {
        AlumnoEstado.activo => l10n.coachHubAlumnosStatusActive,
        AlumnoEstado.conDeuda => l10n.coachHubAlumnosStatusDebt,
        AlumnoEstado.pausado => l10n.coachHubAlumnosStatusPaused,
        AlumnoEstado.bloqueado => l10n.coachHubAlumnosStatusBlocked,
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
        // Magenta, distinto del danger de «con deuda»: no es un problema de
        // pago DEL ALUMNO, es la suscripcion del PF la que caduco.
        AlumnoEstado.bloqueado => p.highlight,
        AlumnoEstado.inactivo => p.textMuted,
      };
}

/// Filtro de estado del roster (chips).
enum RosterFiltro { todos, activos, pausados, bloqueados, inactivos, conDeuda }

/// Estado compuesto de un link, derivado de su `status` + billing.
AlumnoEstado estadoForLink(TrainerLink link, Set<String> conDeudaIds) {
  // El bloqueo MANDA sobre cualquier otro estado: es lo unico accionable y lo
  // unico que explica por que el alumno no cuenta para el limite. Mostrar
  // «Activo» sobre un vinculo bloqueado seria mentir.
  if (link.entitlement == TrainerLinkEntitlement.blocked) {
    return AlumnoEstado.bloqueado;
  }
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
      // «Todos» son TUS ALUMNOS, no el archivo historico. Un vinculo
      // `terminated` es un ex-alumno: no lo entrenas, no le cobras, y sus
      // celdas de ultimo entreno / rutina / plan / vence estan todas vacias.
      //
      // Con 12 vinculos de los cuales 10 estaban terminados, el roster abria
      // en 12 filas donde 10 no tenian un solo dato util y cuatro de las siete
      // columnas quedaban en blanco. El PF lo reporto como «muchos datos de
      // mas que no me sirven de nada» y como «todos los inactivos por que los
      // querria ver».
      //
      // La salida sigue a un click: el chip «Inactivos» los muestra, y sigue
      // contandolos aunque «Vigentes» ya no los liste.
      //
      // EL CHIP SE LLAMA «VIGENTES», NO «TODOS», y ese es el punto.
      //
      // La logica de aca abajo esta bien y este comentario la defiende bien.
      // El problema era la PALABRA: un chip que dice literalmente «Todos» y
      // muestra 2 al lado de «Inactivos 10», con un hero que arriba dice «12
      // en total», se lee como un bug de conteo aunque no lo sea. El usuario
      // no tiene forma de saber que «todos» excluye a los inactivos — la
      // palabra le promete lo contrario.
      //
      // NO se toco el DEFAULT del filtro (sigue en `todos`) a proposito.
      // Arrancar en «Activos» parece la solucion obvia y es peor: los chips
      // son DISJUNTOS —un alumno con deuda cuenta solo bajo «Con deuda»—, asi
      // que el roster abriria escondiendo justo a los que hay que mirar.
      RosterFiltro.todos => e != AlumnoEstado.inactivo,
      RosterFiltro.activos => e == AlumnoEstado.activo,
      RosterFiltro.pausados => e == AlumnoEstado.pausado,
      RosterFiltro.bloqueados => e == AlumnoEstado.bloqueado,
      RosterFiltro.inactivos => e == AlumnoEstado.inactivo,
      RosterFiltro.conDeuda => e == AlumnoEstado.conDeuda,
    };

final _filtroProvider =
    StateProvider.autoDispose<RosterFiltro>((_) => RosterFiltro.todos);
final _queryProvider = StateProvider.autoDispose<String>((_) => '');

/// Pagina visible del roster, 0-based.
///
/// Se resetea a 0 cuando cambia el filtro o la busqueda: quedarse en la
/// pagina 3 despues de cambiar de chip deja al PF mirando un tramo del medio
/// de una lista distinta —o una tabla vacia, si esa lista tiene 2 filas— sin
/// nada que explique por que arranca ahi.
final _pageProvider = StateProvider.autoDispose<int>((_) => 0);

/// Modo de visualización del roster (toggle Tabla / Cards, mockup
/// view-general.png vs view-general-cards.png). Viene de #347; la ronda de
/// revisión enriqueció la TABLA con columnas nuevas, y el modo cards sigue
/// mostrando el resumen.
enum AlumnosViewMode { tabla, cards }

final _viewModeProvider =
    StateProvider.autoDispose<AlumnosViewMode>((_) => AlumnosViewMode.tabla);

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
    // NO hay `TreinoStateSwitcher` acá, y es a propósito.
    //
    // Había dos anidados —uno por los links, otro por los perfiles— y el de
    // adentro envolvía la PANTALLA ENTERA, no la tabla. Cuando la key pasaba
    // de `loading` a `data`, Flutter desmontaba el `_RosterFrame` viejo y
    // montaba uno nuevo, y durante los 240 ms de `AppMotion.base` los dos
    // quedaban pintados encima: dos hero «ALUMNOS», dos botones «Nuevo
    // alumno», dos filas de chips, dos cabeceras de tabla. Medido en
    // producción: ~205 ms con el frame duplicado, 3 corridas de 3.
    //
    // El agravante era que el frame nuevo volvía a correr su entrada
    // escalonada: `TreinoFadeSlideIn` es one-shot POR STATE, y el State se iba
    // con el desmonte. Hero, chips y buscador hacían fade + slide de 12 px
    // otra vez, encima de la copia vieja apagándose. Eso es el parpadeo.
    //
    // El chrome no depende del estado de carga: no tiene por qué desmontarse.
    // Sólo la TABLA cross-fadea, y lo hace adentro de `_RosterFrame`.
    return _LinksLoaded(linksAsync: ref.watch(trainerLinksStreamProvider));
  }
}

/// Resuelve perfiles + gyms + deuda y colapsa los DOS `AsyncValue` (links y
/// perfiles) en un único estado de tabla.
///
/// Se construye siempre, en los tres estados — por eso recibe el `AsyncValue`
/// y no la lista ya resuelta. Mientras los links no llegaron trabaja con una
/// lista vacía y le avisa al hero que todavía no sabe cuántos hay.
class _LinksLoaded extends ConsumerWidget {
  const _LinksLoaded({required this.linksAsync});

  final AsyncValue<List<TrainerLink>> linksAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final links = linksAsync.valueOrNull ?? const <TrainerLink>[];

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

    // Los dos asyncs, colapsados en UN estado de tabla. El de links manda:
    // si falló, el mensaje de perfiles sobra.
    final (String tableState, String? errorMessage, VoidCallback? onRetry) =
        switch ((linksAsync, profilesAsync)) {
      (final l, _) when l.hasError => (
          'error',
          l10n.coachHubAlumnosLoadError,
          () => ref.invalidate(trainerLinksStreamProvider),
        ),
      (_, final p) when p.hasError => (
          'error',
          l10n.coachHubAlumnosProfilesLoadError,
          () => ref.invalidate(userPublicProfilesBatchProvider(ids.join(','))),
        ),
      (final l, final p) when !l.hasValue || !p.hasValue => (
          'loading',
          null,
          null,
        ),
      _ => ('data', null, null),
    };

    return _RosterFrame(
      roster: rosterWithEstado,
      profiles: profilesAsync.valueOrNull ?? const {},
      gymNameById: gymNameById,
      // `null`, no `0`. En la entrada fría el hero afirmaba «ALUMNOS 0» antes
      // de decir «ALUMNOS 12»: un dato falso durante medio segundo es peor que
      // ningún dato.
      rosterCount: linksAsync.hasValue ? rosterWithEstado.length : null,
      tableState: tableState,
      tableLoading: tableState == 'loading',
      errorMessage: errorMessage,
      onRetry: onRetry,
    );
  }
}

/// Header (título CAPS + subtítulo) + filtros + búsqueda + tabla.
///
/// El bloque header/filtros/búsqueda entra con `TreinoFadeSlideIn` staggered
/// (índices 0/1/2) UNA sola vez: este frame se monta una vez por visita y ya
/// no lo desmonta ningún switcher de arriba. El cross-fade de estados vive
/// adentro y envuelve **sólo la tabla**.
class _RosterFrame extends ConsumerWidget {
  const _RosterFrame({
    required this.roster,
    required this.profiles,
    required this.gymNameById,
    this.rosterCount,
    this.tableState = 'data',
    this.tableLoading = false,
    this.errorMessage,
    this.onRetry,
  });

  final List<_RosterEntry> roster;
  final Map<String, UserPublicProfile> profiles;
  final Map<String, String> gymNameById;

  /// Cuántos alumnos hay — `null` mientras todavía no se sabe.
  ///
  /// No es `roster.length`: durante la carga `roster` está vacío y eso NO
  /// significa «tenés 0 alumnos», significa «todavía no sé». El hero omite el
  /// número en vez de afirmar un cero que dura medio segundo y es mentira.
  final int? rosterCount;

  /// Estado del cross-fade de la tabla (`loading` / `error` / `data`).
  final String tableState;
  final bool tableLoading;
  final String? errorMessage;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    // `visibles` es la lista COMPLETA que pasa el filtro y la busqueda —
    // sigue siendo la que cuenta el pie y la que decide si hay mas de una
    // pagina. `enPagina` es lo unico que se dibuja.
    final page = ref.watch(_pageProvider);
    final enPagina = pageOf(visibles, page: page);

    final activos = roster.where((e) => e.estado == AlumnoEstado.activo).length;

    // Breakpoint responsive (900px, mismo estándar que el resto del hub —
    // ver `agenda_web_screen.dart`): el `LayoutBuilder` capta el ancho
    // ANTES del padding horizontal propio de esta sección, igual que el
    // patrón de agenda, para que el corte coincida con el ancho real de
    // pantalla/panel y no con el ancho ya recortado por el padding interno.
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        // Segundo umbral. Los flex del roster estaban calibrados contra el
        // PEOR caso (900 px, el propio breakpoint, donde el header «ÚLTIMO
        // ENTRENO» desbordaba). Arriba de 1200 px esa calibración deja de
        // tener sentido y empieza a hacer daño — ver `_RosterTable.columns`.
        final roomy = constraints.maxWidth >= 1200;
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
                child: CoachHubSectionHero(
                  title: l10n.coachHubAlumnosTitle,
                  count: rosterCount,
                  subtitle: rosterCount == null
                      ? null
                      : l10n.coachHubAlumnosSummary(rosterCount!, activos),
                  actions: [
                    CoachHubHeroAction(
                      label: l10n.dashboardQuickActionNuevoAlumno,
                      icon: TreinoIcon.plus,
                      // Mismo destino que la quick action del dashboard: el
                      // alta arranca por el link de invitación, no por la
                      // lista de los que ya tenés.
                      onTap: () => showInviteAthleteDialog(context),
                      primary: true,
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
                child: const Row(
                  children: [
                    Expanded(child: _SearchField()),
                    SizedBox(width: AppSpacing.s12),
                    _ViewModeToggle(),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s14),
              // ÚNICO cross-fade de la pantalla, y envuelve SÓLO esto.
              //
              // Antes el switcher estaba arriba de todo y remontaba el frame
              // entero; el header, los chips y el buscador se desmontaban con
              // él aunque no dependan del estado de carga. Acá adentro, lo
              // único que cambia entre loading/error/data es la tabla, que es
              // exactamente lo que tiene que cambiar.
              TreinoStateSwitcher(
                childKey: ValueKey('alumnos_tabla_$tableState'),
                // #347: el toggle Tabla/Cards. La tabla es la enriquecida por
                // la ronda de revisión (último entreno, rutina, nutrición,
                // vencimiento, acciones rápidas); el modo cards muestra el
                // resumen, que es para lo que existe.
                child: ref.watch(_viewModeProvider) == AlumnosViewMode.tabla
                    ? _RosterTable(
                        visibles: enPagina,
                        profiles: profiles,
                        gymNameFor: gymNameFor,
                        loading: tableLoading,
                        errorMessage: errorMessage,
                        onRetry: onRetry,
                        wide: wide,
                        roomy: roomy,
                        emptyMessage: roster.isEmpty
                            ? l10n.coachHubAlumnosEmpty
                            : l10n.coachHubAlumnosEmptyFiltered,
                      )
                    : _RosterCardsGrid(
                        links: [for (final e in enPagina) e.link],
                        profiles: profiles,
                        // La deuda ya viene resuelta en el estado compuesto del
                        // entry, así que no hace falta el mapa aparte que usaba la
                        // versión anterior de la grilla.
                        conDeudaIds: {
                          for (final e in enPagina)
                            if (e.estado == AlumnoEstado.conDeuda)
                              e.link.athleteId,
                        },
                        deudaByAthlete: const {},
                        gymNameFor: gymNameFor,
                      ),
              ),
              // Un solo pie para los dos modos: el paginado es de la LISTA,
              // no de como se la esta dibujando. Se esconde solo con una
              // pagina, asi que hoy —con 12 alumnos— no aparece.
              CoachHubPager(
                total: visibles.length,
                page: page,
                onPageChanged: (p) =>
                    ref.read(_pageProvider.notifier).state = p,
              ),
            ],
          ),
        );
      },
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
        (RosterFiltro.bloqueados, l10n.coachHubAlumnosFilterBloqueados),
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
        if (f != null) {
          ref.read(_filtroProvider.notifier).state = f;
          ref.read(_pageProvider.notifier).state = 0;
        }
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
      onChanged: (v) {
        ref.read(_queryProvider.notifier).state = v;
        ref.read(_pageProvider.notifier).state = 0;
      },
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
    required this.wide,
    required this.roomy,
    this.onRetry,
  });

  final List<_RosterEntry> visibles;
  final Map<String, UserPublicProfile> profiles;
  final String? Function(TrainerLink) gymNameFor;
  final bool loading;
  final String? errorMessage;
  final String emptyMessage;
  final VoidCallback? onRetry;

  /// `true` con >=900px de ancho disponible (breakpoint del hub). En angosto
  /// colapsan las columnas agregadas por esta revisión (último entreno,
  /// rutina, nutrición, vencimiento) y sólo quedan alumno/estado/acciones —
  /// las 3 que el mockup original ya trataba como núcleo del roster. Las
  /// celdas colapsadas siguen viajando en `cellWidgets`/`cells` (no se
  /// filtran los rows): `CoachHubDataTable` sólo renderiza lo que aparece en
  /// `columns`, así que basta con no declarar la columna acá — no hace falta
  /// tocar el kit compartido (prohibido para esta pieza).
  final bool wide;

  /// `true` con >=1200px de tabla — hay lugar para que ALUMNO respire.
  ///
  /// Los flex de abajo nacieron calibrados contra el peor caso (900px, con
  /// las 7 columnas a la vez y «ÚLTIMO ENTRENO» desbordando por 43px). Esa
  /// calibración, aplicada en desktop, le regala 275px a una celda que dice
  /// «Hace 5 días» y le deja 142 a ALUMNO — de los cuales el avatar (36) y su
  /// gap (12) se comen casi la mitad. El nombre se queda con ~66px y sale
  /// «Mateo Pr...»: el dato más importante de la fila, truncado a la mitad,
  /// mientras la columna de la fecha desperdicia 200px.
  ///
  /// Con lugar, la calibración es otra. No es un caso especial: es una tabla
  /// responsive haciendo lo que tiene que hacer.
  final bool roomy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    // Ventana de 30 días, día-truncada (UTC) — se computa UNA vez acá (no por
    // fila) para que la family key de finishedInWindowByUidProvider quede
    // estable entre rebuilds (mismo criterio que inactivosProvider).
    // Ventana de dias en ART (#671): con UTC, "Ultimo entreno" de alguien
    // que entreno hoy a la tarde se leia "Ayer" pasadas las 21:00.
    final now = argentinaNow();
    final todayStart = DateTime.utc(now.year, now.month, now.day);
    final windowFrom = todayStart.subtract(const Duration(days: 30));
    final windowTo = todayStart.add(const Duration(days: 1));

    return CoachHubDataTable(
      columns: [
        // Densidad de fila revisada para esta pieza (responsive-gates): los
        // flex de TODAS las columnas se recalibraron a un común denominador
        // más fino (suman 114) — ya no alcanza con enteros chicos (1-4) para
        // que el header de cada columna respire con las 7 columnas visibles
        // a la vez en el peor caso (900px, el propio breakpoint: con los
        // flex 3/1/2/1/1/1/2 originales, el header más largo del roster
        // («ÚLTIMO ENTRENO») desbordaba por 43px ahí). «Alumno» ya trunca
        // con ellipsis (`_AlumnoCell`, avatar 36 + gap 12 fijos, el resto es
        // Flexible) — absorbe el recorte sin riesgo real de overflow (a
        // diferencia del resto, cuyo header es un `Text` sin ellipsis en el
        // kit compartido).
        //
        // Los flex viven en DOS calibraciones (ver `roomy`). Con lugar, el
        // nombre —el dato que identifica la fila— se lleva lo que necesita;
        // en angosto manda no desbordar el header más largo.
        CoachHubColumn(
          key: 'alumno',
          label: l10n.coachHubAlumnosColumnStudent,
          flex: roomy ? 26 : 14,
        ),
        // «ESTADO» (l10n, 6 mayúsculas) necesita más aire que un flex:1
        // sobre 11 columnas totales — mismo criterio que «Rutina».
        CoachHubColumn(
          key: 'estado',
          label: l10n.coachHubAlumnosColumnStatus,
          flex: roomy ? 12 : 14,
        ),
        // Responsive (breakpoint 900px): último entreno/rutina/nutrición/
        // vencimiento colapsan en angosto — alumno/estado/acciones quedan
        // como el núcleo siempre visible del roster. En angosto hay bastante
        // menos flex total compitiendo por el ancho disponible, así que cada
        // columna que queda se lleva más espacio relativo aunque comparta
        // los mismos números de flex que en ancho (mismo mecanismo de
        // `Expanded(flex:)` del kit, sin tocarlo).
        if (wide) ...[
          // «ÚLTIMO ENTRENO» (l10n, 14 caracteres con espacio) es el header
          // más largo del roster — el que más flex necesita.
          //
          // Los 27 eran para que el header no desbordara a 900px. En desktop
          // esos 27 son 275px para mostrar «Hace 5 días», mientras el nombre
          // del alumno trunca a los 66. Con lugar bajan a 16 y el header
          // sigue entrando entero.
          CoachHubColumn(
            key: 'ultimoEntreno',
            label: l10n.coachHubAlumnosColumnLastWorkout,
            flex: roomy ? 16 : 27,
          ),
          CoachHubColumn(
              key: 'rutina', label: 'Rutina', flex: roomy ? 13 : 14), // i18n
          // Header corto ("Plan") en vez de "Nutrición": el ancho de columna
          // disponible (flex compartido con el resto de la fila, sin
          // ellipsis en `_HeaderCell` del kit) no entra con la palabra
          // completa — el chip de la celda ("Con plan"/"Sin plan") ya deja
          // clara la semántica. "Plan" (4 caracteres) es el header más corto
          // del roster — el que menos flex necesita.
          const CoachHubColumn(
              key: 'nutricion', label: 'Plan', flex: 12), // i18n
          // Header corto ("Vence") por la misma razón que "Plan"/"Rutina".
          CoachHubColumn(
              key: 'vencimiento', label: 'Vence', flex: roomy ? 12 : 13),
        ],
        // «ACCIONES» (l10n) + hasta 5 icon-buttons en la fila (pieza
        // «acciones» previa) — necesita el flex más alto después de
        // «Último entreno» para que los 5 íconos no se apiñen.
        CoachHubColumn(
          key: 'acciones',
          label: l10n.coachHubAlumnosColumnActions,
          // Con `roomy` entran los 4 botones de 24px más sus 3 separaciones
          // de 8 (120px) con margen, y sobra menos desperdicio que con 20.
          flex: roomy ? 17 : 20,
          // Los botones ya se dibujaban a la derecha; el rótulo se quedaba a
          // la izquierda del slot, a media tabla de distancia. Declararlo acá
          // los mueve a los dos.
          align: CoachHubColumnAlign.end,
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
/// `assignedRoutinesByTrainerProvider` — "Activa" si el alumno tiene al
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
    final trainerId = ref.watch(currentUidProvider) ?? '';
    final routines = ref
            .watch(assignedRoutinesByTrainerProvider(
              (trainerId: trainerId, athleteId: athleteId),
            ))
            .valueOrNull ??
        const [];
    final activa = routines.any((r) => r.status == RoutineStatus.active);
    return _TappableDotLabel(
      color: activa ? palette.accent : palette.textMuted,
      label: activa ? 'Activa' : 'Sin rutina', // i18n
      // `push` y no `go`: la pantalla de rutinas del alumno tiene flecha
      // atras, y `go` REEMPLAZA la entrada de historial — llegando desde aca,
      // esa flecha no tenia a donde volver y quedaba muerta. El PF: «el boton
      // de ir para atras no funciona».
      onTap: () => context.push('/rutinas/$athleteId'),
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
    return _TappableDotLabel(
      color: conPlan ? palette.accent : palette.textMuted,
      label: conPlan ? 'Con plan' : 'Sin plan', // i18n
      onTap: () => context.go('/alumnos/$athleteId'),
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
        // Bucket de DIA en ART (#671): un vencimiento 31/07 se leia
        // "1 agosto".
        vencimientoInfoFor(payments, athleteId, argentinaNow());

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

/// Variante tappable de [_DotLabel] — usada por `_RutinaCell`/
/// `_NutricionCell` (tap navega a otra pantalla, absorbiendo el gesto para
/// que no dispare el `onRowTap` de la fila).
///
/// A diferencia de envolver `InkWell(child: _DotLabel(...))` (como antes de
/// la pieza responsive-gates), acá el `Align` queda AFUERA del `InkWell`: el
/// `InkWell` sólo envuelve el `Row` de contenido (`mainAxisSize: min`), así
/// que su área tappable es del tamaño del dot+label, no de toda la celda. El
/// `Align` (fuera) sigue posicionando ese contenido angosto a la izquierda
/// dentro del ancho completo de la columna. Bug real encontrado al recalibrar
/// los flex de columna para el breakpoint de 900px: con `InkWell` envolviendo
/// `_DotLabel` (que internamente ya usaba `Align`), el `InkWell` heredaba el
/// ancho COMPLETO de la celda (el `Align` interno se expande a llenar el
/// espacio tight que le da el `Padding`/`Expanded` del kit) — cualquier tap
/// en el espacio vacío a la derecha del label (no sólo sobre el texto) caía
/// dentro del `InkWell` y navegaba, en vez de burbujear al tap de la fila.
/// Eso rompió un test pre-existente (tap en el centro de la fila, que ahora
/// caía dentro de la columna Rutina/Nutrición al mover los flex).
class _TappableDotLabel extends StatelessWidget {
  const _TappableDotLabel({
    required this.color,
    required this.label,
    required this.onTap,
  });

  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onTap,
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
      ),
    );
  }
}

class _RowActions extends ConsumerStatefulWidget {
  const _RowActions({required this.link, required this.palette});

  final TrainerLink link;
  final AppPalette palette;

  @override
  ConsumerState<_RowActions> createState() => _RowActionsState();
}

class _RowActionsState extends ConsumerState<_RowActions> {
  // Reanudar puede fallar el gate de peso ponderado (paywall Fase 7, PR4),
  // asi que ya no es fire-and-forget: necesita estado para no permitir
  // doble submit y para poder avisar cuando el server rechaza.
  bool _busy = false;

  Future<void> _pause(BuildContext context, WidgetRef ref) async {
    final l10n = AppL10n.of(context);
    final ok = await _confirmAction(
      context,
      title: l10n.coachHubDashboardPauseLinkTitle,
      body: l10n.coachHubDashboardPauseLinkBody,
      confirmLabel: l10n.coachHubActionPause,
    );
    if (!ok) return;
    await ref.read(trainerLinkRepositoryProvider).pause(widget.link.id);
  }

  Future<void> _resume() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = AppL10n.of(context);
    try {
      await ref
          .read(trainerLinkPromotionServiceProvider)
          .resume(widget.link.id);
    } on LinkPromotionFailure$PlanLimitReached catch (failure) {
      if (!mounted) return;
      setState(() => _busy = false);
      unawaited(
        showPlanLimitPaywall(
          context,
          currentTier: failure.tier,
          reason: failure.reason == 'subscription-inactive'
              ? PlanLimitReason.subscriptionInactive
              : PlanLimitReason.planLimit,
          // El Coach Hub SI tiene vista de facturacion; la app movil no, y
          // por eso el default es null (ver showPlanLimitPaywall).
          billingRoute: '/ajustes',
        ),
      );
      return;
    } on LinkPromotionFailure$PromotionPrecondition {
      if (!mounted) return;
      setState(() => _busy = false);
      _showError(l10n.coachHubDashboardResumePrecondition);
      return;
    } catch (_) {
      // Catch-all a proposito, NO acotado a LinkPromotionFailure (QA H5):
      // lo que quede afuera de la jerarquia sellada igual tiene que
      // resetear _busy y avisar, o la accion queda muerta sin explicacion.
      if (!mounted) return;
      setState(() => _busy = false);
      _showError(l10n.coachHubDashboardResumeUnavailable);
      return;
    }
    if (mounted) setState(() => _busy = false);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

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
        .terminate(widget.link.id, reason: 'trainer-terminated');
  }

  /// Resuelve (o crea) el chat 1-1 con el alumno vía [chatForOtherUidProvider]
  /// — mismo provider que la tab «Chat» del detalle — y navega al Chat global
  /// del Coach Hub dejando la conversación ya seleccionada
  /// (`selectedChatIdProvider`, mismo mecanismo que usa `ChatListPane` al
  /// tocar un ítem de la lista).
  Future<void> _openChat(BuildContext context, WidgetRef ref) =>
      abrirChatConAlumno(context, ref, widget.link.athleteId);

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final status = widget.link.status;
    // Acciones rápidas — SIEMPRE visibles (no dependen del estado del
    // vínculo, a diferencia de pausar/reanudar/terminar más abajo): el kit
    // (`CoachHubDataTable`) no propaga hover a `cellWidgets`, así que no hay
    // forma de revelarlas sólo al pasar el mouse — quedan fijas con tooltip.
    final buttons = <Widget>[
      _IconAction(
        icon: TreinoIcon.chat,
        tooltip: 'Chat', // i18n
        color: widget.palette.textMuted,
        onPressed: () => _openChat(context, ref),
      ),
      _IconAction(
        icon: TreinoIcon.dumbbell,
        tooltip: 'Rutinas', // i18n
        color: widget.palette.textMuted,
        // `push` por el mismo motivo que el tap de la card: con `go` la
        // flecha atras de la pantalla de rutinas queda sin destino.
        onPressed: () => context.push('/rutinas/${widget.link.athleteId}'),
      ),
      _IconAction(
        icon: TreinoIcon.money,
        tooltip: 'Registrar pago', // i18n
        color: widget.palette.textMuted,
        // Reusa `registrarPago` de la sección Pagos (mismo diálogo +
        // `paymentRepositoryProvider.add`) — evita duplicar el flujo de alta
        // de un pago ad-hoc ya resuelto ahí.
        onPressed: () => registrarPago(context, ref, widget.link.athleteId),
      ),
    ];
    // #568: las operaciones de VINCULO (pausar / reanudar / terminar) van en
    // el menú ⋮, no sueltas en la fila. Ese issue existió justamente porque la
    // columna de acciones se llenaba de íconos y quedaba muerta para alumnos
    // inactivos. Los tres accesos rápidos de arriba sí son directos: son
    // frecuentes y no destructivos.
    final menuItems = <PopupMenuEntry<VoidCallback>>[];
    if (status == TrainerLinkStatus.active) {
      menuItems.add(PopupMenuItem(
        value: () => _pause(context, ref),
        child: Text(l10n.coachHubActionPause),
      ));
    } else if (status == TrainerLinkStatus.paused) {
      menuItems.add(PopupMenuItem(
        value: () => _resume(),
        child: Text(l10n.coachHubActionResume),
      ));
    }
    if (status == TrainerLinkStatus.active ||
        status == TrainerLinkStatus.paused) {
      menuItems.add(PopupMenuItem(
        value: () => _terminate(context, ref),
        child: Text(l10n.coachHubActionTerminate),
      ));
    }
    if (menuItems.isNotEmpty) {
      buttons.add(_menuButton(l10n, items: menuItems));
    } else {
      // Hueco del ancho del ⋮ que no va. La columna esta alineada a la
      // derecha, asi que sin esto las filas sin operaciones de vinculo
      // —terminadas, sin acceso— corren sus tres iconos hacia afuera y la
      // grilla queda dentada. El PF lo reporto como «las acciones quedan
      // feas».
      //
      // Es el MISMO widget, invisible, y no un `SizedBox` con un numero: el
      // ancho real del boton sale de su `padding` mas el tamano del icono, y
      // un 32 escrito a mano ya salio 16px corto en el primer intento. Asi
      // coincide por construccion y sigue coincidiendo si el kit cambia.
      //
      // `maintainInteractivity` queda en false (el default): ocupa lugar, no
      // recibe el mouse ni aparece en el arbol de semantica. Un ⋮
      // deshabilitado seria peor que la ausencia, porque promete algo.
      buttons.add(Visibility(
        visible: false,
        maintainSize: true,
        maintainAnimation: true,
        maintainState: true,
        child: _menuButton(l10n, items: const []),
      ));
    }
    // SEPARACIÓN entre blancos de click.
    //
    // El paso entre botones era exactamente su ancho, o sea CERO píxeles de
    // aire: los targets se tocaban y un desvío de 1 px del cursor cambiaba de
    // acción — con «Terminar vínculo» adentro de una de las cuatro. WCAG 2.2
    // (2.5.8) pide 24x24 **o** separación suficiente; acá se cumplía el
    // mínimo de tamaño justo y se incumplía la separación.
    //
    // Y miden 24, no 32: `visualDensity: compact` resta 2 unidades por eje y
    // cada unidad son 4 px, así que el `minimumSize: Size(32, 32)` de #1062
    // termina en 24x24 efectivos. Por eso no alcanza con agrandar la caja —
    // el alto útil de la fila son 24 px (48 de `rowHeight` menos 12+12 de
    // `cellPaddingV`) y no hay margen para crecer. Lo que sí hay es ancho:
    // con 8 px entre botones la fila pasa de 96 a 120 px y la columna tiene
    // 183.
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.s8),
          buttons[i],
        ],
      ],
    );
  }

  /// El ⋮ de la fila. Se usa DOS veces: visible cuando hay operaciones de
  /// vínculo, e invisible —reservando su ancho— cuando no las hay.
  ///
  /// Estaba duplicado literal entre las dos ramas, con su comentario largo
  /// repetido palabra por palabra. Treinta líneas iguales en dos lugares es
  /// una invitación a cambiar la caja en una rama y no en la otra, que es
  /// exactamente cómo la columna se desalineó en #1062.
  Widget _menuButton(
    AppL10n l10n, {
    required List<PopupMenuEntry<VoidCallback>> items,
  }) =>
      TreinoPopupMenuButton<VoidCallback>(
        tooltip: l10n.coachHubAlumnosRowActionsA11y,
        icon: Icon(TreinoIcon.dotsThree,
            size: 18, color: widget.palette.textMuted),
        // MISMA caja que `_IconAction`, y va por `style` porque es la única
        // perilla que llega: `PopupMenuButton` le reenvía al `IconButton` su
        // `padding`, `iconSize` y `style`, pero NO `constraints` — ese parámetro
        // suyo es para el MENÚ. Sin esto el ⋮ mide 40x24 al lado de los 24x24 de
        // sus tres hermanos, con la píldora de hover saliendo de otro tamaño y
        // otro centro: el PF lo reportó como «todos estos botoncitos están
        // horribles».
        iconSize: 18,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(32, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        onSelected: (action) => action(),
        itemBuilder: (_) => items,
      );
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
    // Antes esto era un `IconButton` con `padding`, `constraints`,
    // `visualDensity` y `tapTargetSize` combinados a mano, y el comentario que
    // vivía acá explicaba —bien— que sin `shrinkWrap` el `_InputPadding` de
    // Material 3 mete 48x48 invisibles que igual cuentan para el layout.
    //
    // Todo eso era conocimiento necesario para escribir UN botón, y lo pagaba
    // cada callsite: en `coach_hub` había 156 botones Material crudos y en el
    // detalle del alumno conviven siete paddings distintos. Ahora lo sabe el
    // kit. Acá sólo queda el tamaño, y `xs` es el que impone la fila: 48 px de
    // `rowHeight` menos 12+12 de `cellPaddingV` son 24 de alto útil.
    return TreinoIconButton(
      icon: icon,
      tooltip: tooltip,
      color: color,
      size: TreinoButtonSize.xs,
      onPressed: onPressed,
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

class _ViewModeToggle extends ConsumerWidget {
  const _ViewModeToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final mode = ref.watch(_viewModeProvider);
    Widget option(AlumnosViewMode m, IconData icon, String label) {
      final selected = m == mode;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => ref.read(_viewModeProvider.notifier).state = m,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? palette.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 15,
                  color: selected
                      ? TreinoButtonTokens.foreground(context)
                      : palette.textMuted),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? TreinoButtonTokens.foreground(context)
                      : palette.textMuted,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          option(AlumnosViewMode.tabla, TreinoIcon.viewTable,
              l10n.coachHubAlumnosViewTable),
          option(AlumnosViewMode.cards, TreinoIcon.viewCards,
              l10n.coachHubAlumnosViewCards),
        ],
      ),
    );
  }
}

class _RosterCardsGrid extends ConsumerWidget {
  const _RosterCardsGrid({
    required this.links,
    required this.profiles,
    required this.conDeudaIds,
    required this.deudaByAthlete,
    required this.gymNameFor,
  });

  final List<TrainerLink> links;
  final Map<String, UserPublicProfile> profiles;
  final Set<String> conDeudaIds;
  final Map<String, int> deudaByAthlete;
  final String? Function(TrainerLink) gymNameFor;

  static const double _targetCardWidth = 300;
  static const double _runSpacing = 12;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final rawColumns =
            ((availableWidth + _runSpacing) / (_targetCardWidth + _runSpacing))
                .floor();
        final columns = rawColumns < 1 ? 1 : rawColumns;
        final totalSpacing = _runSpacing * (columns - 1);
        final cardWidth = (availableWidth - totalSpacing) / columns;
        return Wrap(
          spacing: _runSpacing,
          runSpacing: _runSpacing,
          children: [
            for (final link in links)
              SizedBox(
                width: cardWidth,
                child: _RosterCard(
                  link: link,
                  profile: profiles[link.athleteId],
                  estado: estadoForLink(link, conDeudaIds),
                  gymName: gymNameFor(link),
                  debtAmountArs: deudaByAthlete[link.athleteId],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _RosterCard extends ConsumerWidget {
  const _RosterCard({
    required this.link,
    required this.profile,
    required this.estado,
    required this.gymName,
    required this.debtAmountArs,
  });

  final TrainerLink link;
  final UserPublicProfile? profile;
  final AlumnoEstado estado;
  final String? gymName;
  final int? debtAmountArs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final name = profile?.displayName ?? l10n.coachHubAlumnosNameFallback;
    final trainedToday =
        (ref.watch(finishedTodayByUidProvider(link.athleteId)).valueOrNull ??
                const [])
            .isNotEmpty;
    final color = estado.color(palette);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.go('/alumnos/${link.athleteId}'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: palette.bgCard,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TreinoAvatar(
                    displayName: name,
                    avatarUrl: profile?.avatarUrl,
                    diameter: 44),
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
                          style:
                              TextStyle(color: palette.textMuted, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                Container(
                  width: 9,
                  height: 9,
                  margin: const EdgeInsets.only(top: 4),
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.coachHubAlumnosColumnLastWorkout,
                  style: TextStyle(color: palette.textMuted, fontSize: 11),
                ),
                Text(
                  trainedToday ? l10n.coachHubAlumnosLastWorkoutToday : '—',
                  style: TextStyle(
                    color: trainedToday ? palette.accent : palette.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (debtAmountArs != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  l10n.coachHubAlumnosDebtAmount(fmtArs(debtAmountArs!)),
                  style: TextStyle(
                    color: palette.warning,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
