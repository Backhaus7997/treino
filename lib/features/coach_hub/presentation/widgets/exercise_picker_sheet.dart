import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../workout/domain/exercise.dart';

/// Bottom sheet con search + lista del catálogo de exercises.
/// Devuelve el [Exercise] elegido (o null si el PF cancela).
///
/// Compartido entre el preview simple y el periodizado para resolver
/// ejercicios "sin match" a mano.
class ExercisePickerSheet extends StatefulWidget {
  const ExercisePickerSheet({
    super.key,
    required this.rowName,
    required this.exercises,
  });
  final String rowName;
  final List<Exercise> exercises;

  @override
  State<ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<ExercisePickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Exercise> get _filtered {
    final q = _query.toLowerCase().trim();
    if (q.isEmpty) return widget.exercises;
    return widget.exercises.where((e) {
      if (e.name.toLowerCase().contains(q)) return true;
      if (e.muscleGroup.toLowerCase().contains(q)) return true;
      for (final alias in e.aliases) {
        if (alias.toLowerCase().contains(q)) return true;
      }
      return false;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final filtered = _filtered;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (_, scrollController) => Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          top: 18,
          bottom: MediaQuery.of(context).viewInsets.bottom + 18,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Asignar a "${widget.rowName}"',
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              autofocus: true,
              style: TextStyle(color: palette.textPrimary),
              decoration: InputDecoration(
                hintText: 'Buscar ejercicio…',
                hintStyle: TextStyle(color: palette.textMuted),
                prefixIcon: Icon(TreinoIcon.search, color: palette.textMuted),
                filled: true,
                fillColor: palette.bg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: palette.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: palette.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: palette.accent, width: 1.5),
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'Sin resultados.',
                        style: TextStyle(color: palette.textMuted),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: palette.border,
                      ),
                      itemBuilder: (_, i) {
                        final ex = filtered[i];
                        return ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          title: Text(
                            ex.name,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            ex.muscleGroup,
                            style: TextStyle(
                              color: palette.textMuted,
                              fontSize: 12,
                            ),
                          ),
                          onTap: () => Navigator.of(context).pop(ex),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
