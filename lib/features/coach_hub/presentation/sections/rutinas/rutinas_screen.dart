// NOTE: Scaffold y SafeArea los provee CoachHubScaffold (ADR-CHW-005).
// Todas las strings en español hardcodeado + // i18n.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';
import 'package:treino/core/widgets/motion/treino_state_switcher.dart';
import 'package:treino/core/widgets/motion/treino_tappable.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/chat/widgets/avatar_color.dart';
import 'package:treino/features/coach_hub/presentation/shell/section_header.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
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
          const SectionHeader(title: 'Rutinas'), // i18n
          const SizedBox(height: 6),
          Text(
            'Elegí un alumno para armarle una rutina.', // i18n
            style: GoogleFonts.barlow(color: palette.textMuted, fontSize: 14),
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
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, link) in athletes.indexed)
                      TreinoFadeSlideIn(
                        delay: AppMotion.stagger(i),
                        child: _AthleteRow(link: link),
                      ),
                  ],
                );
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
          style: GoogleFonts.barlow(color: palette.textMuted, fontSize: 14)),
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

/// Fila de un alumno — tap abre el editor de rutinas para ese alumno.
class _AthleteRow extends ConsumerStatefulWidget {
  const _AthleteRow({required this.link});

  final TrainerLink link;

  @override
  ConsumerState<_AthleteRow> createState() => _AthleteRowState();
}

class _AthleteRowState extends ConsumerState<_AthleteRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final athleteId = widget.link.athleteId;
    final profileAsync = ref.watch(userPublicProfileProvider(athleteId));
    final profile = profileAsync.valueOrNull;
    final rawName = profile?.displayName ?? '';
    final name = rawName.isEmpty ? 'Alumno' : rawName; // i18n
    final gymName = profile?.gymName;
    final estado = _estadoFor(widget.link.status);

    // Conteo de rutinas ACTIVAS — mismo filtro que la pantalla de detalle
    // (athlete_routines_screen.dart) para que el número coincida con lo que
    // el PF ve al entrar. `valueOrNull` deja el badge en un estado "cargando"
    // en vez de mostrar "Sin rutina" de forma incorrecta mientras resuelve.
    final routinesAsync = ref.watch(assignedRoutinesProvider(athleteId));
    final activeRoutinesCount = routinesAsync.valueOrNull
        ?.where((r) => r.status == RoutineStatus.active)
        .length;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: TreinoTappable(
        onTap: () => context.push('/rutinas/$athleteId'),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: palette.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: _hovered ? palette.borderHover : palette.border),
          ),
          child: Row(
            children: [
              _Avatar(
                  name: name, url: profile?.avatarUrl, athleteId: athleteId),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.barlow(
                          color: palette.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600),
                    ),
                    if (gymName != null && gymName.isNotEmpty)
                      Text(
                        gymName,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.barlow(
                            color: palette.textMuted, fontSize: 12),
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
                  child: _EstadoPill(estado: estado),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 92,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _RoutineCountBadge(count: activeRoutinesCount),
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
        borderRadius: BorderRadius.circular(20),
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
          borderRadius: BorderRadius.circular(20),
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
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
