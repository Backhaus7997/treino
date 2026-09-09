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
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
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

/// Los filtros de la sección, sobre la RUTINA.
///
/// Los de antes hablaban de personas —«Sin rutina», «Con rutina», «Activos»,
/// «Inactivos»— y ninguno sobrevive al cambio de eje: no se le puede preguntar
/// a una plantilla si su alumno está activo.
enum RutinaFiltro { todas, asignadas, plantillas, publicas, archivadas }

extension RutinaFiltroX on RutinaFiltro {
  String get label => switch (this) {
        RutinaFiltro.todas => 'Todas', // i18n
        RutinaFiltro.asignadas => 'Asignadas', // i18n
        RutinaFiltro.plantillas => 'Plantillas', // i18n
        RutinaFiltro.publicas => 'Públicas', // i18n
        RutinaFiltro.archivadas => 'Archivadas', // i18n
      };
}

/// Si [r] entra en [f].
///
/// «Todas» excluye las ARCHIVADAS, igual que el chip «Todos» del roster de
/// Alumnos excluye a los inactivos: lo archivado sigue existiendo y tiene su
/// propio chip, pero no compite por la atención con lo que está en uso. Sin
/// esa exclusión, un PF con años de planes terminados vería su biblioteca
/// enterrada bajo lo que ya no usa.
bool matchesFiltro(Routine r, RutinaFiltro f) {
  final archivada = r.status == RoutineStatus.archived;
  final esPlantilla = r.source == RoutineSource.trainerTemplate;
  final asignada = (r.assignedTo ?? '').isNotEmpty;

  return switch (f) {
    RutinaFiltro.todas => !archivada,
    RutinaFiltro.asignadas => asignada && !archivada,
    RutinaFiltro.plantillas => esPlantilla && !archivada,
    RutinaFiltro.publicas =>
      r.visibility == RoutineVisibility.public && !archivada,
    RutinaFiltro.archivadas => archivada,
  };
}

final _filtroProvider =
    StateProvider.autoDispose<RutinaFiltro>((_) => RutinaFiltro.todas);
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FilterBar(filtro: filtro, countFor: countFor),
        const SizedBox(height: AppSpacing.s12),
        const _SearchField(),
        const SizedBox(height: AppSpacing.s14),
        if (visibles.isEmpty)
          _muted(palette, 'No encontramos rutinas con esos filtros.') // i18n
        else
          RoutineCardGrid(routines: visibles),
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
