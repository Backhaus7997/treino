import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/onboarding/presentation/onboarding_card_content.dart';
import 'package:treino/features/onboarding/presentation/onboarding_illustration.dart';
import 'package:treino/features/onboarding/presentation/onboarding_tour_view.dart';

import '../../../helpers/test_app_wrapper.dart';

const _slides = [
  OnboardingCardContent(
    icon: TreinoIcon.tabHome,
    illustration: OnboardingIllustration.athleteHome(),
    title: 'PRIMERA',
    body: 'Cuerpo de la primera slide.',
  ),
  OnboardingCardContent(
    icon: TreinoIcon.tabWorkout,
    illustration: OnboardingIllustration.athleteWorkout(),
    title: 'SEGUNDA',
    body: 'Cuerpo de la segunda slide.',
    bullets: ['Una viñeta', 'Otra viñeta'],
  ),
  OnboardingCardContent(
    icon: TreinoIcon.tabCoach,
    illustration: OnboardingIllustration.athleteCoach(),
    title: 'TERCERA',
    body: 'Cuerpo de la tercera slide.',
  ),
];

/// Presentational-only harness: no ProviderScope, no overrides, no Firestore.
/// If this ever needs one, the view has grown a dependency it should not have.
Future<void> _pump(
  WidgetTester tester, {
  required VoidCallback onFinish,
  required VoidCallback onSkip,
  List<OnboardingCardContent> slides = _slides,
}) {
  return tester.pumpWidget(
    TestAppWrapper(
      child: OnboardingTourView(
        slides: slides,
        onFinish: onFinish,
        onSkip: onSkip,
        skipLabel: 'SALTAR',
        nextLabel: 'SIGUIENTE',
        finishLabel: 'COMENZAR',
        stepSemanticsLabel: (c, t) => 'Paso $c de $t',
      ),
    ),
  );
}

void main() {
  group('OnboardingTourView', () {
    testWidgets('renders the first slide only', (tester) async {
      await _pump(tester, onFinish: () {}, onSkip: () {});

      expect(find.text('PRIMERA'), findsOneWidget);
      expect(find.text('TERCERA'), findsNothing);
    });

    testWidgets('renders one progress bar per slide', (tester) async {
      await _pump(tester, onFinish: () {}, onSkip: () {});
      expect(find.byType(AnimatedContainer), findsNWidgets(_slides.length));
    });

    testWidgets('adapts the bar count to the slide count', (tester) async {
      // Guards the parameterisation: mobile runs 5 slides, web runs 8, and
      // ProfileSetupHeader (the visual source) hardcodes 4.
      await _pump(
        tester,
        onFinish: () {},
        onSkip: () {},
        slides: _slides.take(2).toList(),
      );
      expect(find.byType(AnimatedContainer), findsNWidgets(2));
    });

    testWidgets('SWIPE advances to the next slide', (tester) async {
      // The functional difference against ProfileSetupFlow, which disables
      // scroll physics.
      await _pump(tester, onFinish: () {}, onSkip: () {});

      await tester.drag(
        find.byKey(const Key('onboarding_page_view')),
        const Offset(-400, 0),
      );
      await tester.pumpAndSettle();

      expect(find.text('SEGUNDA'), findsOneWidget);
      expect(find.text('Una viñeta'), findsOneWidget);
    });

    testWidgets('the CTA advances while slides remain', (tester) async {
      await _pump(tester, onFinish: () {}, onSkip: () {});

      expect(find.text('SIGUIENTE'), findsOneWidget);
      await tester.tap(find.byKey(const Key('onboarding_primary_cta')));
      await tester.pumpAndSettle();

      expect(find.text('SEGUNDA'), findsOneWidget);
    });

    testWidgets('the CTA becomes COMENZAR on the last slide', (tester) async {
      var finished = 0;
      await _pump(tester, onFinish: () => finished++, onSkip: () {});

      for (var i = 0; i < _slides.length - 1; i++) {
        await tester.tap(find.byKey(const Key('onboarding_primary_cta')));
        await tester.pumpAndSettle();
      }

      expect(find.text('COMENZAR'), findsOneWidget);
      expect(find.text('SIGUIENTE'), findsNothing);
      expect(finished, 0, reason: 'not fired until the CTA is actually tapped');

      await tester.tap(find.byKey(const Key('onboarding_primary_cta')));
      await tester.pumpAndSettle();
      expect(finished, 1);
    });

    testWidgets('SKIP is available on the FIRST slide and fires once',
        (tester) async {
      // A tour nobody can leave is a toll, not a welcome.
      var skipped = 0;
      await _pump(tester, onFinish: () {}, onSkip: () => skipped++);

      expect(find.text('PRIMERA'), findsOneWidget);
      await tester.tap(find.byKey(const Key('onboarding_skip_button')));
      await tester.pumpAndSettle();

      expect(skipped, 1);
    });

    testWidgets('SKIP meets the 44pt minimum touch target', (tester) async {
      await _pump(tester, onFinish: () {}, onSkip: () {});

      final size =
          tester.getSize(find.byKey(const Key('onboarding_skip_button')));
      expect(size.height, greaterThanOrEqualTo(44));
      expect(size.width, greaterThanOrEqualTo(44));
    });

    testWidgets('a single-slide tour finishes immediately', (tester) async {
      var finished = 0;
      await _pump(
        tester,
        onFinish: () => finished++,
        onSkip: () {},
        slides: _slides.take(1).toList(),
      );

      expect(find.text('COMENZAR'), findsOneWidget);
      await tester.tap(find.byKey(const Key('onboarding_primary_cta')));
      expect(finished, 1);
    });

    testWidgets('does not overflow on a 320x568 screen at 2x text scale',
        (tester) async {
      // Fixed header + fixed footer + Expanded body is exactly what overflowed
      // in profile_setup (audit F4).
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: TestAppWrapper(
            child: OnboardingTourView(
              slides: const [
                OnboardingCardContent(
                  icon: TreinoIcon.tabCoach,
                  illustration: OnboardingIllustration.trainerCoach(),
                  title: 'UN TÍTULO LARGO QUE FUERZA EL WRAP',
                  body: 'Un cuerpo largo que ocupa varias líneas para empujar '
                      'el layout y verificar que scrollea en vez de romper el '
                      'render con un overflow de RenderFlex.',
                  bullets: [
                    'Una viñeta también larga que envuelve en varias líneas',
                    'Otra viñeta igual de larga para sumar altura al layout',
                  ],
                ),
              ],
              onFinish: () {},
              onSkip: () {},
              skipLabel: 'SALTAR',
              nextLabel: 'SIGUIENTE',
              finishLabel: 'COMENZAR',
              stepSemanticsLabel: (c, t) => 'Paso $c de $t',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
