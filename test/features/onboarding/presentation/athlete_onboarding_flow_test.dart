import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/onboarding/presentation/onboarding_flow.dart';
import 'package:treino/features/onboarding/presentation/athlete_onboarding_slides.dart';
import 'package:treino/features/onboarding/presentation/widgets/onboarding_nav_bar.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../../helpers/layout_failure.dart';

Future<void> _pumpSlide(
  WidgetTester tester,
  int index, {
  required bool light,
}) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: light ? AppTheme.light() : AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: OnboardingFlow(
          slides: [athleteOnboardingSlides[index]],
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
  // Let the sample-data futures/streams resolve.
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  group('OnboardingFlow', () {
    // The bug this pins down: the previews embed real screens, and those screens
    // build viewports (RutinasSection, HistorialSection, the trainer-link card).
    // A viewport under an unbounded main-axis constraint cannot lay out — it
    // throws "RenderBox was not laid out" and `child!.hasSize is not true`, the
    // preview paints EMPTY, and the per-frame re-throw locks the tour up. Both
    // symptoms were reported from a device before this test existed.
    for (var i = 0; i < athleteOnboardingSlides.length; i++) {
      for (final light in [true, false]) {
        final theme = light ? 'claro' : 'oscuro';
        testWidgets(
          'slide $i (${athleteOnboardingSlides[i].title}) lays out in $theme',
          (tester) async {
            await _pumpSlide(tester, i, light: light);

            final failure = drainLayoutFailure(tester);
            expect(
              failure,
              isNull,
              reason: 'slide $i falló el layout en $theme:\n$failure',
            );

            // Not just "did not throw": the device frame must actually contain
            // a rendered screen. An empty preview still paints its background,
            // so the nav bar is the cheapest proof the subtree survived layout.
            expect(
              find.byType(OnboardingNavBar),
              findsOneWidget,
              reason: 'la preview de la slide $i quedó vacía en $theme',
            );
            final navSize = tester.getSize(find.byType(OnboardingNavBar));
            expect(
              navSize.height,
              greaterThan(0),
              reason: 'el nav de la slide $i no tiene alto en $theme',
            );
          },
        );
      }
    }

    testWidgets('the last slide swaps SALTAR for LISTO and finishes',
        (tester) async {
      var finished = false;
      var skipped = false;

      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            locale: const Locale('es', 'AR'),
            home: OnboardingFlow(
              slides: [athleteOnboardingSlides.last],
              onFinish: () => finished = true,
              onSkip: () => skipped = true,
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

      // On the last slide the SKIP slot swaps to a label: there is nothing
      // left to skip, and leaving the slot empty put a visible hole next to a
      // full progress bar.
      expect(find.text('SALTAR'), findsNothing);
      expect(find.text('LISTO'), findsOneWidget);
      expect(find.text('EMPEZAR'), findsOneWidget);

      await tester.tap(find.byKey(const Key('onboarding_primary_cta')));
      await tester.pump();

      expect(finished, isTrue);
      expect(skipped, isFalse);
    });
  });
}
