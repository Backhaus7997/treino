import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/onboarding/presentation/onboarding_flow.dart';
import 'package:treino/features/onboarding/presentation/trainer_onboarding_slides.dart';
import 'package:treino/features/onboarding/presentation/widgets/onboarding_nav_bar.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../../helpers/layout_failure.dart';

Widget _app(List slides, {required bool light}) => ProviderScope(
      child: MaterialApp(
        theme: light ? AppTheme.light() : AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: OnboardingFlow(
          slides: List.from(slides),
          onFinish: () {},
          onSkip: () {},
          skipLabel: 'SALTAR',
          nextLabel: 'SIGUIENTE',
          finishLabel: 'EMPEZAR',
          lastStepLabel: 'LISTO',
          stepSemanticsLabel: (a, b) => 'Paso $a de $b',
        ),
      ),
    );

void main() {
  group('Trainer onboarding', () {
    // Same guard the athlete deck carries, and for the same reason: the bugs
    // that reached a device were an empty preview and a frozen tour, both from
    // layout that only failed once the slide was actually built.
    for (var i = 0; i < trainerOnboardingSlides.length; i++) {
      for (final light in [true, false]) {
        final theme = light ? 'claro' : 'oscuro';
        testWidgets(
          'slide $i (${trainerOnboardingSlides[i].title}) lays out in $theme',
          (tester) async {
            tester.view.physicalSize = const Size(393, 852);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await tester
                .pumpWidget(_app([trainerOnboardingSlides[i]], light: light));
            await tester.pump(const Duration(milliseconds: 500));

            final failure = drainLayoutFailure(tester);
            expect(
              failure,
              isNull,
              reason: 'slide $i falló el layout en $theme:\n$failure',
            );

            // An empty preview still paints its background, so "no exception"
            // is not enough — the nav proves the subtree survived layout.
            expect(find.byType(OnboardingNavBar), findsOneWidget);
            expect(
              tester.getSize(find.byType(OnboardingNavBar)).height,
              greaterThan(0),
            );
          },
        );
      }
    }

    testWidgets('walking the whole deck never breaks layout', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_app(trainerOnboardingSlides, light: false));
      await tester.pump(const Duration(milliseconds: 500));
      expect(drainLayoutFailure(tester), isNull, reason: 'al montar');

      for (var step = 2; step <= trainerOnboardingSlides.length; step++) {
        await tester.tap(find.byKey(const Key('onboarding_primary_cta')));
        await tester.pumpAndSettle();
        expect(
          drainLayoutFailure(tester),
          isNull,
          reason: 'se rompió al llegar a la slide $step',
        );
      }

      // Last slide: SKIP gives way to the LISTO label, CTA reads EMPEZAR.
      expect(find.text('SALTAR'), findsNothing);
      expect(find.text('LISTO'), findsOneWidget);
      expect(find.text('EMPEZAR'), findsOneWidget);
    });

    testWidgets('the pulsing dot settles instead of spinning forever',
        (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Reduced motion must stop the loop. Beyond being the right behaviour,
      // an always-running animation makes `pumpAndSettle` hang forever, so this
      // also keeps the deck testable.
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: _app([trainerOnboardingSlides.first], light: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(drainLayoutFailure(tester), isNull);
    });
  });
}
