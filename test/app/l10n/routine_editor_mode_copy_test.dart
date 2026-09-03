// El copy del editor de rutina por modo (#871).
//
// El editor sirve a CUATRO modos y hasta este slice `TrainerTemplating` reusaba
// los strings de `TrainerAssigning`: crear una PLANTILLA —que no se asigna a
// nadie— mostraba "Crear plan" y un CTA que decía **"ASIGNAR PLAN"**. Es el
// único cambio de copy que el rediseño autoriza.
//
// Este test existe para que los otros tres modos NO se muevan al arreglarlo.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/l10n/app_l10n.dart';

void main() {
  late AppL10n l10n;

  setUpAll(() async {
    l10n = await AppL10n.delegate.load(const Locale('es', 'AR'));
  });

  group('plantillas — copy propio', () {
    test('crear dice "Nueva plantilla", no "Crear plan"', () {
      expect(l10n.coachTemplateEditorTitle, 'Nueva plantilla');
      expect(l10n.coachTemplateEditorTitle, isNot(l10n.coachEditorTitle));
    });

    test('editar dice "Editar plantilla"', () {
      expect(l10n.coachTemplateEditorEditTitle, 'Editar plantilla');
    });

    test('el CTA dice "GUARDAR PLANTILLA", no "ASIGNAR PLAN"', () {
      expect(l10n.coachTemplateEditorSubmit, 'GUARDAR PLANTILLA');
      expect(l10n.coachTemplateEditorSubmit, isNot(l10n.coachEditorSubmit),
          reason: 'una plantilla no se asigna a nadie: ese era el bug');
    });
  });

  group('los otros tres modos conservan su copy exacto', () {
    test('TrainerAssigning', () {
      expect(l10n.coachEditorTitle, 'Crear plan');
      expect(l10n.coachEditorSubmit, 'ASIGNAR PLAN');
      expect(l10n.coachEditorUpdateLabel, 'GUARDAR CAMBIOS');
    });

    test('SelfCreating', () {
      expect(l10n.workoutSelfEditorTitle, isNotEmpty);
      expect(l10n.workoutSelfEditorSubmitLabel, isNotEmpty);
      expect(l10n.workoutSelfEditorSubmitLabel,
          isNot(l10n.coachTemplateEditorSubmit));
    });

    test('SelfCustomizing — el modo que el handoff se olvidaba', () {
      // El handoff listaba tres modos; el código tiene cuatro. Todo lo que
      // toque títulos o CTA cubre los cuatro.
      expect(l10n.workoutRoutineCustomizeTitle, isNotEmpty);
      expect(l10n.workoutRoutineCustomizeSubmitLabel, 'GUARDAR COMO MÍA');
    });
  });

  test('los cuatro CTA son distintos entre sí', () {
    final ctas = {
      l10n.coachEditorSubmit,
      l10n.coachTemplateEditorSubmit,
      l10n.workoutSelfEditorSubmitLabel,
      l10n.workoutRoutineCustomizeSubmitLabel,
    };
    expect(ctas.length, 4,
        reason: 'si dos modos comparten CTA, alguno está diciendo algo que no '
            'hace — que es exactamente lo que pasaba con plantillas');
  });
}
