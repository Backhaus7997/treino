// NOTE: Scaffold y SafeArea los provee CoachHubScaffold (ADR-CHW-005).
// Todas las strings en español hardcodeado + // i18n.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';
import 'package:treino/core/widgets/motion/treino_state_switcher.dart';
import 'package:treino/core/widgets/motion/treino_tappable.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';
import 'package:treino/features/coach_hub/presentation/widgets/skeleton/coach_hub_skeleton.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_status.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';

import 'routine_card_grid.dart';

/// Sección «Rutinas» del Coach Hub web.
///
/// Lista LAS RUTINAS del PF, no sus alumnos.
///
/// Antes esta pantalla era un roster: listaba personas y contaba cuántas
/// rutinas activas tenía cada una. Eso dejaba afuera la mitad del trabajo de
/// un PF —una plantilla sin asignar no le pertenece a ningún alumno, así que
/// no aparecía en ninguna fila— y obligaba a entrar alumno por alumno para
/// encontrar un plan cuyo nombre ya se sabía.
///
/// El eje es el AUTOR: `routinesAuthoredByProvider` trae todo lo que el PF
/// creó, plantillas y planes juntos, y cada card dice qué es con sus
/// etiquetas. Es la primera pantalla del Hub donde esas dos formas conviven —
/// hasta ahora los planes vivían acá y las plantillas en Biblioteca.
class RutinasScreen extends ConsumerWidget {
  const RutinasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final uid = ref.watch(currentUidProvider) ?? '';
    final rutinasAsync = ref.watch(routinesAuthoredByProvider(uid));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TreinoFadeSlideIn(
            delay: AppMotion.stagger(0),
            child: const CoachHubSectionHero(
              title: 'Rutinas', // i18n
              subtitle: 'Todo lo que creaste: planes y plantillas.', // i18n
            ),
          ),
          const SizedBox(height: 20),
          TreinoStateSwitcher(
            childKey: ValueKey(rutinasAsync.when(
              loading: () => 'loading',
              error: (_, __) => 'error',
              data: (rs) => rs.isEmpty ? 'empty' : 'data',
            )),
            child: rutinasAsync.when(
              loading: () => const CoachHubSkeleton(
                filas: 4,
                padding: EdgeInsets.symmetric(vertical: 24, horizontal: 12),
              ),
              error: (_, __) =>
                  _muted(palette, 'No pudimos cargar tus rutinas.'), // i18n
              data: (rutinas) => rutinas.isEmpty
                  ? _muted(palette,
                      'Todavía no creaste ninguna rutina.') // i18n
                  : _RutinasView(rutinas: rutinas),
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
              fontSize: AppTextSize.body)),
    );

/// Los filtros de la sección, sobre el ESTADO de la rutina.
///
/// Antes eran cinco: `todas · asignadas · plantillas · publicas · archivadas`.
/// Los dos del medio se fueron, y no por simplificar: **«asignadas» y
/// «plantillas» dejaron de ser filtros para ser los dos BLOQUES** en que la
/// pantalla se divide (ver [_RutinasView]). Un chip que muestra exactamente el
/// contenido de un bloque que ya está en pantalla no filtra nada, sólo esconde
/// el otro.
///
/// Lo que queda es un eje de estado, que sí es transversal a los dos bloques:
/// qué está en uso, qué está publicado, qué se guardó.
enum RutinaFiltro { vigentes, publicas, archivadas }

extension RutinaFiltroX on RutinaFiltro {
  String get label => switch (this) {
        RutinaFiltro.vigentes => 'Vigentes', // i18n
        RutinaFiltro.publicas => 'Públicas', // i18n
        RutinaFiltro.archivadas => 'Archivadas', // i18n
      };
}

/// Si [r] entra en [f].
///
/// «Vigentes» excluye las ARCHIVADAS, igual que el chip equivalente del roster
/// de Alumnos excluye a los inactivos: lo archivado sigue existiendo y tiene su
/// propio chip, pero no compite por la atención con lo que está en uso. Sin
/// esa exclusión, un PF con años de planes terminados vería su biblioteca
/// enterrada bajo lo que ya no usa.
bool matchesFiltro(Routine r, RutinaFiltro f) {
  final archivada = r.status == RoutineStatus.archived;

  return switch (f) {
    RutinaFiltro.vigentes => !archivada,
    RutinaFiltro.publicas =>
      r.visibility == RoutineVisibility.public && !archivada,
    RutinaFiltro.archivadas => archivada,
  };
}

final _filtroProvider =
    StateProvider.autoDispose<RutinaFiltro>((_) => RutinaFiltro.vigentes);
final _queryProvider = StateProvider.autoDispose<String>((_) => '');

class _RutinasView extends ConsumerWidget {
  const _RutinasView({required this.rutinas});

  final List<Routine> rutinas;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final filtro = ref.watch(_filtroProvider);
    final query = ref.watch(_queryProvider).trim().toLowerCase();

    int countFor(RutinaFiltro f) =>
        rutinas.where((r) => matchesFiltro(r, f)).length;

    final visibles = rutinas.where((r) {
      if (!matchesFiltro(r, filtro)) return false;
      if (query.isEmpty) return true;
      // Se busca por NOMBRE y por split: son las dos cosas que el PF recuerda
      // de una rutina cuando la está buscando.
      final enNombre = r.name.toLowerCase().contains(query);
      final enSplit = (r.split ?? '').toLowerCase().contains(query);
      return enNombre || enSplit;
    }).toList();

    // El corte que ordena la sección. Una plantilla y la copia que entrena un
    // alumno son cosas distintas —una se reutiliza, la otra tiene dueño— y
    // mezcladas se pierden: con 20 alumnos y 5 rutinas cada uno, las 5
    // plantillas del PF son el 5% de una grilla de 100 tarjetas.
    //
    // Se parte por `assignedTo` y NADA MÁS, a propósito. Los chips que esto
    // reemplaza usaban dos predicados distintos —«Plantillas» miraba `source`,
    // «Asignadas» miraba `assignedTo`— y dos predicados pueden discrepar: una
    // rutina podía caer en los dos o en ninguno, y en el segundo caso
    // desaparecía de la pantalla sin que nada fallara. Con un solo predicado
    // booleano cada rutina cae en exactamente un bloque, siempre. (Hoy los dos
    // coinciden: las reglas exigen `assignedTo == null` en una plantilla y
    // `assignTemplateToAthlete` mueve `source` y `assignedTo` juntos. Pero no
    // hace falta confiar en eso para que la suma cierre.)
    final plantillas = visibles.where((r) => (r.assignedTo ?? '').isEmpty);
    final asignadas = visibles.where((r) => (r.assignedTo ?? '').isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FilterBar(filtro: filtro, countFor: countFor),
        const SizedBox(height: AppSpacing.s12),
        const _SearchField(),
        const SizedBox(height: AppSpacing.s18),
        if (visibles.isEmpty)
          _muted(palette, 'No encontramos rutinas con esos filtros.') // i18n
        else ...[
          if (plantillas.isNotEmpty) ...[
            _BloqueHeader(
              titulo: 'Mis plantillas', // i18n
              cuenta: plantillas.length,
            ),
            const SizedBox(height: AppSpacing.s12),
            RoutineCardGrid(routines: plantillas.toList()),
          ],
          if (plantillas.isNotEmpty && asignadas.isNotEmpty)
            const SizedBox(height: AppSpacing.s20),
          if (asignadas.isNotEmpty) ...[
            _BloqueHeader(
              titulo: 'Lo que entrena cada alumno', // i18n
              cuenta: asignadas.length,
            ),
            for (final grupo in _agruparPorAlumno(asignadas)) ...[
              const SizedBox(height: AppSpacing.s14),
              _GrupoDeAlumno(athleteId: grupo.key, rutinas: grupo.value),
            ],
          ],
        ],
      ],
    );
  }
}

/// Parte [rutinas] por alumno, **conservando el orden de llegada**.
///
/// El orden importa y es gratis: `listAuthoredBy` ya devuelve la lista ordenada
/// por `createdAt` descendente, así que respetarlo deja arriba al alumno cuya
/// rutina se tocó más recientemente — que es por dónde el PF vuelve a entrar.
///
/// **Alfabético sería mejor y no se puede pagar acá.** Ordenar por nombre
/// obliga a resolver los perfiles de los N alumnos ANTES de dibujar el primer
/// grupo, y esta pantalla evita eso a propósito desde #1065: cada card —y ahora
/// cada encabezado— resuelve su nombre por su cuenta y muestra un placeholder
/// mientras tanto. Con nombres en el padre, un perfil lento deja la sección
/// entera en blanco, y uno que resuelve tarde REORDENA los grupos bajo el
/// cursor. Un `LinkedHashMap` no necesita ningún nombre.
List<MapEntry<String, List<Routine>>> _agruparPorAlumno(
  Iterable<Routine> rutinas,
) {
  final porAlumno = <String, List<Routine>>{};
  for (final r in rutinas) {
    porAlumno.putIfAbsent(r.assignedTo!, () => <Routine>[]).add(r);
  }
  return porAlumno.entries.toList();
}

/// El encabezado de uno de los dos bloques de la sección.
class _BloqueHeader extends StatelessWidget {
  const _BloqueHeader({required this.titulo, required this.cuenta});

  final String titulo;
  final int cuenta;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      children: [
        Text(
          titulo.toUpperCase(),
          style: TextStyle(
            fontFamily: AppFonts.barlowCondensed,
            fontWeight: AppFonts.w700,
            fontSize: AppTextSize.body,
            letterSpacing: 0.5,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(width: AppSpacing.s8),
        Text(
          '$cuenta',
          style: TextStyle(
            fontFamily: AppFonts.barlow,
            fontWeight: AppFonts.w700,
            fontSize: AppTextSize.caption,
            color: palette.textMuted,
          ),
        ),
      ],
    );
  }
}

/// Las rutinas de UN alumno, bajo su nombre.
///
/// Resuelve el nombre por su cuenta, igual que las etiquetas de cada card. Es
/// lo que permite que [_agruparPorAlumno] no necesite perfiles: mientras el
/// suyo carga —o si la cuenta se borró— dice «Alumno», nunca un uid ni un
/// nombre inventado.
class _GrupoDeAlumno extends ConsumerWidget {
  const _GrupoDeAlumno({required this.athleteId, required this.rutinas});

  final String athleteId;
  final List<Routine> rutinas;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final perfil = ref.watch(userPublicProfileProvider(athleteId));
    final limpio = perfil.valueOrNull?.displayName?.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          limpio == null || limpio.isEmpty
              ? 'Alumno' // i18n
              : limpio,
          style: TextStyle(
            fontFamily: AppFonts.barlow,
            fontWeight: AppFonts.w600,
            fontSize: AppTextSize.bodyDense,
            color: palette.accentText,
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        RoutineCardGrid(routines: rutinas),
      ],
    );
  }
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.filtro, required this.countFor});

  final RutinaFiltro filtro;
  final int Function(RutinaFiltro) countFor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: AppSpacing.s8,
      runSpacing: AppSpacing.s8,
      children: [
        for (final f in RutinaFiltro.values)
          _Chip(
            label: f.label,
            count: countFor(f),
            selected: f == filtro,
            onTap: () => ref.read(_filtroProvider.notifier).state = f,
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return TreinoTappable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s14,
          vertical: AppSpacing.s8,
        ),
        decoration: BoxDecoration(
          color: selected
              ? palette.accent.withValues(alpha: 0.16)
              : Colors.transparent,
          border: Border.all(
            color: selected ? palette.accent : palette.border,
          ),
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: AppFonts.barlow,
                fontWeight: AppFonts.w600,
                fontSize: AppTextSize.bodyDense,
                // `accentText` y no `accent`: esto es TEXTO, y el acento como
                // tinta sobre claro no llega a 4,5:1.
                color: selected ? palette.accentText : palette.textPrimary,
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            Text(
              '$count',
              style: TextStyle(
                fontFamily: AppFonts.barlow,
                fontWeight: AppFonts.w700,
                fontSize: AppTextSize.caption,
                color: palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends ConsumerStatefulWidget {
  const _SearchField();

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: ref.read(_queryProvider));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return TextField(
      key: const Key('rutinas_search_field'),
      controller: _ctrl,
      onChanged: (v) => ref.read(_queryProvider.notifier).state = v,
      style: TextStyle(
        fontFamily: AppFonts.barlow,
        color: palette.textPrimary,
        fontSize: AppTextSize.body,
      ),
      decoration: InputDecoration(
        hintText: 'Buscar por nombre o split...', // i18n
        prefixIcon: Icon(Icons.search, color: palette.textMuted, size: 18),
      ),
    );
  }
}
