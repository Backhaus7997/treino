import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/workout/domain/exercise_feedback.dart';
import 'package:treino/features/workout/presentation/widgets/coach_note.dart';
import 'package:treino/features/workout/presentation/widgets/exercise_feedback_note.dart';
import 'package:treino/l10n/app_l10n.dart';

/// El tag de las dos notas iba pintado con el MISMO color que su fondo al 8%.
/// En la paleta clara eso mide 1.50:1 (mint) y 2.13:1 (ámbar) — a 10 px el tag
/// no se lee. AGENTS.md §2 pide medir en las DOS paletas todo par donde el
/// acento sea fondo; este archivo lo mide de verdad en vez de confiar en el
/// ojo, así que si alguien vuelve a poner `tint` en el texto, falla acá.
///
/// El umbral es 4.5:1 (WCAG AA, texto normal): 10 px no califica como "texto
/// grande" bajo ninguna lectura.
void main() {
  const minRatio = 4.5;

  double relativeLuminance(Color c) {
    double ch(double v) {
      final s = v / 255.0;
      return s <= 0.03928
          ? s / 12.92
          : math.pow((s + 0.055) / 1.055, 2.4) * 1.0;
    }

    return 0.2126 * ch(c.r * 255) +
        0.7152 * ch(c.g * 255) +
        0.0722 * ch(c.b * 255);
  }

  double contrast(Color fg, Color bg) {
    // El tag NO tiene alpha propio, pero sí lo tiene `textMuted` — se compone
    // sobre su fondo real antes de medir, o el número que sale es una fantasía.
    final solidFg = Color.alphaBlend(fg, bg);
    final a = relativeLuminance(solidFg), b = relativeLuminance(bg);
    return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
  }

  /// El fondo EFECTIVO del tag: `tint` al 8% compuesto sobre la superficie que
  /// lo hospeda. Medir contra `bgCard` pelado da un número que nadie ve.
  Color wash(Color tint, Color surface) =>
      Color.alphaBlend(tint.withValues(alpha: 0.08), surface);

  Future<void> pumpFeedbackNote(
    WidgetTester tester, {
    required ThemeData theme,
    required ExerciseFeedbackKind kind,
  }) =>
      tester.pumpWidget(MaterialApp(
        theme: theme,
        locale: const Locale('es', 'AR'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: Scaffold(
          body: ExerciseFeedbackNote(
            feedback: ExerciseFeedback(
              id: 'f1',
              exerciseId: 'bench-press',
              exerciseName: 'Press de banca',
              setNumber: 2,
              kind: kind,
              text: 'Me tira el hombro',
              createdAt: DateTime.utc(2026, 8, 24, 18, 30),
            ),
          ),
        ),
      ));

  Color tagColorOf(WidgetTester tester, String tag) =>
      tester.widget<Text>(find.text(tag)).style!.color!;

  // El ThemeData se construye DENTRO del test, no acá: `AppTheme.dark()` pide
  // fuentes por AssetBundle y a nivel de `main()` el binding todavía no existe.
  for (final variant
      in <({String name, ThemeData Function() theme, AppPalette palette})>[
    (
      name: 'dark',
      theme: AppTheme.dark,
      palette: AppPalette.mintMagenta,
    ),
    (
      name: 'light',
      theme: AppTheme.light,
      palette: AppPalette.mintMagentaLight,
    ),
  ]) {
    testWidgets(
        'ExerciseFeedbackNote: el tag de MOLESTIA se lee sobre su propio fondo '
        '(${variant.name})', (tester) async {
      await pumpFeedbackNote(
        tester,
        theme: variant.theme(),
        kind: ExerciseFeedbackKind.discomfort,
      );
      final l10n = await AppL10n.delegate.load(const Locale('es', 'AR'));
      final bg = wash(variant.palette.warning, variant.palette.bgCard);
      final fg = tagColorOf(tester, l10n.exerciseFeedbackNoteTagDiscomfort);

      expect(contrast(fg, bg), greaterThanOrEqualTo(minRatio));
      // Y explícitamente: el tint NO puede volver a ser el color del texto.
      expect(fg, isNot(variant.palette.warning));
    });

    testWidgets(
        'ExerciseFeedbackNote: el tag de COMENTARIO se lee sobre su propio '
        'fondo (${variant.name})', (tester) async {
      await pumpFeedbackNote(
        tester,
        theme: variant.theme(),
        kind: ExerciseFeedbackKind.comment,
      );
      final l10n = await AppL10n.delegate.load(const Locale('es', 'AR'));
      final bg = wash(variant.palette.accent, variant.palette.bgCard);
      final fg = tagColorOf(tester, l10n.exerciseFeedbackNoteTagComment);

      expect(contrast(fg, bg), greaterThanOrEqualTo(minRatio));
      expect(fg, isNot(variant.palette.accent));
    });

    testWidgets(
        'CoachNote: el tag DEL COACH se lee sobre su propio fondo '
        '(${variant.name})', (tester) async {
      // El espejo tiene el mismo defecto y se arregla en el mismo change: si
      // uno queda legible y el otro no, el par vuelve a desalinearse.
      await tester.pumpWidget(MaterialApp(
        theme: variant.theme(),
        locale: const Locale('es', 'AR'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: const Scaffold(body: CoachNote(text: 'Bajá la excéntrica')),
      ));
      final l10n = await AppL10n.delegate.load(const Locale('es', 'AR'));
      final bg = wash(variant.palette.accent, variant.palette.bgCard);
      final fg = tagColorOf(tester, l10n.exerciseNoteFromCoachTag);

      expect(contrast(fg, bg), greaterThanOrEqualTo(minRatio));
      expect(fg, isNot(variant.palette.accent));
    });
  }
}
