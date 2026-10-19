import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/floating_bar_metrics.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/presentation/routine_detail_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

/// #1559: el botón «atrás» flota sobre el contenido; el encabezado de una
/// rutina SIN pills (sin coach ni split) no puede quedar debajo de él.
void main() {
  testWidgets('el título arranca debajo del botón atrás (rutina sin pills)', (
    tester,
  ) async {
    const routine = Routine(
      id: 'own-1',
      name: 'Mi rutina',
      level: ExperienceLevel.beginner,
      days: [
        RoutineDay(
          dayNumber: 1,
          name: 'Título del día',
          slots: [
            RoutineSlot(
              exerciseId: 'bench-press',
              exerciseName: 'Bench Press',
              muscleGroup: 'chest',
              targetSets: 3,
              targetRepsMin: 8,
              targetRepsMax: 12,
              restSeconds: 90,
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          routineByIdStreamProvider('own-1')
              .overrideWith((ref) => Stream.value(routine)),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
          home: const Scaffold(body: RoutineDetailScreen(routineId: 'own-1')),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    final back = find.ancestor(
      of: find.byIcon(TreinoIcon.back),
      matching: find.byType(IconButton),
    );
    final header = find.byKey(const Key('routine-compact-header'));
    final title = find.descendant(
      of: header,
      matching: find.text('TÍTULO DEL DÍA'),
    );
    expect(back, findsOneWidget);
    expect(header, findsOneWidget);
    expect(title, findsOneWidget);

    // Posiciones, no anchos de texto: el título debe quedar por debajo del
    // borde inferior del botón.
    final backBottom = tester.getBottomLeft(back).dy;
    expect(tester.getTopLeft(title).dy, greaterThanOrEqualTo(backBottom));

    // Y el espacio reservado sale de la constante compartida.
    expect(
      tester.getTopLeft(header).dy + FloatingBarMetrics.reservedHeight,
      greaterThanOrEqualTo(backBottom),
    );
  });
}
