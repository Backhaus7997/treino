import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../workout/application/custom_exercise_providers.dart';
import '../../../workout/application/exercise_providers.dart';
import '../../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../../../workout/domain/custom_exercise.dart';
import '../../../workout/domain/exercise.dart';
import '../../../workout/presentation/custom_exercise_editor_screen.dart';

/// Shows a modal bottom sheet for picking an exercise.
///
/// Returns the selected [Exercise], or `null` if dismissed. The picker
/// merges two sources:
///   * The trainer's personal `customExercises` subcollection (top of the
///     list, under a "TUS EJERCICIOS" header).
///   * The public default catalogue (bottom, under "CATÁLOGO").
///
/// Custom exercises are converted to the [Exercise] shape on selection so
/// the caller's contract is unchanged. A pinned "+ Crear ejercicio nuevo"
/// tile pushes the [CustomExerciseEditorScreen] modally; if the editor
/// returns a freshly created custom exercise the picker pops with it
/// immediately so the slot fills without re-opening the sheet.
///
/// REQ-COACH-PLANS-024 · SCENARIO-458, 459.
Future<Exercise?> showExercisePicker(BuildContext context) {
  return showModalBottomSheet<Exercise>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ExercisePickerSheetContent(),
  );
}

class _ExercisePickerSheetContent extends ConsumerStatefulWidget {
  const _ExercisePickerSheetContent();

  @override
  ConsumerState<_ExercisePickerSheetContent> createState() =>
      _ExercisePickerSheetContentState();
}

class _ExercisePickerSheetContentState
    extends ConsumerState<_ExercisePickerSheetContent> {
  String _query = '';

  Future<void> _openCreateNew(BuildContext sheetContext) async {
    final created = await Navigator.of(sheetContext).push<CustomExercise?>(
      MaterialPageRoute<CustomExercise?>(
        builder: (_) => Scaffold(
          backgroundColor: AppPalette.of(sheetContext).bg,
          body: const SafeArea(
            child: CustomExerciseEditorScreen(exerciseId: 'new'),
          ),
        ),
      ),
    );
    if (created != null && sheetContext.mounted) {
      Navigator.of(sheetContext).pop(_toExercise(created));
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

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: palette.espresso,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Search field
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextField(
                  autofocus: true,
                  style: GoogleFonts.barlow(
                      color: palette.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    prefixIcon:
                        Icon(TreinoIcon.search, color: palette.textMuted),
                    hintText: 'Buscar ejercicio…',
                    hintStyle: GoogleFonts.barlow(
                        color: palette.textMuted, fontSize: 14),
                    filled: true,
                    fillColor: palette.bgCard,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
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

              // Create new CTA
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: _CreateNewTile(
                  palette: palette,
                  enabled: uid.isNotEmpty,
                  onTap: uid.isEmpty ? null : () => _openCreateNew(context),
                ),
              ),

              // Exercise list (customs + defaults)
              Expanded(
                child: _buildList(
                  scrollController: scrollController,
                  palette: palette,
                  defaults: defaultsAsync,
                  customs: customsAsync,
                ),
              ),

              // Safe area padding for home indicator
              SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildList({
    required ScrollController scrollController,
    required AppPalette palette,
    required AsyncValue<List<Exercise>> defaults,
    required AsyncValue<List<CustomExercise>> customs,
  }) {
    if (defaults.isLoading || customs.isLoading) {
      return Center(
        child: CircularProgressIndicator(color: palette.accent),
      );
    }
    if (defaults.hasError) {
      return Center(
        child: Text(
          'No pudimos cargar ejercicios.',
          style:
              GoogleFonts.barlow(color: palette.textMuted, fontSize: 14),
        ),
      );
    }
    final defaultList = defaults.value ?? const <Exercise>[];
    final customList = customs.value ?? const <CustomExercise>[];

    final q = _query.toLowerCase().trim();
    final filteredCustoms = q.isEmpty
        ? customList
        : customList
            .where((c) => c.name.toLowerCase().contains(q))
            .toList();
    final filteredDefaults = q.isEmpty
        ? defaultList
        : defaultList
            .where((e) => e.name.toLowerCase().contains(q))
            .toList();

    if (filteredCustoms.isEmpty && filteredDefaults.isEmpty) {
      return Center(
        child: Text(
          'Sin resultados.',
          style:
              GoogleFonts.barlow(color: palette.textMuted, fontSize: 14),
        ),
      );
    }

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        if (filteredCustoms.isNotEmpty) ...[
          _SectionHeader('Tus ejercicios', palette: palette),
          for (final c in filteredCustoms)
            ListTile(
              title: Text(
                c.name,
                style: GoogleFonts.barlow(
                  color: palette.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: c.muscleGroup.isEmpty
                  ? null
                  : Text(
                      c.muscleGroup,
                      style: GoogleFonts.barlow(
                          color: palette.textMuted, fontSize: 12),
                    ),
              trailing: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'MÍO',
                  style: GoogleFonts.barlowCondensed(
                    color: palette.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              onTap: () =>
                  Navigator.of(context).pop(_toExercise(c)),
            ),
        ],
        if (filteredDefaults.isNotEmpty) ...[
          _SectionHeader('Catálogo', palette: palette),
          for (final e in filteredDefaults)
            ListTile(
              title: Text(
                e.name,
                style: GoogleFonts.barlow(
                  color: palette.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: Text(
                e.muscleGroup,
                style: GoogleFonts.barlow(
                    color: palette.textMuted, fontSize: 12),
              ),
              onTap: () => Navigator.of(context).pop(e),
            ),
        ],
      ],
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
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.barlowCondensed(
          color: palette.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

class _CreateNewTile extends StatelessWidget {
  const _CreateNewTile({
    required this.palette,
    required this.enabled,
    required this.onTap,
  });

  final AppPalette palette;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: palette.bgCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: palette.accent, width: 1),
          ),
          child: Row(
            children: [
              Icon(TreinoIcon.plus, size: 18, color: palette.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Crear ejercicio nuevo',
                  style: GoogleFonts.barlow(
                    color: palette.accent,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(TreinoIcon.chevronRight,
                  size: 14,
                  color: palette.accent.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lossy adapter — projects the fields the routine slot needs (id, name,
/// muscleGroup) and stamps `category: 'custom'` so downstream code can
/// distinguish trainer-personal exercises from the public catalogue if it
/// ever needs to. The athlete-side detail screen falls back to the slot's
/// denormalized name/muscleGroup so it doesn't need a global lookup.
Exercise _toExercise(CustomExercise c) {
  return Exercise(
    id: c.id,
    name: c.name,
    muscleGroup: c.muscleGroup,
    category: 'custom',
    techniqueInstructions: null,
    videoUrl: c.videoUrl,
    defaultRestSeconds: c.defaultRestSeconds,
  );
}
