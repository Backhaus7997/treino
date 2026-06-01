import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../application/custom_exercise_providers.dart';
import '../application/session_providers.dart' show currentUidProvider;
import '../domain/custom_exercise.dart';

/// Trainer's personal exercise library — list + entry point to create more.
class MyExercisesScreen extends ConsumerWidget {
  const MyExercisesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final uid = ref.watch(currentUidProvider) ?? '';
    final exercisesAsync = uid.isEmpty
        ? const AsyncValue<List<CustomExercise>>.data(<CustomExercise>[])
        : ref.watch(customExercisesForTrainerStreamProvider(uid));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => context.pop(),
                behavior: HitTestBehavior.opaque,
                child:
                    Icon(TreinoIcon.back, size: 20, color: palette.textPrimary),
              ),
              const SizedBox(width: 14),
              Text(
                'MIS EJERCICIOS',
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  letterSpacing: 1.0,
                  color: palette.textPrimary,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: exercisesAsync.when(
            loading: () =>
                Center(child: CircularProgressIndicator(color: palette.accent)),
            error: (_, __) => Center(
              child: Text(
                'No pudimos cargar tus ejercicios.',
                style: GoogleFonts.barlow(fontSize: 14, color: palette.textMuted),
              ),
            ),
            data: (items) => items.isEmpty
                ? _EmptyState(palette: palette)
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                    physics: const ClampingScrollPhysics(),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) =>
                        _ExerciseCard(exercise: items[i], palette: palette),
                  ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => context.push('/profile/my-exercises/new'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: palette.bg,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9999),
                  ),
                ),
                child: Text(
                  '+ NUEVO EJERCICIO',
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(TreinoIcon.sparkle, size: 48, color: palette.textMuted),
            const SizedBox(height: 18),
            Text(
              'Tu biblioteca está vacía.',
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: palette.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Creá ejercicios con el nombre que vos usás y un video de referencia. Quedan guardados solo para vos.',
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w400,
                fontSize: 13,
                color: palette.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({required this.exercise, required this.palette});
  final CustomExercise exercise;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.bgCard,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => context.push('/profile/my-exercises/${exercise.id}'),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.border, width: 1),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exercise.name,
                      style: GoogleFonts.barlow(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: palette.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (exercise.muscleGroup.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        exercise.muscleGroup,
                        style: GoogleFonts.barlow(
                          fontWeight: FontWeight.w400,
                          fontSize: 12,
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (exercise.videoUrl != null && exercise.videoUrl!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(TreinoIcon.play, size: 16, color: palette.accent),
                ),
              Icon(TreinoIcon.forward, size: 16, color: palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
