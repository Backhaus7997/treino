import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/widgets/motion/treino_shimmer.dart';
import 'package:treino/core/widgets/motion/treino_state_switcher.dart';
import 'package:treino/features/coach/application/athlete_note_providers.dart';

/// Tarjeta de la nota fijada del PF sobre el alumno en el tab Resumen —
/// Fase 3 WU-05 (extraído de `_NoteCard`, `alumno_detail_screen.dart`,
/// ADR-A3-04).
///
/// Reutiliza [athleteNoteProvider] — el mismo que usa el tab Notas privadas.
/// Trunca a 3 líneas + "hace X días" del updatedAt. Sin nota → estado vacío.
class NoteCard extends ConsumerWidget {
  const NoteCard({
    super.key,
    required this.palette,
    required this.trainerId,
    required this.athleteId,
  });

  final AppPalette palette;
  final String trainerId;
  final String athleteId;

  String _haceDias(DateTime updatedAt) {
    final diff = DateTime.now().difference(updatedAt.toLocal());
    final days = diff.inDays;
    if (days == 0) return 'hoy';
    if (days == 1) return 'hace 1 día';
    return 'hace $days días';
  }

  Widget _box(Widget child) => Container(
        padding: const EdgeInsets.all(AppSpacing.s14),
        decoration: BoxDecoration(
          color: palette.bgCard,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: child,
      );

  Widget _skeleton() => _box(
        TreinoShimmer(
          child: Column(
            key: const Key('nota_skeleton'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < 2; i++) ...[
                Container(
                  height: 12,
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                if (i == 0) const SizedBox(height: AppSpacing.s8),
              ],
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(
      athleteNoteProvider((trainerId: trainerId, athleteId: athleteId)),
    );
    final String stateKey;
    final Widget content;

    if (async.isLoading && !async.hasValue) {
      stateKey = 'loading';
      content = _skeleton();
    } else if (async.hasError) {
      stateKey = 'error';
      content = _box(Text('No se pudo cargar la nota.',
          style: TextStyle(color: palette.textMuted, fontSize: 13)));
    } else {
      final note = async.valueOrNull;
      final empty = note == null || note.note.trim().isEmpty;
      stateKey = empty ? 'empty' : 'data';
      content = _box(
        empty
            ? Text(
                'Sin nota fijada.', // i18n: Fase W2
                style: TextStyle(color: palette.textMuted, fontSize: 13),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.note,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s8 - 2),
                  Text(
                    _haceDias(note.updatedAt), // i18n: Fase W2
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
      );
    }

    return TreinoStateSwitcher(
      childKey: ValueKey('nota_$stateKey'),
      child: content,
    );
  }
}
