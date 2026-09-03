// Los dibujos del onboarding del editor citan labels de la app REAL.
//
// El dartdoc de `custom_exercise_onboarding_art.dart` promete «si un label
// cambia allá, cambialo acá». Hasta acá esa promesa era un comentario: nadie
// la hacía cumplir, y un onboarding que enseña un botón que ya se llama de
// otra forma es peor que no tener onboarding — le hace perder tiempo al
// usuario buscando algo que no existe.
//
// Este archivo la vuelve ejecutable para las cuatro ilustraciones del editor:
// si alguien renombra `routineEditorSetTypeWarmup` o `A TODAS`, el test cae.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/onboarding/presentation/custom_exercise_onboarding_art.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../../helpers/layout_failure.dart';

/// Dibuja [art] y devuelve el `AppL10n` con el que se rindió, para comparar
/// contra los mismos strings que ve el usuario.
Future<AppL10n> _pumpArt(WidgetTester tester, Widget art) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  late AppL10n l10n;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            l10n = AppL10n.of(context);
            return Center(child: SizedBox(height: 240, child: art));
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return l10n;
}

void main() {
  testWidgets('tipos de serie: los cuatro, verbatim del ARB', (tester) async {
    final l10n = await _pumpArt(
      tester,
      const CustomExerciseOnboardingArt.setTypes(),
    );

    for (final tipo in [
      l10n.routineEditorSetTypeNormal,
      l10n.routineEditorSetTypeWarmup,
      l10n.routineEditorSetTypeDrop,
      l10n.routineEditorSetTypeFailure,
    ]) {
      expect(find.text(tipo), findsOneWidget,
          reason: 'el dibujo promete un tipo que el menú real no ofrece');
    }
    expect(drainLayoutFailure(tester), isNull);
  });

  testWidgets('barra del teclado: «A TODAS» y su confirmación', (tester) async {
    final l10n = await _pumpArt(
      tester,
      const CustomExerciseOnboardingArt.keyboardBar(),
    );

    expect(find.text(l10n.routineEditorFillColumnLabel), findsOneWidget);
    expect(find.text(l10n.routineEditorFillKgApplied), findsOneWidget);
    expect(find.text(l10n.routineEditorFillKgUndo), findsOneWidget);
    expect(drainLayoutFailure(tester), isNull);
  });

  testWidgets('semanas: el título del diálogo y sus dos alcances',
      (tester) async {
    final l10n = await _pumpArt(
      tester,
      const CustomExerciseOnboardingArt.weeks(),
    );

    expect(find.text(l10n.routineEditorAddScopeTitle), findsOneWidget);
    expect(find.text(l10n.routineEditorScopeOnlyThisWeek), findsOneWidget);
    expect(find.text(l10n.routineEditorScopeAllWeeks), findsOneWidget);
    expect(drainLayoutFailure(tester), isNull);
  });

  testWidgets('panel de la web: se dibuja entero', (tester) async {
    // Este no puede citar el ARB: el editor web tiene su copy hardcodeada por
    // la constraint C-6 (`routine_editor_web_screen.dart` no llama a AppL10n).
    // Se pinta el literal, que es lo que el panel muestra de verdad.
    await _pumpArt(tester, const CustomExerciseOnboardingArt.sidePanel());

    expect(find.text('En superserie'), findsOneWidget);
    expect(find.text('Crear ejercicio nuevo'), findsOneWidget);
    expect(drainLayoutFailure(tester), isNull);
  });
}
