import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/floating_bar_metrics.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/presentation/exercise_detail_screen.dart';
import 'package:treino/features/workout/presentation/routine_detail_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

/// #1559: los botones circulares flotan (`Positioned(top: 0)`) sobre el
/// contenido, y el encabezado compacto (sin foto) reserva arriba el alto
/// necesario para que nada quede debajo de ellos.
///
/// En develop el solapamiento NO se reprodujo: esto es un candado, no la
/// prueba de un fix. Fija el invariante con medidas REALES —el `getRect` del
/// `IconButton` montado, no la constante— contra donde arranca de verdad el
/// contenido del encabezado, con el texto agrandado, un notch simulado y la
/// el tap target del escritorio. En M3 el `IconButton` ignora
/// `ThemeData.visualDensity`, pero `MaterialTapTargetSize.shrinkWrap` —el
/// default en macOS / Windows / Linux, incluida la web en desktop— lo deja en
/// 40 px en vez de 48 si nadie le fija el tamaño.

const _uid = 'athlete-1';
const _safeTop = 47.0;

/// Toda `IconButton` montada dentro de una barra flotante de la pantalla.
Finder _floatingButtons() => find.descendant(
      of: find.byWidgetPredicate((w) => w is Positioned && w.top == 0),
      matching: find.byType(IconButton),
    );

/// La `Column` del encabezado que contiene el título: su borde superior es
/// donde arranca el contenido que el botón no puede pisar.
Finder _headerContent(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(Column)).first;

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  required List<Override> overrides,
  required MaterialTapTargetSize tapTarget,
}) async {
  // Ancho y alto de sobra: a 2× de texto hay filas del CUERPO que ya
  // desbordan a 390 px (otra deuda), y acá sólo se mide el encabezado.
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  tester.view.padding = const FakeViewPadding(top: _safeTop);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [currentUidProvider.overrideWithValue(_uid), ...overrides],
      child: MaterialApp(
        theme: AppTheme.dark().copyWith(materialTapTargetSize: tapTarget),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
          ),
          child: child!,
        ),
        // Como el shell: el SafeArea consume el notch antes de la pantalla.
        home: Scaffold(body: SafeArea(child: screen)),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

void _expectButtonsClearContent(
  WidgetTester tester, {
  required String title,
  required int expectedButtons,
}) {
  final buttons = _floatingButtons();
  expect(buttons, findsNWidgets(expectedButtons));

  final contentTop = tester.getRect(_headerContent(title)).top;
  for (final element in buttons.evaluate()) {
    final rect = tester.getRect(find.byWidget(element.widget));

    // El botón mide lo que dice la fuente única, sea cual sea la densidad.
    expect(rect.size, const Size.square(FloatingBarMetrics.buttonSize));
    // Y cuelga del borde del área segura, no del de la pantalla.
    expect(rect.top, _safeTop + FloatingBarMetrics.topInset);
    // El invariante: el contenido arranca debajo del botón, con aire.
    expect(
      contentTop,
      greaterThanOrEqualTo(rect.bottom + FloatingBarMetrics.clearance),
      reason: 'el botón $rect pisa el contenido que arranca en $contentTop',
    );
  }
}

const _slot = RoutineSlot(
  exerciseId: 'bench-press',
  exerciseName: 'Bench Press',
  muscleGroup: 'chest',
  targetSets: 3,
  targetRepsMin: 8,
  targetRepsMax: 12,
  restSeconds: 90,
);

// Rutina propia sin foto ni coach: encabezado compacto con la menor cantidad
// de pills, y con el botón editar a la derecha.
const _ownRoutine = Routine(
  id: 'own-1',
  name: 'Mi rutina',
  level: ExperienceLevel.beginner,
  source: RoutineSource.userCreated,
  createdBy: _uid,
  days: [
    RoutineDay(dayNumber: 1, name: 'Título del día', slots: [_slot])
  ],
);

void main() {
  const tapTargets = {
    'móvil (padded)': MaterialTapTargetSize.padded,
    'escritorio (shrinkWrap)': MaterialTapTargetSize.shrinkWrap,
  };
  for (final MapEntry(key: name, value: tapTarget) in tapTargets.entries) {
    group('tap target $name', () {
      testWidgets('routine_detail: los botones no pisan el encabezado', (
        tester,
      ) async {
        await _pump(
          tester,
          const RoutineDetailScreen(routineId: 'own-1'),
          tapTarget: tapTarget,
          overrides: [
            routineByIdStreamProvider('own-1')
                .overrideWith((ref) => Stream.value(_ownRoutine)),
          ],
        );

        // Atrás + editar.
        _expectButtonsClearContent(
          tester,
          title: 'TÍTULO DEL DÍA',
          expectedButtons: 2,
        );
      });

      testWidgets('exercise_detail: el botón atrás no pisa el encabezado', (
        tester,
      ) async {
        await _pump(
          tester,
          const ExerciseDetailScreen(exerciseId: 'mi-ejercicio'),
          tapTarget: tapTarget,
          overrides: [
            // `custom` → encabezado compacto, sin foto.
            exerciseByIdProvider('mi-ejercicio').overrideWith(
              (ref) async => const Exercise(
                id: 'mi-ejercicio',
                name: 'Mi ejercicio',
                muscleGroup: 'Pecho',
                category: 'custom',
              ),
            ),
          ],
        );

        _expectButtonsClearContent(
          tester,
          title: 'MI EJERCICIO',
          expectedButtons: 1,
        );
      });
    });
  }
}
