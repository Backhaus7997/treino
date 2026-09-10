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
import 'package:treino/features/coach_hub/presentation/widgets/button/treino_button.dart';
import 'package:treino/features/coach_hub/application/picker_panel_width_provider.dart';

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

  int get _cantidadDeFiltros =>
      _muscleFilters.length + _equipmentFilters.length;

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
    final alAgregar =
        enSuperserie ? widget.onAgregarEnSuperserie : widget.onAgregar;
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
            fontSize: AppTextSize.title,
          ),
        ),
        content: Text(
          // Slots denormalize the name/group at assign time, so existing
          // routines keep working after the library entry is gone.
          'Se borra "${exercise.name}" de tu biblioteca. Las rutinas que ya lo '
          'usan no se tocan.', // i18n
          style: GoogleFonts.barlow(
              color: palette.textMuted, fontSize: AppTextSize.bodyDense),
        ),
        actions: [
          TreinoButton(
            label: 'Cancelar', // i18n
            variant: TreinoButtonVariant.ghost,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          const SizedBox(width: AppSpacing.s8),
          TreinoButton(
            label: 'Eliminar', // i18n
            variant: TreinoButtonVariant.danger,
            onPressed: () => Navigator.of(ctx).pop(true),
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
                    fontSize: AppTextSize.title,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              TreinoIconButton(
                icon: TreinoIcon.close,
                tooltip: 'Cerrar', // i18n
                color: palette.textMuted,
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
              fontSize: AppTextSize.body,
            ),
            decoration: InputDecoration(
              prefixIcon: Icon(TreinoIcon.search, color: palette.textMuted),
              suffixIcon: _query.isEmpty
                  ? null
                  : TreinoIconButton(
                      icon: TreinoIcon.close,
                      tooltip: 'Borrar', // i18n
                      color: palette.textMuted,
                      size: TreinoButtonSize.xs,
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
              hintText: 'Buscar ejercicio…', // i18n
              hintStyle: GoogleFonts.barlow(
                color: palette.textMuted,
                fontSize: AppTextSize.body,
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
            // Con filtros puestos el botón pasa a acento: la variante DICE si
            // hay filtros activos, en vez de un `color:` calculado a mano.
            child: TreinoButton(
              key: const Key('picker_filtros_toggle'),
              label: _cantidadDeFiltros == 0
                  ? 'Filtros' // i18n
                  : 'Filtros ($_cantidadDeFiltros)', // i18n
              icon: _filtrosAbiertos
                  ? TreinoIcon.chevronUp
                  : TreinoIcon.chevronDown,
              variant: _cantidadDeFiltros == 0
                  ? TreinoButtonVariant.ghost
                  : TreinoButtonVariant.ghostAccent,
              size: TreinoButtonSize.sm,
              onPressed: () =>
                  setState(() => _filtrosAbiertos = !_filtrosAbiertos),
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
              onEquipmentChanged: (v) => setState(() => _equipmentFilters = v),
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
          // `Wrap` y no `Row`: acá conviven hasta TRES botones —Cancelar, En
          // superserie, Agregar (N)— y este pie vive tanto en un diálogo como
          // en un panel lateral de 400 px. Con `Row` la tercera opción hacía
          // desbordar la fila; envueltos, bajan a una segunda línea. Los
          // labels además se traducen, así que el ancho no es un número que
          // podamos fijar de antemano.
          child: Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 0,
            runSpacing: AppSpacing.s8,
            children: [
              // "Cancelar" SÓLO en modo diálogo. En el panel no hay ruta que
              // cerrar: `Navigator.pop()` saldría del editor entero, que es
              // exactamente lo contrario de lo que el botón promete. El panel
              // se cierra con su propia X.
              if (widget.onAgregar == null) ...[
                TreinoButton(
                  label: 'Cancelar', // i18n
                  variant: TreinoButtonVariant.ghost,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: AppSpacing.s8),
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
                  child: TreinoButton(
                    key: const Key('picker_agregar_superserie'),
                    label: 'En superserie', // i18n
                    icon: TreinoIcon.streak,
                    variant: TreinoButtonVariant.secondary,
                    onPressed: () => _confirm(
                      defaultsAsync.valueOrNull ?? const [],
                      customsAsync.valueOrNull ?? const [],
                      enSuperserie: true,
                    ),
                  ),
                ),
              TreinoButton(
                label: _selected.isEmpty
                    ? 'Agregar' // i18n
                    : 'Agregar (${_selected.length})', // i18n
                onPressed: _selected.isEmpty
                    ? null
                    : () => _confirm(
                          defaultsAsync.valueOrNull ?? const [],
                          customsAsync.valueOrNull ?? const [],
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
          style: GoogleFonts.barlow(
              color: palette.textMuted, fontSize: AppTextSize.body),
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
            style: GoogleFonts.barlow(
                color: palette.textMuted, fontSize: AppTextSize.body),
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
            fontSize: AppTextSize.caption,
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
              fontSize: AppTextSize.body,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: subtitle != null && subtitle!.isNotEmpty
              ? Text(
                  subtitle!,
                  style: GoogleFonts.barlow(
                    color: palette.textMuted,
                    fontSize: AppTextSize.caption,
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
                      fontSize: AppTextSize.micro,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (onEdit != null)
                TreinoIconButton(
                  icon: TreinoIcon.edit,
                  tooltip: 'Editar', // i18n
                  color: palette.textMuted,
                  size: TreinoButtonSize.xs,
                  onPressed: onEdit,
                ),
              if (onDelete != null)
                TreinoIconButton(
                  icon: TreinoIcon.trash,
                  tooltip: 'Eliminar', // i18n
                  color: palette.textMuted,
                  size: TreinoButtonSize.xs,
                  onPressed: onDelete,
                ),
              TreinoIconButton(
                icon: TreinoIcon.chartBar,
                tooltip: 'Ver detalle', // i18n
                color: palette.textMuted,
                size: TreinoButtonSize.xs,
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
          fontSize: AppTextSize.caption,
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
                fontSize: AppTextSize.body,
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

/// Ancho POR DEFECTO del panel lateral, en px lógicos.
///
/// Era fijo, y ahí estaba el problema: el editor de la izquierda tiene que
/// seguir siendo legible mientras se elige (el punto del #860), pero clavar el
/// panel en 400 significaba que un monitor de 1920 no le sumaba un píxel a
/// NADIE — ni al panel ni a la rutina. Ahora es el punto de partida y lo mueve
/// quien quiera, entre `kAnchoPanelPickerMin` y lo que deje la rutina.
///
/// Ver `picker_panel_width_provider.dart` para el rango y por qué.
const double kAnchoPanelPicker = kAnchoPanelPickerDefault;

/// Ancho del asa de arrastre: `AppSpacing.s8`.
///
/// Es el primer separador arrastrable del hub, así que no hay precedente que
/// copiar — el número sale de la escala de spacing, que es lo que el guard
/// `no_off_scale_spacing_scan` permite.
///
/// Ocho y no uno: un asa del ancho del borde que dibuja es imposible de
/// agarrar sin apuntar. El borde sigue midiendo 1 px; lo que mide 8 es el
/// blanco de agarre, que es invisible salvo por el cursor.
const double kAnchoAsaPanel = AppSpacing.s8;

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
    this.width = kAnchoPanelPicker,
    this.onResize,
    super.key,
  });

  /// Ancho actual del panel. Lo decide el llamador, que es el único que sabe
  /// cuánto lugar hay — ver `maxAnchoPanelPicker`.
  final double width;

  /// Arrastre del asa, en px. Positivo = el panel se ENSANCHA.
  ///
  /// `null` apaga el asa: en el modal no hay nada que redimensionar.
  final ValueChanged<double>? onResize;

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
    final panel = Container(
      width: width,
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: onResize == null
            ? Border(left: BorderSide(color: palette.border))
            : null,
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
                    fontSize: AppTextSize.caption,
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

    if (onResize == null) return panel;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_AsaDeArrastre(onResize: onResize!), panel],
    );
  }
}

/// El asa que ensancha y angosta el panel.
///
/// Va en su BORDE IZQUIERDO, que es el que da contra la rutina: arrastrar
/// hacia la izquierda agranda el panel, y es el mismo gesto que en cualquier
/// otro panel redimensionable. El delta llega en px de pantalla, así que
/// ensanchar es `-delta`; esa inversión la hace el llamador, que es el que
/// sabe de qué lado está.
///
/// El asa mide 8 px de ancho pero sólo DIBUJA el borde de 1 que ya estaba. Los
/// otros 7 son blanco de agarre: invisibles salvo por el cursor, que cambia a
/// `resizeLeftRight` al pasar por encima. Sin eso el asa sería del ancho del
/// borde y habría que apuntarle.
class _AsaDeArrastre extends StatelessWidget {
  const _AsaDeArrastre({required this.onResize});

  final ValueChanged<double> onResize;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => onResize(d.delta.dx),
        child: SizedBox(
          width: kAnchoAsaPanel,
          child: Align(
            alignment: Alignment.centerRight,
            child: Container(width: 1, color: palette.border),
          ),
        ),
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
              fontSize: AppTextSize.caption,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
