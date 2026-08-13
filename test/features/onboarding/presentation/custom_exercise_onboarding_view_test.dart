import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/onboarding/presentation/custom_exercise_onboarding_slides.dart';
import 'package:treino/features/onboarding/presentation/custom_exercise_onboarding_view.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../../helpers/layout_failure.dart';

const _skipKey = Key('custom_exercise_onboarding_skip_button');
const _ctaKey = Key('custom_exercise_onboarding_primary_cta');
const _pagerKey = Key('custom_exercise_onboarding_page_view');

/// Labels are passed in by the caller in production (from `AppL10n`); the view
/// itself is copy-agnostic, so the tests pin literals and stay readable.
Future<void> _pump(
  WidgetTester tester, {
  required VoidCallback onFinish,
  required VoidCallback onSkip,
  CustomExerciseOnboardingLayout layout = CustomExerciseOnboardingLayout.sheet,
  ThemeData? theme,
  Size size = const Size(390, 844),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(
        body: CustomExerciseOnboardingView(
          slides: athleteCustomExerciseSlides,
          layout: layout,
          onFinish: onFinish,
          onSkip: onSkip,
          skipLabel: 'SALTAR',
          nextLabel: 'SIGUIENTE',
          finishLabel: 'CREAR MI EJERCICIO',
          stepSemanticsLabel: (c, t) => 'Paso $c de $t',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Advances the pager by tapping the primary CTA and letting it animate.
Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.byKey(_ctaKey));
  await tester.pumpAndSettle();
}

void main() {
  group('CustomExerciseOnboardingView', () {
    testWidgets('shows three slides and walks through all of them',
        (tester) async {
      await _pump(tester, onFinish: () {}, onSkip: () {});

      // The deck itself is the source of truth for "three".
      expect(athleteCustomExerciseSlides, hasLength(3));

      final pager = tester.widget<PageView>(find.byKey(_pagerKey));
      expect(pager.childrenDelegate.estimatedChildCount, 3);

      expect(find.text('¿FALTA UN EJERCICIO? CREÁLO VOS'), findsOneWidget);
      expect(find.text('PASO 1 DE 3'), findsOneWidget);

      await _next(tester);
      expect(find.text('SUMALE UN VIDEO'), findsOneWidget);
      expect(find.text('PASO 2 DE 3'), findsOneWidget);

      await _next(tester);
      expect(find.text('USALO EN CUALQUIER RUTINA'), findsOneWidget);
      expect(find.text('PASO 3 DE 3'), findsOneWidget);
    });

    testWidgets(
        'CTA reads SIGUIENTE until the last slide, then the finish copy',
        (tester) async {
      await _pump(tester, onFinish: () {}, onSkip: () {});

      expect(find.text('SIGUIENTE'), findsOneWidget);
      expect(find.text('CREAR MI EJERCICIO'), findsNothing);

      await _next(tester);
      expect(find.text('SIGUIENTE'), findsOneWidget);

      await _next(tester);
      expect(find.text('SIGUIENTE'), findsNothing);
      expect(find.text('CREAR MI EJERCICIO'), findsOneWidget);
    });

    testWidgets('the CTA on the last slide finishes instead of advancing',
        (tester) async {
      var finished = 0;
      await _pump(tester, onFinish: () => finished++, onSkip: () {});

      await _next(tester);
      await _next(tester);
      expect(finished, 0, reason: 'must not fire while advancing');

      await tester.tap(find.byKey(_ctaKey));
      await tester.pumpAndSettle();
      expect(finished, 1);
    });

    testWidgets('SALTAR is offered on every slide but the last',
        (tester) async {
      var skipped = 0;
      await _pump(tester, onFinish: () {}, onSkip: () => skipped++);

      expect(find.byKey(_skipKey), findsOneWidget);
      await _next(tester);
      expect(find.byKey(_skipKey), findsOneWidget);

      await _next(tester);
      expect(
        find.byKey(_skipKey),
        findsNothing,
        reason: 'the last slide CTA already ends the flow',
      );
      expect(skipped, 0);
    });

    testWidgets('SALTAR calls back from the first slide', (tester) async {
      var skipped = 0;
      await _pump(tester, onFinish: () {}, onSkip: () => skipped++);

      await tester.tap(find.byKey(_skipKey));
      await tester.pumpAndSettle();

      expect(skipped, 1);
    });

    testWidgets('SALTAR keeps a 44pt touch target (#619)', (tester) async {
      await _pump(tester, onFinish: () {}, onSkip: () {});

      final size = tester.getSize(find.byKey(_skipKey));
      expect(size.height, greaterThanOrEqualTo(44));
      expect(size.width, greaterThanOrEqualTo(44));
    });

    testWidgets('the dots announce the step and hide their own semantics',
        (tester) async {
      await _pump(tester, onFinish: () {}, onSkip: () {});

      expect(find.bySemanticsLabel('Paso 1 de 3'), findsOneWidget);

      await _next(tester);
      expect(find.bySemanticsLabel('Paso 2 de 3'), findsOneWidget);
      expect(find.bySemanticsLabel('Paso 1 de 3'), findsNothing);
    });

    testWidgets('survives a 320x568 screen at 2x text scale', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: CustomExerciseOnboardingView(
                slides: athleteCustomExerciseSlides,
                onFinish: () {},
                onSkip: () {},
                skipLabel: 'SALTAR',
                nextLabel: 'SIGUIENTE',
                finishLabel: 'CREAR MI EJERCICIO',
                stepSemanticsLabel: (c, t) => 'Paso $c de $t',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(drainLayoutFailure(tester), isNull);
      // The CTA must still be reachable, not pushed off the sheet.
      expect(find.byKey(_ctaKey), findsOneWidget);
    });

    testWidgets('renders in the light theme without overflowing',
        (tester) async {
      await _pump(
        tester,
        onFinish: () {},
        onSkip: () {},
        theme: AppTheme.light(),
      );

      expect(drainLayoutFailure(tester), isNull);
      expect(find.text('¿FALTA UN EJERCICIO? CREÁLO VOS'), findsOneWidget);
    });

    testWidgets('the dialog layout lays the art beside the copy',
        (tester) async {
      await _pump(
        tester,
        onFinish: () {},
        onSkip: () {},
        layout: CustomExerciseOnboardingLayout.dialog,
        size: const Size(1280, 800),
      );

      expect(drainLayoutFailure(tester), isNull);
      expect(find.text('¿FALTA UN EJERCICIO? CREÁLO VOS'), findsOneWidget);
      expect(find.byKey(_ctaKey), findsOneWidget);
    });

    testWidgets('the trainer deck differs from the athlete one on slide 3',
        (tester) async {
      expect(trainerCustomExerciseSlides, hasLength(3));
      expect(
        trainerCustomExerciseSlides[2].title,
        'ASIGNALO A TUS ALUMNOS',
        reason: 'the assign-to-students framing is the point of the split',
      );
      expect(
        athleteCustomExerciseSlides[2].title,
        'USALO EN CUALQUIER RUTINA',
      );
    });
  });
}
