// La hoja de acciones de un ejercicio (#871), aislada.
//
// Era un `PopupMenuButton`: un menú flotante de ítems de ~40 dp colgado de un
// ícono de 20. Las acciones son las MISMAS —`_SlotAction` no cambia—; lo que
// cambia es dónde se muestran y de qué tamaño.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/workout/presentation/widgets/exercise_actions_sheet.dart';
import 'package:treino/l10n/app_l10n.dart';

const _kAcciones = [
  ExerciseAction(id: 'toggle', label: 'Colapsar sets', icon: Icons.expand_less),
  ExerciseAction(id: 'replace', label: 'Cambiar ejercicio', icon: Icons.edit),
  ExerciseAction(
    id: 'copy',
    label: 'Copiar sets del anterior',
    icon: Icons.copy,
    enabled: false,
  ),
  ExerciseAction(
    id: 'remove',
    label: 'Eliminar',
    icon: Icons.delete,
    danger: true,
  ),
];

Future<void> _montar(
  WidgetTester tester, {
  String titulo = 'Press de Banca',
  List<ExerciseAction> acciones = _kAcciones,
  void Function(Object)? onPick,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(
        body: ExerciseActionsSheet(
          title: titulo,
          actions: acciones,
          onPick: onPick ?? (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _accion(String id) => find.byKey(Key('exercise_sheet_action_$id'));

void main() {
  testWidgets('dice sobre qué ejercicio se está actuando', (tester) async {
    // Con la hoja abierta la card queda tapada: sin el título no se ve cuál es.
    await _montar(tester);
    expect(
      tester.widget<Text>(find.byKey(const Key('exercise_sheet_title'))).data,
      'Press de Banca',
    );
  });

  testWidgets('lista las acciones en orden', (tester) async {
    await _montar(tester);
    for (final a in _kAcciones) {
      expect(find.text(a.label), findsOneWidget);
    }
  });

  testWidgets('cada ítem llega al mínimo táctil de 48', (tester) async {
    await _montar(tester);
    expect(tester.getSize(_accion('replace')).height, 48,
        reason: 'el menú anterior daba ~40 por ítem');
  });

  testWidgets('devuelve la acción tocada', (tester) async {
    Object? elegida;
    await _montar(tester, onPick: (id) => elegida = id);
    await tester.tap(_accion('replace'));
    expect(elegida, 'replace');
  });

  group('una acción deshabilitada NO responde', () {
    testWidgets('el tap no la dispara', (tester) async {
      final tocadas = <Object>[];
      await _montar(tester, onPick: tocadas.add);

      await tester.tap(_accion('copy'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(tocadas, isEmpty,
          reason: 'un ítem que responde y no hace nada es peor que uno que se '
              've claramente inerte');
    });

    testWidgets('su InkWell tiene onTap nulo — sin ripple tampoco',
        (tester) async {
      await _montar(tester);
      expect(tester.widget<InkWell>(_accion('copy')).onTap, isNull);
      expect(tester.widget<InkWell>(_accion('replace')).onTap, isNotNull);
    });

    testWidgets('se anuncia deshabilitada', (tester) async {
      final handle = tester.ensureSemantics();
      await _montar(tester);
      final s = tester.getSemantics(_accion('copy'));
      expect(s.label, 'Copiar sets del anterior');
      handle.dispose();
    });
  });

  testWidgets('la destructiva se pinta distinto de las demás', (tester) async {
    await _montar(tester);
    Color colorDe(String id) => tester
        .widget<Icon>(
            find.descendant(of: _accion(id), matching: find.byType(Icon)))
        .color!;

    expect(colorDe('remove'), isNot(colorDe('replace')),
        reason: 'eliminar va en danger: es la única que no se deshace');
  });

  testWidgets('el chrome replica el de la hoja del plan', (tester) async {
    // Son las dos superficies modales del editor y tienen que leerse igual.
    await _montar(tester);
    expect(find.byType(SafeArea), findsWidgets);
    expect(find.byKey(const Key('exercise_sheet_title')), findsOneWidget);
  });

  testWidgets('sin ícono propio no rompe el layout', (tester) async {
    await _montar(
      tester,
      acciones: const [
        ExerciseAction(id: 'x', label: 'Sola', icon: TreinoIcon.edit),
      ],
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Sola'), findsOneWidget);
  });
}
