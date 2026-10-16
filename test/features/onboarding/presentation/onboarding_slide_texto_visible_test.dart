// #1462 / #1506: en el carrusel de bienvenida (PF y atleta) el texto de la
// slide se cortaba a mitad de renglón contra el CTA. La slide scrolleaba, pero
// nada lo indicaba: la ilustración ocupaba media pantalla y el cuerpo quedaba
// abajo del borde visible.
//
// Se mide en el SE (375×667) y en el iPhone 17 (402×874). Ojo: en tests
// GoogleFonts mide con la fuente de fallback, que es MÁS ANCHA — el texto sale
// más alto que en el device, así que si entra acá, entra en el teléfono.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/onboarding/presentation/athlete_onboarding_slides.dart';
import 'package:treino/features/onboarding/presentation/onboarding_flow.dart';
import 'package:treino/features/onboarding/presentation/onboarding_slide.dart';
import 'package:treino/features/onboarding/presentation/trainer_onboarding_slides.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../../helpers/layout_failure.dart';

Future<void> _pump(WidgetTester tester, OnboardingSlide slide, Size size,
    {double textScale = 1.0}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: OnboardingFlow(
          slides: [slide],
          onFinish: () {},
          onSkip: () {},
          skipLabel: 'SALTAR',
          nextLabel: 'SIGUIENTE',
          finishLabel: 'EMPEZAR',
          lastStepLabel: 'LISTO',
          stepSemanticsLabel: (a, b) => 'Paso $a de $b',
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  const tamanios = {
    'SE 375×667': Size(375, 667),
    'iPhone 17 402×874': Size(402, 874),
  };
  final decks = {
    'atleta': athleteOnboardingSlides,
    'entrenador': trainerOnboardingSlides,
  };

  for (final MapEntry(key: deck, value: slides) in decks.entries) {
    for (var i = 0; i < slides.length; i++) {
      for (final MapEntry(key: equipo, value: size) in tamanios.entries) {
        testWidgets('$deck, slide ${i + 1}: el texto entra entero ($equipo)',
            (tester) async {
          await _pump(tester, slides[i], size);
          // Overflow horizontal de fuentes de fallback adentro del mock (ej.
          // HomeCtaButton): artefacto del harness. Cualquier otra falla, sí.
          expect(drainLayoutFailure(tester), isNull);
          final visible =
              tester.getRect(find.byKey(const Key('onboarding_page_view')));
          final cuerpo = tester.getRect(find.text(slides[i].body));
          expect(cuerpo.bottom, lessThanOrEqualTo(visible.bottom),
              reason: 'el cuerpo termina en ${cuerpo.bottom} y lo visible en '
                  '${visible.bottom}: queda cortado contra el CTA');
          expect(cuerpo.top, greaterThanOrEqualTo(visible.top));
        });
      }
    }
  }

  // Si ni el texto solo entra (landscape, letra a 1,3×), la ilustración ya se
  // achicó a 0: el texto tiene que SCROLLEAR, no desbordar abajo del CTA.
  const extremos = {
    'landscape 667×375': (Size(667, 375), 1.0),
    'SE con letra a 1,3×': (Size(375, 667), 1.3),
  };
  for (final MapEntry(key: caso, value: (size, escala)) in extremos.entries) {
    testWidgets('el texto no desborda: scrollea ($caso)', (tester) async {
      final slide = athleteOnboardingSlides.first;
      await _pump(tester, slide, size, textScale: escala);
      expect(drainLayoutFailure(tester), isNull);
      final scroll = find.ancestor(
          of: find.text(slide.body),
          matching: find.byType(SingleChildScrollView));
      expect(scroll, findsOneWidget);
      final visible =
          tester.getRect(find.byKey(const Key('onboarding_page_view')));
      expect(tester.getRect(scroll).bottom, lessThanOrEqualTo(visible.bottom));
    });
  }
}
