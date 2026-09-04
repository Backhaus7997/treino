// NOTE: Scaffold y SafeArea los provee CoachHubScaffold (ADR-CHW-005).
// Todas las strings en español hardcodeado + // i18n.
// No se usa AppL10n (constraint C-6).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/exercise_asset_image.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../workout/application/custom_exercise_providers.dart';
import '../../../workout/application/exercise_filter.dart';
import '../../../workout/application/exercise_providers.dart';
import '../../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../../../workout/domain/custom_exercise.dart';
import '../../../workout/domain/equipment_type.dart';
import '../../../workout/domain/exercise.dart';
import '../../../workout/domain/muscle_group.dart';
import '../sections/biblioteca/widgets/exercise_detail_dialog.dart'
    show showExerciseDetailDialog;
import 'create_custom_exercise_dialog.dart';
import 'package:treino/features/coach_hub/presentation/widgets/skeleton/coach_hub_skeleton.dart';

/// Web equivalent of [showExercisePicker] (mobile's `exercise_picker_sheet.dart`
/// bottom sheet) — a multi-select exercise picker for the Coach Hub routine
/// editor. Same contract: returns the confirmed [List<Exercise>], or `null` if
/// dismissed without confirming.
///
/// ADR-CHW-005: no bottom sheet on web — muscle/equipment filters render as
/// INLINE chips (mirrors [BibliotecaFilterChips]' visual language) with LOCAL
/// widget state, not the global `bibliotecaMuscleFilterProvider` /
/// `bibliotecaEquipmentFilterProvider` — those are scoped to the Biblioteca
/// section's own lifecycle and would leak stale filter state into an
/// independently-opened dialog.
///
/// Reuses the same low-level building blocks as the mobile picker
/// (`exerciseMatchesFilters`, `customToExercise`, `exercisesProvider`,
/// `customExercisesForTrainerStreamProvider`) so search/filter BEHAVIOR is
/// identical — only the presentation container (dialog vs. sheet) differs.
///
/// Trainers can create a new custom exercise inline via "+ Crear ejercicio
/// nuevo" ([showCreateCustomExerciseDialog]): the created exercise is
/// auto-selected and shows up under "Tus ejercicios" on its own (the custom
/// stream is live). Web captures the MVP fields (name/muscle/equipment);
/// mobile's richer description + validated-video editor stays app-only.
Future<List<Exercise>?> showExercisePickerDialog(
  BuildContext context, {
  Set<String> alreadySelectedIds = const {},
}) {
  return showDialog<List<Exercise>>(
    context: context,
    builder: (_) =>
        _ExercisePickerDialog(alreadySelectedIds: alreadySelectedIds),
  );
}

class _ExercisePickerDialog extends ConsumerStatefulWidget {
  const _ExercisePickerDialog({
    required this.alreadySelectedIds,
    this.onAgregar,
    this.onAgregarEnSuperserie,
  });

  final Set<String> alreadySelectedIds;

  /// Qué hacer al confirmar. Cuando es **null** el contenido se hospeda en un
  /// `Dialog` y confirmar hace `Navigator.pop(result)` — el flujo de siempre.
  /// Cuando está, el contenido se dibuja pelado para que lo hospede un panel:
  /// confirmar llama a esto y **no cierra nada**, así el PF agrega varios
  /// ejercicios seguidos viendo cómo se arma el día (#860).
  final void Function(List<Exercise>)? onAgregar;

  /// Agrega los elegidos ya enlazados como superserie. Sólo en modo panel.
  final void Function(List<Exercise>)? onAgregarEnSuperserie;

  @override
  ConsumerState<_ExercisePickerDialog> createState() =>
      _ExercisePickerDialogState();
}

class _ExercisePickerDialogState extends ConsumerState<_ExercisePickerDialog> {
  String _query = '';
  Set<MuscleGroup> _muscleFilters = {};
  Set<EquipmentType> _equipmentFilters = {};
  late Set<String> _selected;
  final TextEditingController _searchController = TextEditingController();

  /// Los 23 chips de filtro arrancan COLAPSADOS.
  ///
  /// Desplegados son 4 filas y, junto con el header, el buscador y la fila de
  /// crear, dejaban 3 ejercicios visibles sobre un catálogo de cientos (#860).
  /// El buscador cubre el caso normal —se busca por nombre— y los filtros son
  /// para acotar cuando eso no alcanza: cerrados por default, el alto se lo
  /// queda la lista, que es lo único que importa acá.
  bool _filtrosAbiertos = false;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.alreadySelectedIds};
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int get _cantidadDeFiltros => _muscleFilters.length + _equipmentFilters.length;

  bool _matches(Exercise e) => exerciseMatchesFilters(
        e,
        query: _query,
        muscles: _muscleFilters,
        equipment: _equipmentFilters,
      );

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _confirm(
    List<Exercise> defaults,
    List<CustomExercise> customs, {
    bool enSuperserie = false,
  }) {
    final result = <Exercise>[];
    for (final id in _selected) {
      final fromDefaults = _exerciseWithId(defaults, id);
      if (fromDefaults != null) {
        result.add(fromDefaults);
        continue;
      }
      final fromCustom = _customWithId(customs, id);
      if (fromCustom != null) {
        result.add(customToExercise(fromCustom));
      }
    }
    final alAgregar = enSuperserie
        ? widget.onAgregarEnSuperserie
        : widget.onAgregar;
    if (alAgregar == null) {
      Navigator.of(context).pop(result);
      return;
    }
    // El panel NO se cierra. Y se limpia la selección: dejarla marcada haría
    // que el próximo "Agregar" reenvíe los mismos ejercicios.
    alAgregar(result);
    setState(() => _selected.clear());
  }

  Future<void> _openCreateNew() async {
    final created = await showCreateCustomExerciseDialog(context);
    if (created == null || !mounted) return;
    // The custom stream (customExercisesForTrainerStreamProvider) is live, so
    // the new exercise shows up under "Tus ejercicios" on its own — pre-select
    // it so the trainer just hits "Agregar".
    setState(() => _selected.add(created.id));
  }

  Future<void> _editCustom(CustomExercise exercise) async {
    // The custom stream is live and selection is keyed by id, so the edited row
    // refreshes in place — nothing to reconcile here.
    await showEditCustomExerciseDialog(context, exercise);
  }

  Future<void> _deleteCustom(CustomExercise exercise) async {
    final uid = ref.read(currentUidProvider) ?? '';
    if (uid.isEmpty) return;
    final palette = AppPalette.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.bgCard,
        title: Text(
          '¿Eliminar ejercicio?', // i18n
          style: GoogleFonts.barlowCondensed(
            color: palette.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        content: Text(
          // Slots denormalize the name/group at assign time, so existing
          // routines keep working after the library entry is gone.
          'Se borra "${exercise.name}" de tu biblioteca. Las rutinas que ya lo '
          'usan no se tocan.', // i18n
          style: GoogleFonts.barlow(color: palette.textMuted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancelar', // i18n
              style: GoogleFonts.barlow(color: palette.textMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Eliminar', // i18n
              style: GoogleFonts.barlow(
                color: palette.danger,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(customExerciseRepositoryProvider)
          .delete(trainerId: uid, id: exercise.id);
      if (mounted) setState(() => _selected.remove(exercise.id));
      messenger.showSnackBar(
        const SnackBar(content: Text('Ejercicio eliminado.')), // i18n
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No pudimos eliminar el ejercicio.'), // i18n
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final uid = ref.watch(currentUidProvider) ?? '';
    final defaultsAsync = ref.watch(exercisesProvider);
    final customsAsync = uid.isEmpty
        ? const AsyncValue<List<CustomExercise>>.data(<CustomExercise>[])
        : ref.watch(customExercisesForTrainerStreamProvider(uid));

    // 10 muscle groups + 13 equipment types wrap into several chip rows at
    // this dialog's width — a fixed height doesn't leave the exercise list
    // enough room. Size against the viewport (capped) so the Expanded list
    // always gets adequate space regardless of how many rows the chips wrap
    // into.
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final dialogHeight = (viewportHeight * 0.85).clamp(520.0, 780.0);

    final contenido = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Elegir ejercicios', // i18n
                  style: GoogleFonts.barlowCondensed(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Cerrar', // i18n
                icon: Icon(TreinoIcon.close, color: palette.textMuted),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        // ── Search ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: TextField(
            controller: _searchController,
            style: GoogleFonts.barlow(
              color: palette.textPrimary,
              fontSize: 14,
            ),
            decoration: InputDecoration(
              prefixIcon: Icon(TreinoIcon.search, color: palette.textMuted),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: Icon(
                        TreinoIcon.close,
                        color: palette.textMuted,
                        size: 18,
                      ),
                      tooltip: 'Borrar', // i18n
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
              hintText: 'Buscar ejercicio…', // i18n
              hintStyle: GoogleFonts.barlow(
                color: palette.textMuted,
                fontSize: 14,
              ),
              filled: true,
              fillColor: palette.bg,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: palette.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: palette.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: palette.accent),
              ),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        // ── Inline filter chips (ADR-CHW-005 — no bottom sheet) ────────
        //
        // Colapsados por default. El contador dice cuántos hay puestos, para
        // que cerrarlos no esconda un filtro activo sin avisar — que sería
        // peor que el problema de alto que esto resuelve.
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 20, 0),
            child: TextButton.icon(
              key: const Key('picker_filtros_toggle'),
              onPressed: () =>
                  setState(() => _filtrosAbiertos = !_filtrosAbiertos),
              icon: Icon(
                _filtrosAbiertos
                    ? TreinoIcon.chevronUp
                    : TreinoIcon.chevronDown,
                size: 16,
                color: palette.textMuted,
              ),
              label: Text(
                _cantidadDeFiltros == 0
                    ? 'Filtros' // i18n
                    : 'Filtros ($_cantidadDeFiltros)', // i18n
                style: GoogleFonts.barlowCondensed(
                  color: _cantidadDeFiltros == 0
                      ? palette.textMuted
                      : palette.accentText,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
        if (_filtrosAbiertos)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: _InlineFilters(
              palette: palette,
              muscleFilters: _muscleFilters,
              equipmentFilters: _equipmentFilters,
              onMuscleChanged: (v) => setState(() => _muscleFilters = v),
              onEquipmentChanged: (v) =>
                  setState(() => _equipmentFilters = v),
            ),
          ),
        const Divider(height: 1),
        // ── List ─────────────────────────────────────────────────────
        Expanded(
          child: _buildList(
            palette: palette,
            defaults: defaultsAsync,
            customs: customsAsync,
          ),
        ),
        // ── Crear ejercicio nuevo ────────────────────────────────────
        //
        // Al PIE y no arriba de la lista (#860). Arriba competía por el alto
        // con lo único que importa acá: la lista. Al pie es alto fijo — no se
        // scrollea, no se lo come el scroll, y sigue estando siempre visible.
        const Divider(height: 1),
        _CreateNewExerciseButton(palette: palette, onTap: _openCreateNew),
        // ── Footer ───────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: palette.border)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // "Cancelar" SÓLO en modo diálogo. En el panel no hay ruta que
              // cerrar: `Navigator.pop()` saldría del editor entero, que es
              // exactamente lo contrario de lo que el botón promete. El panel
              // se cierra con su propia X.
              if (widget.onAgregar == null) ...[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Cancelar', // i18n
                    style: GoogleFonts.barlow(color: palette.textMuted),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              // "Agregar en superserie" SÓLO con 2 o más elegidos: una
              // superserie de uno no existe, y un botón deshabilitado que
              // nunca se explica es peor que uno que aparece cuando aplica.
              //
              // Y va acá, al lado de "Agregar", porque la decisión se toma
              // DONDE se hace la selección. Estaba en la fila del día, a otra
              // parte de la pantalla, obligando a elegir los ejercicios sin
              // haber decidido todavía si iban agrupados.
              if (widget.onAgregarEnSuperserie != null && _selected.length >= 2)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.s8),
                  child: TextButton.icon(
                    key: const Key('picker_agregar_superserie'),
                    onPressed: () => _confirm(
                      defaultsAsync.valueOrNull ?? const [],
                      customsAsync.valueOrNull ?? const [],
                      enSuperserie: true,
                    ),
                    icon: Icon(
                      TreinoIcon.streak,
                      size: 15,
                      color: palette.highlight,
                    ),
                    label: Text(
                      'En superserie', // i18n
                      style: GoogleFonts.barlowCondensed(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ElevatedButton(
                onPressed: _selected.isEmpty
                    ? null
                    : () => _confirm(
                          defaultsAsync.valueOrNull ?? const [],
                          customsAsync.valueOrNull ?? const [],
                        ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: TreinoButtonTokens.foreground(context),
                  disabledBackgroundColor: palette.accent.withValues(
                    alpha: 0.3,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                ),
                child: Text(
                  _selected.isEmpty
                      ? 'Agregar' // i18n
                      : 'Agregar (${_selected.length})', // i18n
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    // DOS hospedajes para UN contenido.
    //
    // El panel no puede devolver un resultado: se queda abierto y va
    // empujando ejercicios al día, que es el punto del #860 — el modal tapa
    // la plantilla en cada iteración del loop "miro qué puse → elijo el que
    // sigue → miro cómo quedó". Por eso el flujo de control se da vuelta:
    // de `await` a callback.
    //
    // Abajo de 1280 sigue el modal. No es un número nuevo: es
    // `Viewport.desktop` de `responsive.dart` (ADR-CHW-004), y en `compact`
    // el sidebar ya está forzado a colapsar — meterle un panel de 400 px
    // sería el mismo error que ese ADR decidió evitar.
    if (widget.onAgregar != null) return contenido;

    return Dialog(
      backgroundColor: palette.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.lg)),
      ),
      child: SizedBox(width: 560, height: dialogHeight, child: contenido),
    );
  }

  Widget _buildList({
    required AppPalette palette,
    required AsyncValue<List<Exercise>> defaults,
    required AsyncValue<List<CustomExercise>> customs,
  }) {
    if (defaults.isLoading || customs.isLoading) {
      return const CoachHubSkeleton(filas: 6);
    }
    if (defaults.hasError) {
      return Center(
        child: Text(
          'No pudimos cargar ejercicios.', // i18n
          style: GoogleFonts.barlow(color: palette.textMuted, fontSize: 14),
        ),
      );
    }
    final defaultList = defaults.value ?? const <Exercise>[];
    final customList = customs.value ?? const <CustomExercise>[];

    final filteredCustoms =
        customList.where((c) => _matches(customToExercise(c))).toList();
    final filteredDefaults = defaultList.where(_matches).toList();

    if (filteredCustoms.isEmpty && filteredDefaults.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'No encontramos ejercicios con esos filtros.', // i18n
            textAlign: TextAlign.center,
            style: GoogleFonts.barlow(color: palette.textMuted, fontSize: 14),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        if (filteredCustoms.isNotEmpty) ...[
          _SectionHeader('Tus ejercicios', palette: palette), // i18n
          for (final c in filteredCustoms)
            _ExerciseRow(
              id: c.id,
              name: c.name,
              subtitle: c.muscleGroup.isEmpty
                  ? null
                  : muscleGroupLabel(c.muscleGroup),
              badge: 'MÍO', // i18n
              isCustom: true,
              muscleGroup: c.muscleGroup,
              thumbnailUrl: null,
              ownerId: ref.watch(currentUidProvider),
              selected: _selected.contains(c.id),
              palette: palette,
              onTap: () => _toggle(c.id),
              onEdit: () => _editCustom(c),
              onDelete: () => _deleteCustom(c),
            ),
        ],
        if (filteredDefaults.isNotEmpty) ...[
          _SectionHeader('Catálogo', palette: palette), // i18n
          for (final e in filteredDefaults)
            _ExerciseRow(
              id: e.id,
              name: e.name,
              subtitle: muscleGroupLabel(e.muscleGroup),
              badge: null,
              isCustom: false,
              muscleGroup: e.muscleGroup,
              thumbnailUrl: e.thumbnailUrl,
              ownerId: null,
              selected: _selected.contains(e.id),
              palette: palette,
              onTap: () => _toggle(e.id),
            ),
        ],
      ],
    );
  }
}

// ── Inline filters (ADR-CHW-005) ──────────────────────────────────────────────

class _InlineFilters extends StatelessWidget {
  const _InlineFilters({
    required this.palette,
    required this.muscleFilters,
    required this.equipmentFilters,
    required this.onMuscleChanged,
    required this.onEquipmentChanged,
  });

  final AppPalette palette;
  final Set<MuscleGroup> muscleFilters;
  final Set<EquipmentType> equipmentFilters;
  final ValueChanged<Set<MuscleGroup>> onMuscleChanged;
  final ValueChanged<Set<EquipmentType>> onEquipmentChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _Chip(
              label: 'TODOS', // i18n
              active: muscleFilters.isEmpty,
              palette: palette,
              onTap: () => onMuscleChanged(const {}),
            ),
            for (final muscle in MuscleGroup.displayOrder)
              _Chip(
                label: muscle.label.toUpperCase(), // i18n
                active: muscleFilters.contains(muscle),
                palette: palette,
                onTap: () {
                  final next = Set<MuscleGroup>.from(muscleFilters);
                  if (!next.remove(muscle)) next.add(muscle);
                  onMuscleChanged(next);
                },
              ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _Chip(
              label: 'TODOS', // i18n
              active: equipmentFilters.isEmpty,
              palette: palette,
              onTap: () => onEquipmentChanged(const {}),
            ),
            for (final equip in EquipmentType.values)
              _Chip(
                label: equip.label.toUpperCase(), // i18n
                active: equipmentFilters.contains(equip),
                palette: palette,
                onTap: () {
                  final next = Set<EquipmentType>.from(equipmentFilters);
                  if (!next.remove(equip)) next.add(equip);
                  onEquipmentChanged(next);
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.active,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool active;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? palette.accent : palette.border,
            width: active ? 1.5 : 1,
          ),
          color: active ? palette.accent.withValues(alpha: 0.12) : palette.bg,
        ),
        child: Text(
          label,
          style: GoogleFonts.barlowCondensed(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: active ? palette.accent : palette.textMuted,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}

// ── Exercise row ───────────────────────────────────────────────────────────

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.badge,
    required this.isCustom,
    required this.muscleGroup,
    required this.thumbnailUrl,
    required this.ownerId,
    required this.selected,
    required this.palette,
    required this.onTap,
    this.onEdit,
    this.onDelete,
  });

  final String id;
  final String name;
  final String? subtitle;
  final String? badge;
  final bool isCustom;

  /// Clave canónica del grupo muscular: es el último escalón de la cascada de
  /// [ExerciseAssetImage] y el que carga el catálogo entero (los PNG con
  /// nombre de ejercicio existen para un puñado).
  final String muscleGroup;

  /// Foto real del ejercicio (frame de su propio video). null en customs y en
  /// docs anteriores al backfill: ahí manda la cascada de assets.
  final String? thumbnailUrl;
  final String? ownerId;
  final bool selected;
  final AppPalette palette;
  final VoidCallback onTap;

  /// Present only for the trainer's own custom exercises → renders edit/delete.
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  Icon _iconoDeFallback(AppPalette palette) => Icon(
        TreinoIcon.dumbbell,
        size: 26,
        color: palette.textMuted,
      );

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        decoration: BoxDecoration(
          color: selected
              ? palette.accent.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(
              color: selected ? palette.accent : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 2,
          ),
          // La foto, no un ícono repetido 800 veces. Sin esto el catálogo
          // precargado se lee como una lista de nombres y el PF tiene que
          // saberse de memoria a qué se parece cada variante.
          //
          // 56 px es el alto máximo que `ListTile` le da al leading (maxHeight
          // fija del SDK, list_tile.dart): más grande obliga al truco del
          // `OverflowBox` que usa el sheet del teléfono, y acá el panel es una
          // lista densa donde el alto de fila es justo lo que el #860 vino a
          // cuidar.
          leading: SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ClipOval(
                  child: Container(
                    width: 56,
                    height: 56,
                    color: palette.bgCard,
                    alignment: Alignment.center,
                    // Los customs no tienen foto ni entran en la cascada:
                    // sus ids no son los del catálogo.
                    child: isCustom
                        ? _iconoDeFallback(palette)
                        : ExerciseAssetImage(
                            exerciseId: id,
                            muscleGroup: muscleGroup,
                            thumbnailUrl: thumbnailUrl,
                            width: 56,
                            height: 56,
                            fallback: _iconoDeFallback(palette),
                          ),
                  ),
                ),
                // El tilde pasa a badge encima de la foto: el fondo acentuado
                // y el borde izquierdo ya dicen "elegido", pero en una lista
                // larga el ojo busca la marca en el mismo lugar de siempre.
                if (selected)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: palette.accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: palette.bgCard, width: 2),
                      ),
                      child: Icon(
                        TreinoIcon.check,
                        size: 11,
                        color: TreinoButtonTokens.foreground(context),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          title: Text(
            name,
            style: GoogleFonts.barlow(
              color: palette.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: subtitle != null && subtitle!.isNotEmpty
              ? Text(
                  subtitle!,
                  style: GoogleFonts.barlow(
                    color: palette.textMuted,
                    fontSize: 12,
                  ),
                )
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (badge != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badge!,
                    style: GoogleFonts.barlowCondensed(
                      color: palette.accent,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (onEdit != null)
                IconButton(
                  tooltip: 'Editar', // i18n
                  icon: Icon(
                    TreinoIcon.edit,
                    size: 15,
                    color: palette.textMuted,
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: onEdit,
                ),
              if (onDelete != null)
                IconButton(
                  tooltip: 'Eliminar', // i18n
                  icon: Icon(
                    TreinoIcon.trash,
                    size: 15,
                    color: palette.textMuted,
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: onDelete,
                ),
              IconButton(
                tooltip: 'Ver detalle', // i18n
                icon: Icon(
                  TreinoIcon.chartBar,
                  size: 16,
                  color: palette.textMuted,
                ),
                visualDensity: VisualDensity.compact,
                onPressed: () => showExerciseDetailDialog(
                  context,
                  exerciseId: id,
                  ownerId: isCustom ? ownerId : null,
                  exerciseName: name,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label, {required this.palette});

  final String label;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.barlowCondensed(
          color: palette.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

/// Inline "+ Crear ejercicio nuevo" row, pinned above the exercise list so it
/// stays reachable in every list state (results, empty, loading).
class _CreateNewExerciseButton extends StatelessWidget {
  const _CreateNewExerciseButton({required this.palette, required this.onTap});

  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const Key('create_new_exercise_button'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Icon(TreinoIcon.plus, size: 18, color: palette.accent),
            const SizedBox(width: 10),
            Text(
              'Crear ejercicio nuevo', // i18n
              style: GoogleFonts.barlow(
                color: palette.accent,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// No `package:collection` dependency in this project (mirrors the mobile
// picker's own `_FirstWhereOrNull` extension) — plain manual lookups instead.
Exercise? _exerciseWithId(List<Exercise> items, String id) {
  for (final e in items) {
    if (e.id == id) return e;
  }
  return null;
}

CustomExercise? _customWithId(List<CustomExercise> items, String id) {
  for (final c in items) {
    if (c.id == id) return c;
  }
  return null;
}

/// Ancho del panel lateral, en px lógicos.
///
/// 400 y no más: el editor de la izquierda tiene que seguir siendo LEGIBLE
/// mientras se elige, que es el punto del #860. A 1280 —el piso donde el panel
/// aparece— esto le deja 880 al editor, más que los 560 que ocupaba el modal
/// tapándolo todo.
const double kAnchoPanelPicker = 400;

/// El picker como PANEL LATERAL persistente (#860).
///
/// El modal dejaba 3 ejercicios visibles sobre un catálogo de cientos, pero el
/// alto era el síntoma: el problema es que TAPA la plantilla en cada iteración
/// del loop "miro qué puse → elijo el que sigue → miro cómo quedó". Este panel
/// no se cierra al agregar, así que ese loop no se rompe.
///
/// Comparte el contenido con [showExercisePickerDialog] — misma búsqueda,
/// mismos filtros, misma lista. Lo único que cambia es el hospedaje y que
/// confirmar llama a [onAgregar] en vez de cerrar.
///
/// Quién decide si se usa esto o el modal: el llamador, por `Viewport`. Ver el
/// comentario en el `build` del contenido.
class ExercisePickerPanel extends StatelessWidget {
  const ExercisePickerPanel({
    required this.dias,
    required this.diaElegido,
    required this.onElegirDia,
    required this.onAgregar,
    required this.onAgregarEnSuperserie,
    this.alreadySelectedIds = const {},
    super.key,
  });

  /// Los nombres de los días del plan, en orden.
  final List<String> dias;

  /// Índice del día que recibe lo que se agregue.
  ///
  /// Con los días APILADOS y el panel siempre abierto, esto tiene que estar a
  /// la vista y ser cambiable acá: los botones "Agregar ejercicio" de cada día
  /// —que antes eran los que ataban el panel a uno— ya no existen en desktop.
  /// Sin selector, el PF no tendría cómo saber ni elegir dónde cae.
  final int diaElegido;
  final ValueChanged<int> onElegirDia;

  final void Function(List<Exercise>) onAgregar;

  /// Agrega los elegidos YA ENLAZADOS como superserie. El botón que lo dispara
  /// aparece sólo con 2 o más seleccionados: una superserie de uno no existe.
  final void Function(List<Exercise>) onAgregarEnSuperserie;

  final Set<String> alreadySelectedIds;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: kAnchoPanelPicker,
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border(left: BorderSide(color: palette.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s18,
              AppSpacing.s14,
              AppSpacing.s18,
              AppSpacing.s8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Agregar a', // i18n
                  style: GoogleFonts.barlowCondensed(
                    color: palette.textMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: AppSpacing.hairline),
                // Un chip por día. Con un solo día igual se muestra: sacarlo
                // haría que el destino aparezca y desaparezca al agregar el
                // segundo, y el PF tendría que descubrirlo de nuevo.
                Wrap(
                  spacing: AppSpacing.hairline * 2,
                  runSpacing: AppSpacing.hairline * 2,
                  children: [
                    for (var i = 0; i < dias.length; i++)
                      _ChipDeDia(
                        key: Key('picker_panel_dia_$i'),
                        label: dias[i],
                        seleccionado: i == diaElegido,
                        palette: palette,
                        onTap: () => onElegirDia(i),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _ExercisePickerDialog(
              alreadySelectedIds: alreadySelectedIds,
              onAgregar: onAgregar,
              onAgregarEnSuperserie: onAgregarEnSuperserie,
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip de destino del panel: a qué día caen los ejercicios que se agreguen.
class _ChipDeDia extends StatelessWidget {
  const _ChipDeDia({
    required this.label,
    required this.seleccionado,
    required this.palette,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool seleccionado;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: seleccionado ? palette.accent : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s12,
            vertical: AppSpacing.hairline + 2,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(
              color: seleccionado ? palette.accent : palette.border,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.barlowCondensed(
              // Sobre `accent` va el ink invariante y NO `palette.bg`: en la
              // paleta light, bg sobre accent mide 1,57:1 (AGENTS.md regla 2).
              color: seleccionado
                  ? TreinoButtonTokens.foreground(context)
                  : palette.textMuted,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

