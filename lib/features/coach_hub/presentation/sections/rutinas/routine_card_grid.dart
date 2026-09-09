import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/theme/app_palette.dart';
import '../../../../../app/theme/tokens/tokens.dart';
import '../../../../profile/application/user_public_profile_providers.dart';
import '../../../../workout/domain/routine.dart';
import '../../../../workout/domain/routine_source.dart';
import '../../../../workout/domain/routine_status.dart';
import '../../../../workout/domain/routine_visibility.dart';

/// Grilla de las rutinas del PF, en cards.
///
/// Reemplaza el listado de PERSONAS que había en esta sección. La diferencia
/// no es cosmética: aquel listado partía del alumno y sólo podía contar
/// «cuántas rutinas tiene», así que una plantilla sin asignar —que es la mitad
/// del trabajo de un PF— no aparecía en ningún lado.
///
/// El ancho de card y el `Wrap` replican los de la grilla que ya existía acá,
/// para que la sección no cambie de ritmo al cambiar de contenido.
class RoutineCardGrid extends StatelessWidget {
  const RoutineCardGrid({super.key, required this.routines});

  final List<Routine> routines;

  static const double _targetCardWidth = 300;
  static const double _runSpacing = 12;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final raw =
            ((available + _runSpacing) / (_targetCardWidth + _runSpacing))
                .floor();
        final columns = raw < 1 ? 1 : raw;
        final cardWidth =
            (available - _runSpacing * (columns - 1)) / columns;
        return Wrap(
          spacing: _runSpacing,
          runSpacing: _runSpacing,
          children: [
            for (final r in routines)
              SizedBox(
                width: cardWidth,
                child: RoutineCard(key: ValueKey(r.id), routine: r),
              ),
          ],
        );
      },
    );
  }
}

/// Una rutina del PF: nombre, sus etiquetas y el resumen de la prescripción.
class RoutineCard extends ConsumerWidget {
  const RoutineCard({super.key, required this.routine});

  final Routine routine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final archivada = routine.status == RoutineStatus.archived;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Dos editores, según qué sea la rutina. No es un detalle de routing:
      // un plan asignado se guarda por `updateAssigned` y necesita el alumno
      // en la URL; una plantilla no tiene alumno y va por `updateTemplate`.
      // Mandar una plantilla al editor de planes la haría pedir un
      // `athleteId` que no existe.
      //
      // `push` y no `go`: el editor tiene su propia flecha atrás, y con `go`
      // se reemplaza la entrada de historial y esa flecha queda sin destino.
      // Es el mismo bug que ya se arregló en Nutrición y en Rutinas.
      onTap: () => context.push(_destino(routine)),
      child: Container(
        key: Key('routine_card_${routine.id}'),
        padding: const EdgeInsets.all(AppSpacing.s14),
        decoration: BoxDecoration(
          color: palette.bgCard,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              routine.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppFonts.barlowCondensed,
                fontWeight: AppFonts.w700,
                fontSize: AppTextSize.bodyLarge,
                // Una archivada se lee apagada: sigue siendo tuya y sigue
                // estando, pero ya no es lo que estás usando.
                color: archivada ? palette.textMuted : palette.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            _Etiquetas(routine: routine),
            const SizedBox(height: AppSpacing.s8),
            Text(
              _resumen(routine),
              style: TextStyle(
                fontFamily: AppFonts.barlow,
                fontSize: AppTextSize.caption,
                color: palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A qué editor va esta rutina.
  ///
  /// Con alumno → el editor de planes, que lo necesita en la URL. Sin alumno
  /// → el de plantillas. Hoy esas dos formas viven en secciones distintas del
  /// Hub —los planes en Rutinas, las plantillas en Biblioteca—, y esta grilla
  /// es el primer lugar donde se ven juntas.
  static String _destino(Routine r) {
    final alumno = r.assignedTo;
    return alumno == null || alumno.isEmpty
        ? '/template-editor/${r.id}'
        : '/routine-editor/$alumno/${r.id}';
  }

  /// Split · nivel · semanas. Lo que distingue una rutina de otra de un
  /// vistazo, sin abrirla.
  static String _resumen(Routine r) {
    final partes = <String>[
      if ((r.split ?? '').trim().isNotEmpty) r.split!.trim(),
      // i18n: Fase W2
      if (r.numWeeks > 1) '${r.numWeeks} semanas' else '1 semana',
    ];
    return partes.join(' · ');
  }
}

/// Las etiquetas de una rutina: a quién está asignada, si es plantilla, si es
/// pública, si está archivada.
///
/// Van en un `Wrap` porque son de largo variable —el nombre de un alumno puede
/// ser largo— y en una `Row` la card desbordaría en la columna más angosta.
class _Etiquetas extends ConsumerWidget {
  const _Etiquetas({required this.routine});

  final Routine routine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final etiquetas = <Widget>[];

    final asignadoA = routine.assignedTo;
    if (asignadoA != null && asignadoA.isNotEmpty) {
      // El nombre se resuelve por su cuenta: la card no lo recibe del padre
      // para que la grilla no tenga que juntar todos los perfiles antes de
      // dibujar nada. Mientras resuelve dice «Asignada», no un nombre falso.
      final pub = ref.watch(userPublicProfileProvider(asignadoA)).valueOrNull;
      final nombre = pub?.displayName?.trim();
      etiquetas.add(_Etiqueta(
        texto: nombre == null || nombre.isEmpty
            ? 'Asignada' // i18n: Fase W2
            : 'Asignada a $nombre', // i18n: Fase W2
        color: palette.accentText,
      ));
    } else if (routine.source == RoutineSource.trainerTemplate) {
      etiquetas.add(_Etiqueta(
        texto: 'Plantilla', // i18n: Fase W2
        color: palette.textMuted,
      ));
    }

    if (routine.visibility == RoutineVisibility.public) {
      etiquetas.add(_Etiqueta(
        texto: 'Pública', // i18n: Fase W2
        color: palette.accentText,
      ));
    }

    if (routine.status == RoutineStatus.archived) {
      etiquetas.add(_Etiqueta(
        texto: 'Archivada', // i18n: Fase W2
        color: palette.textMuted,
      ));
    }

    if (etiquetas.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: AppSpacing.hairline,
      runSpacing: AppSpacing.hairline,
      children: etiquetas,
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta({required this.texto, required this.color});

  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.hairline,
      ),
      decoration: BoxDecoration(
        color: palette.surfaceSubtle,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontFamily: AppFonts.barlow,
          fontWeight: AppFonts.w600,
          fontSize: AppTextSize.micro,
          color: color,
        ),
      ),
    );
  }
}
