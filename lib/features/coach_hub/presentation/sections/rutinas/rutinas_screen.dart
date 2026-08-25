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
import 'package:treino/core/widgets/motion/treino_tappable.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/chat/widgets/avatar_color.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/domain/routine_status.dart';

/// Sección «Rutinas» del Coach Hub web.
///
/// Una rutina se asigna a UN alumno, así que el flujo necesita un destino.
/// El sidebar es global (no está parado sobre ningún alumno), por eso esta
/// pantalla es el punto de entrada: lista los alumnos vinculados y, al tocar
/// uno, abre sus rutinas (`/rutinas/:athleteId`) donde el PF ve las que ya le
/// cargó y puede crear o editar. Mismo espíritu que mobile, expuesto desde el
/// menú lateral.
///
/// Redesign (triage list): cada fila ahora también muestra el gimnasio, un
/// estado del vínculo y la cantidad de rutinas ACTIVAS ya asignadas — así el
/// PF ve de un vistazo a quién todavía le falta armar una rutina, sin abrir
/// cada alumno. Mismos patrones visuales que la lista de Alumnos ya
/// rediseñada (avatar de color, pill de estado).
///
/// Filtros/búsqueda/toggle Tabla-Cards (port de Alumnos): a diferencia de
/// Alumnos, acá el eje propio de esta pantalla es la CANTIDAD DE RUTINAS —
/// no hay dimensión de deuda. Por eso el filtro se define localmente
/// (`RutinaFiltro`) en vez de reusar `RosterFiltro` de Alumnos.
class RutinasScreen extends ConsumerWidget {
  const RutinasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final linksAsync = ref.watch(trainerLinksStreamProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TreinoSectionHeader(title: 'Rutinas'), // i18n
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
            childKey: ValueKey(linksAsync.when(
              loading: () => 'loading',
              error: (_, __) => 'error',
              data: (links) => links
                      .where((l) => l.status != TrainerLinkStatus.pending)
                      .isEmpty
                  ? 'empty'
                  : 'data',
            )),
            child: linksAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) =>
                  _muted(palette, 'No pudimos cargar los alumnos.'), // i18n
              data: (links) {
                // Una fila por alumno: colapsamos al link más reciente (el stream
                // viene requestedAt DESC) y excluimos `pending` (esas son
                // solicitudes, todavía no son alumnos).
                final seen = <String>{};
                final athletes = <TrainerLink>[];
                for (final l in links) {
                  if (l.status == TrainerLinkStatus.pending) continue;
                  if (seen.add(l.athleteId)) athletes.add(l);
                }
                if (athletes.isEmpty) {
                  return _muted(
                      palette, 'Todavía no tenés alumnos vinculados.'); // i18n
                }
                return _RutinasRosterView(athletes: athletes);
              },
            ),
          ),
        ],
      ),
    );
  }
}

Widget _muted(AppPalette palette, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(text,
          style: TextStyle(
              fontFamily: AppFonts.barlow,
              color: palette.textMuted,
              fontSize: 14)),
    );

/// Estado simplificado del vínculo para esta lista — a diferencia de
/// `AlumnoEstado` (alumnos_screen.dart) no factoriza deuda: acá solo importa
/// si el vínculo está activo, pausado o inactivo para decidir si tiene
/// sentido armarle una rutina.
enum _LinkEstado { activo, pausado, inactivo }

_LinkEstado _estadoFor(TrainerLinkStatus status) => switch (status) {
      TrainerLinkStatus.active => _LinkEstado.activo,
      TrainerLinkStatus.paused => _LinkEstado.pausado,
      TrainerLinkStatus.terminated ||
      TrainerLinkStatus.pending =>
        _LinkEstado.inactivo,
    };

extension on _LinkEstado {
  String get label => switch (this) {
        _LinkEstado.activo => 'Activo', // i18n
        _LinkEstado.pausado => 'Pausado', // i18n
        _LinkEstado.inactivo => 'Inactivo', // i18n
      };

  Color color(AppPalette p) => switch (this) {
        _LinkEstado.activo => p.accent,
        _LinkEstado.pausado => p.highlight,
        _LinkEstado.inactivo => p.textMuted,
      };
}

/// Filtro de la lista de Rutinas (chips). A diferencia de `RosterFiltro`
/// (Alumnos) no hay `conDeuda` — el eje propio de esta pantalla es la
/// cantidad de rutinas activas asignadas.
enum RutinaFiltro { todos, sinRutina, conRutina, activos, inactivos }

extension on RutinaFiltro {
  String get label => switch (this) {
        RutinaFiltro.todos => 'Todos', // i18n
        RutinaFiltro.sinRutina => 'Sin rutina', // i18n
        RutinaFiltro.conRutina => 'Con rutina', // i18n
        RutinaFiltro.activos => 'Activos', // i18n
        RutinaFiltro.inactivos => 'Inactivos', // i18n
      };
}

/// Un alumno matchea el filtro según:
/// - `todos`/`activos`/`inactivos`: solo dependen del estado del vínculo, ya
///   resuelto sync (no hay red de por medio) — siempre evaluables.
/// - `sinRutina`/`conRutina`: dependen de `activeRoutinesCount`, que puede
///   estar `null` mientras el provider por-alumno todavía está cargando. Un
///   alumno en ese estado NO matchea ninguno de los dos filtros basados en
///   conteo (se excluye de ambos hasta resolver) — así nunca aparece como
///   "Sin rutina" de forma incorrecta solo porque todavía no cargó.
bool _matchesFiltro(
        _LinkEstado estado, int? activeRoutinesCount, RutinaFiltro f) =>
    switch (f) {
      RutinaFiltro.todos => true,
      RutinaFiltro.sinRutina =>
        activeRoutinesCount != null && activeRoutinesCount == 0,
      RutinaFiltro.conRutina =>
        activeRoutinesCount != null && activeRoutinesCount > 0,
      RutinaFiltro.activos => estado == _LinkEstado.activo,
      RutinaFiltro.inactivos => estado == _LinkEstado.inactivo,
    };

final _rutinaFiltroProvider =
    StateProvider.autoDispose<RutinaFiltro>((_) => RutinaFiltro.todos);
final _queryProvider = StateProvider.autoDispose<String>((_) => '');

/// Modo de visualización (toggle Tabla / Cards), mismo patrón que Alumnos.
enum RutinaViewMode { tabla, cards }

final _rutinaViewModeProvider =
    StateProvider.autoDispose<RutinaViewMode>((_) => RutinaViewMode.tabla);

/// Vista con los datos ya resueltos por alumno.
///
/// Antes cada `_AthleteRow` leía su propio perfil y conteo de rutinas. Para
/// poder filtrar/contar por la dimensión de rutinas a nivel de LISTA (chips
/// con contador, ej. "SIN RUTINA · 5") hace falta conocer el estado y el
/// conteo de TODOS los alumnos acá arriba, no fila por fila. Por eso este
/// widget mira (`.watch`) `userPublicProfileProvider` y
/// `assignedRoutinesProvider` una vez por alumno — sí, es un `.family`
/// provider por alumno en un loop en el padre, pero es la única forma de que
/// el padre conozca todo antes de filtrar (mismo costo de red que antes,
/// solo que leído un nivel más arriba).
class _RutinasRosterView extends ConsumerWidget {
  const _RutinasRosterView({required this.athletes});

  final List<TrainerLink> athletes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final filtro = ref.watch(_rutinaFiltroProvider);
    final query = ref.watch(_queryProvider).trim().toLowerCase();
    final viewMode = ref.watch(_rutinaViewModeProvider);

    final profileById = <String, UserPublicProfile?>{};
    final countById = <String, int?>{};
    final estadoById = <String, _LinkEstado>{};
    for (final link in athletes) {
      final athleteId = link.athleteId;
      profileById[athleteId] =
          ref.watch(userPublicProfileProvider(athleteId)).valueOrNull;
      countById[athleteId] = ref
          .watch(assignedRoutinesProvider(athleteId))
          .valueOrNull
          ?.where((r) => r.status == RoutineStatus.active)
          .length;
      estadoById[athleteId] = _estadoFor(link.status);
    }

    String nameFor(String athleteId) {
      final raw = profileById[athleteId]?.displayName ?? '';
      return raw.isEmpty ? 'Alumno' : raw; // i18n
    }

    int countFor(RutinaFiltro f) => athletes
        .where((l) =>
            _matchesFiltro(estadoById[l.athleteId]!, countById[l.athleteId], f))
        .length;

    final visibles = athletes.where((l) {
      final athleteId = l.athleteId;
      if (!_matchesFiltro(
          estadoById[athleteId]!, countById[athleteId], filtro)) {
        return false;
      }
      if (query.isEmpty) return true;
      // Match against the REAL name, not the "Alumno" fallback. If the profile
      // hasn't loaded yet (name null), don't exclude the athlete from search —
      // same loading-safety principle as the count filters (a still-loading
      // row is never wrongly hidden just because its data hasn't arrived).
      final realName = profileById[athleteId]?.displayName;
      if (realName == null || realName.isEmpty) return true;
      return realName.toLowerCase().contains(query);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _FilterBar(filtro: filtro, countFor: countFor)),
            const SizedBox(width: 12),
            const _ViewModeToggle(),
          ],
        ),
        const SizedBox(height: 12),
        _SearchField(),
        const SizedBox(height: 14),
        if (visibles.isEmpty)
          _muted(palette, 'No encontramos alumnos con esos filtros.') // i18n
        else if (viewMode == RutinaViewMode.tabla)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, link) in visibles.indexed)
                // key por athleteId: sin ella el matching de Elements es
                // posicional, y cualquier cambio de la lista visible (filtro,
                // búsqueda, o una inserción del stream) hace que las filas
                // existentes reusen el State one-shot corrido de posición y
                // la última infle una animación nueva — exactamente al revés
                // de la intención.
                TreinoFadeSlideIn(
                  key: ValueKey(link.athleteId),
                  delay: AppMotion.stagger(i),
                  child: _AthleteRow(
                    athleteId: link.athleteId,
                    name: nameFor(link.athleteId),
                    avatarUrl: profileById[link.athleteId]?.avatarUrl,
                    gymName: profileById[link.athleteId]?.gymName,
                    estado: estadoById[link.athleteId]!,
                    activeRoutinesCount: countById[link.athleteId],
                  ),
                ),
            ],
          )
        else
          _RutinasCardsGrid(
            athletes: visibles,
            nameFor: nameFor,
            profileById: profileById,
            countById: countById,
          ),
      ],
    );
  }
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.filtro, required this.countFor});

  final RutinaFiltro filtro;
  final int Function(RutinaFiltro) countFor;

  static const _chips = [
    RutinaFiltro.todos,
    RutinaFiltro.sinRutina,
    RutinaFiltro.conRutina,
    RutinaFiltro.activos,
    RutinaFiltro.inactivos,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final f in _chips)
          _Chip(
            // "TODOS · 12" — label mayúscula + punto medio + contador, mismo
            // patrón que Alumnos.
            label: '${f.label.toUpperCase()} · ${countFor(f)}',
            selected: f == filtro,
            onTap: () => ref.read(_rutinaFiltroProvider.notifier).state = f,
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
          color: selected ? palette.accent : Colors.transparent,
          border: Border.all(color: selected ? palette.accent : palette.border),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? TreinoButtonTokens.foreground(context)
                : palette.textMuted,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: 0.4,
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
    return TextField(
      controller: _controller,
      onChanged: (v) => ref.read(_queryProvider.notifier).state = v,
      style: TextStyle(color: palette.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Buscar por nombre…', // i18n
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

class _ViewModeToggle extends ConsumerWidget {
  const _ViewModeToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final mode = ref.watch(_rutinaViewModeProvider);
    Widget option(RutinaViewMode m, IconData icon, String label) {
      final selected = m == mode;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => ref.read(_rutinaViewModeProvider.notifier).state = m,
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
          option(RutinaViewMode.tabla, TreinoIcon.viewTable, 'Tabla'), // i18n
          option(RutinaViewMode.cards, TreinoIcon.viewCards, 'Cards'), // i18n
        ],
      ),
    );
  }
}

/// Fila de un alumno — tap abre el editor de rutinas para ese alumno.
///
/// Recibe todo ya resuelto por el padre (`_RutinasRosterView`) en vez de
/// mirar sus propios providers: así el padre (que necesita los mismos datos
/// para filtrar/contar) y la fila siempre coinciden — una única fuente de
/// verdad por alumno.
class _AthleteRow extends StatefulWidget {
  const _AthleteRow({
    required this.athleteId,
    required this.name,
    required this.avatarUrl,
    required this.gymName,
    required this.estado,
    required this.activeRoutinesCount,
  });

  final String athleteId;
  final String name;
  final String? avatarUrl;
  final String? gymName;
  final _LinkEstado estado;
  final int? activeRoutinesCount;

  @override
  State<_AthleteRow> createState() => _AthleteRowState();
}

class _AthleteRowState extends State<_AthleteRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final gymName = widget.gymName;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      // TreinoTappable ya aplica HitTestBehavior.opaque internamente, así que
      // el box padeado entero sigue siendo tappeable (el avatar mide 36px,
      // debajo del mínimo de 44pt) y además suma el feedback de presión.
      child: TreinoTappable(
        onTap: () => context.push('/rutinas/${widget.athleteId}'),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: palette.bgCard,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
                color: _hovered ? palette.borderHover : palette.border),
          ),
          child: Row(
            children: [
              _Avatar(
                  name: widget.name,
                  url: widget.avatarUrl,
                  athleteId: widget.athleteId),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: AppFonts.barlow,
                          color: palette.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600),
                    ),
                    if (gymName != null && gymName.isNotEmpty)
                      Text(
                        gymName,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontFamily: AppFonts.barlow,
                            color: palette.textMuted,
                            fontSize: 12),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Fixed widths so the pills form aligned columns across rows
              // regardless of label length ("Activo" vs "Inactivo", "1 rutina"
              // vs "Sin rutina"). Pills are left-aligned within their slot.
              SizedBox(
                width: 96,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _EstadoPill(estado: widget.estado),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 92,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _RoutineCountBadge(count: widget.activeRoutinesCount),
                ),
              ),
              const SizedBox(width: 8),
              Icon(TreinoIcon.chevronRight, size: 18, color: palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Grilla responsive de cards (modo Cards). A diferencia de Alumnos, la card
/// acá es deliberadamente simple (decisión del usuario): solo avatar + nombre
/// + badge de conteo de rutinas — sin gimnasio, sin pill de estado, sin
/// último entreno ni deuda.
class _RutinasCardsGrid extends StatelessWidget {
  const _RutinasCardsGrid({
    required this.athletes,
    required this.nameFor,
    required this.profileById,
    required this.countById,
  });

  final List<TrainerLink> athletes;
  final String Function(String athleteId) nameFor;
  final Map<String, UserPublicProfile?> profileById;
  final Map<String, int?> countById;

  static const double _targetCardWidth = 300;
  static const double _runSpacing = 12;

  @override
  Widget build(BuildContext context) {
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
            for (final link in athletes)
              SizedBox(
                width: cardWidth,
                child: _RutinasCard(
                  athleteId: link.athleteId,
                  name: nameFor(link.athleteId),
                  avatarUrl: profileById[link.athleteId]?.avatarUrl,
                  activeRoutinesCount: countById[link.athleteId],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _RutinasCard extends StatelessWidget {
  const _RutinasCard({
    required this.athleteId,
    required this.name,
    required this.avatarUrl,
    required this.activeRoutinesCount,
  });

  final String athleteId;
  final String name;
  final String? avatarUrl;
  final int? activeRoutinesCount;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/rutinas/$athleteId'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: palette.bgCard,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            _Avatar(name: name, url: avatarUrl, athleteId: athleteId),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppFonts.barlow,
                  color: palette.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _RoutineCountBadge(count: activeRoutinesCount),
          ],
        ),
      ),
    );
  }
}

/// Avatar de color estable por alumno (patrón de Alumnos' `_Avatar`,
/// alumnos_screen.dart:589-622) — fondo `avatarColorFor(athleteId)` + inicial
/// blanca cuando no hay foto; `NetworkImage` cuando sí.
class _Avatar extends StatelessWidget {
  const _Avatar(
      {required this.name, required this.url, required this.athleteId});

  final String name;
  final String? url;
  final String athleteId;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final hasNetworkImage = url != null && url!.isNotEmpty;
    return CircleAvatar(
      radius: 18,
      backgroundColor: hasNetworkImage ? palette.bg : avatarColorFor(athleteId),
      backgroundImage: hasNetworkImage ? NetworkImage(url!) : null,
      child: hasNetworkImage
          ? null
          : Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }
}

/// Pill de estado del vínculo — mismo look que `_EstadoBadge` de Alumnos
/// (alumnos_screen.dart:624-664): fondo tinte @0.15 alpha + punto de color +
/// label. Replicado acá (no importado) porque Alumnos usa `AlumnoEstado`
/// (con dimensión de deuda) que esta pantalla no necesita.
class _EstadoPill extends StatelessWidget {
  const _EstadoPill({required this.estado});

  final _LinkEstado estado;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = estado.color(palette);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              estado.label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge de cantidad de rutinas activas — la info más importante de la
/// redesign: distingue de un vistazo quién necesita una rutina ("Sin
/// rutina", chip muted) de quién ya tiene ("N rutinas", chip accent).
/// Mientras `count` es null (todavía cargando) muestra un placeholder sutil
/// en vez de "Sin rutina", que sería incorrecto durante la carga.
class _RoutineCountBadge extends StatelessWidget {
  const _RoutineCountBadge({required this.count});

  final int? count;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    if (count == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: palette.textMuted.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Text(
          '…', // i18n
          style: TextStyle(color: palette.textMuted, fontSize: 12),
        ),
      );
    }

    final hasRoutines = count! > 0;
    final label = hasRoutines
        ? (count == 1 ? '1 rutina' : '$count rutinas') // i18n
        : 'Sin rutina'; // i18n
    final color = hasRoutines ? palette.accent : palette.textMuted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: hasRoutines
            ? color.withValues(alpha: 0.15)
            : palette.textMuted.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
