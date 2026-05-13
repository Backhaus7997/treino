import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../application/routine_providers.dart';

class RoutineDetailPlaceholderScreen extends ConsumerWidget {
  const RoutineDetailPlaceholderScreen({
    required this.routineId,
    super.key,
  });

  final String routineId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    final routineAsync = ref.watch(routineByIdProvider(routineId));

    final String titleText = routineAsync.maybeWhen(
      data: (r) => r?.name.toUpperCase() ?? 'PLANTILLA',
      orElse: () => 'PLANTILLA',
    );

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: palette.bg,
        foregroundColor: palette.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(TreinoIcon.back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          titleText,
          style: theme.textTheme.titleLarge,
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: routineAsync.when(
            data: (routine) {
              if (routine == null) {
                return Text(
                  'No encontramos esta plantilla.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: palette.textMuted,
                  ),
                );
              }
              return Text(
                'Detalle disponible próximamente.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: palette.textMuted,
                ),
              );
            },
            loading: () => CircularProgressIndicator(color: palette.accent),
            error: (_, __) => Text(
              'No pudimos cargar la plantilla.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: palette.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
