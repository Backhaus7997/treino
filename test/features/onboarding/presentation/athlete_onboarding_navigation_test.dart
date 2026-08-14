import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/onboarding/presentation/onboarding_flow.dart';
import 'package:treino/features/onboarding/presentation/athlete_onboarding_slides.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../../helpers/layout_failure.dart';

/// Walks the WHOLE deck the way a user does.
///
/// The per-slide test pumps one slide in isolation; this one runs the real
/// PageView with all five, because that is the shape that crashed on device —
/// adjacent pages stay alive during the transition, so slide 3 builds while
/// slide 2 is still mounted.
void main() {
  testWidgets('tapping SIGUIENTE through all 5 slides never breaks layout',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var finished = false;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
          home: OnboardingFlow(
            slides: athleteOnboardingSlides,
            onFinish: () => finished = true,
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
    expect(drainLayoutFailure(tester), isNull, reason: 'slide 1 al montar');

    for (var step = 2; step <= athleteOnboardingSlides.length; step++) {
      await tester.tap(find.byKey(const Key('onboarding_primary_cta')));
      await tester.pumpAndSettle();
      expect(
        drainLayoutFailure(tester),
        isNull,
        reason: 'se rompió al llegar a la slide $step',
      );
    }

    expect(find.text('EMPEZAR'), findsOneWidget);
    await tester.tap(find.byKey(const Key('onboarding_primary_cta')));
    await tester.pump();
    expect(finished, isTrue);
  });
}
