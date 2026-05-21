import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../workout/application/exercise_providers.dart';
import '../../../workout/domain/exercise.dart';

/// Shows a modal bottom sheet for picking an exercise.
///
/// Returns the selected [Exercise], or `null` if dismissed.
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

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final exercisesAsync = ref.watch(exercisesProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: palette.espresso,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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

              // Exercise list
              Expanded(
                child: exercisesAsync.when(
                  loading: () => Center(
                    child: CircularProgressIndicator(color: palette.accent),
                  ),
                  error: (_, __) => Center(
                    child: Text(
                      'No pudimos cargar ejercicios.',
                      style: GoogleFonts.barlow(
                          color: palette.textMuted, fontSize: 14),
                    ),
                  ),
                  data: (exercises) {
                    final filtered = _query.isEmpty
                        ? exercises
                        : exercises
                            .where((e) => e.name
                                .toLowerCase()
                                .contains(_query.toLowerCase()))
                            .toList();

                    if (filtered.isEmpty) {
                      return Center(
                        child: Text(
                          'Sin resultados.',
                          style: GoogleFonts.barlow(
                              color: palette.textMuted, fontSize: 14),
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final exercise = filtered[index];
                        return ListTile(
                          title: Text(
                            exercise.name,
                            style: GoogleFonts.barlow(
                              color: palette.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            exercise.muscleGroup,
                            style: GoogleFonts.barlow(
                                color: palette.textMuted, fontSize: 12),
                          ),
                          onTap: () => Navigator.of(context).pop(exercise),
                        );
                      },
                    );
                  },
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
}
