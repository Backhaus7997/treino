import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/onboarding/presentation/custom_exercise_onboarding_slides.dart';
import 'package:treino/features/onboarding/presentation/onboarding_card_content.dart';
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
  List<OnboardingCardContent> slides = athleteCustomExerciseSlides,
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
          slides: slides,
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
    testWidgets('camina TODAS las slides del deck, sean las que sean',
        (tester) async {
      await _pump(tester, onFinish: () {}, onSkip: () {});

      // Derivado del deck, no hardcodeado: este test se rompió cuando el deck
      // pasó de 6 a 9 slides, y lo único que probaba de más era el número 6.
      final total = athleteCustomExerciseSlides.length;
      final pager = tester.widget<PageView>(find.byKey(_pagerKey));
      expect(pager.childrenDelegate.estimatedChildCount, total);

      for (var i = 0; i < total; i++) {
        expect(
          find.text(athleteCustomExerciseSlides[i].title),
          findsOneWidget,
          reason: 'slide ${i + 1} de $total',
        );
        expect(find.text('PASO ${i + 1} DE $total'), findsOneWidget);
        if (i < total - 1) await _next(tester);
      }
      expect(drainLayoutFailure(tester), isNull);
    });

    testWidgets(
        'CTA reads SIGUIENTE until the last slide, then the finish copy',
        (tester) async {
      await _pump(tester, onFinish: () {}, onSkip: () {});

      for (var i = 0; i < athleteCustomExerciseSlides.length - 1; i++) {
        expect(find.text('SIGUIENTE'), findsOneWidget, reason: 'slide $i');
        expect(find.text('CREAR MI EJERCICIO'), findsNothing);
        await _next(tester);
      }

      expect(find.text('SIGUIENTE'), findsNothing);
      expect(find.text('CREAR MI EJERCICIO'), findsOneWidget);
    });

    testWidgets('the CTA on the last slide finishes instead of advancing',
        (tester) async {
      var finished = 0;
      await _pump(tester, onFinish: () => finished++, onSkip: () {});

      for (var i = 0; i < athleteCustomExerciseSlides.length - 1; i++) {
        await _next(tester);
      }
      expect(finished, 0, reason: 'must not fire while advancing');

      await tester.tap(find.byKey(_ctaKey));
      await tester.pumpAndSettle();
      expect(finished, 1);
    });

    testWidgets('SALTAR is offered on every slide but the last',
        (tester) async {
      var skipped = 0;
      await _pump(tester, onFinish: () {}, onSkip: () => skipped++);

      for (var i = 0; i < athleteCustomExerciseSlides.length - 1; i++) {
        expect(find.byKey(_skipKey), findsOneWidget, reason: 'slide $i');
        await _next(tester);
      }

      expect(
        find.byKey(_skipKey),
        findsNothing,
        reason: 'the last slide CTA already ends the flow',
      );
      expect(skipped, 0);
    });

    // Un test POR DECK, no un loop adentro de uno: el `PageView` conserva su
    // página entre `pumpWidget`s —mismo tipo de widget, mismo elemento— así
    // que el segundo deck arrancaba donde había quedado el primero.
    for (final deck in {
      'alumno': athleteCustomExerciseSlides,
      'entrenador': trainerCustomExerciseSlides,
      'coach hub': trainerWebCustomExerciseSlides,
    }.entries) {
      testWidgets('cada slide del deck «${deck.key}» se dibuja sin desbordar',
          (tester) async {
        // Las ilustraciones son widgets con medidas fijas dentro de un
        // `FittedBox`. El canvas de 320x236 es el único guard, y un cuerpo
        // nuevo que se pase de largo no lo agarra ningún otro test: el
        // walkthrough camina SÓLO el deck del alumno, y las de la web no las
        // miraba nadie.
        await _pump(
          tester,
          onFinish: () {},
          onSkip: () {},
          slides: deck.value,
        );

        for (var i = 0; i < deck.value.length; i++) {
          expect(
            find.text(deck.value[i].title),
            findsOneWidget,
            reason: 'slide ${i + 1} de ${deck.value.length}',
          );
          expect(
            drainLayoutFailure(tester),
            isNull,
            reason: '«${deck.value[i].title}» desborda',
          );
          if (i < deck.value.length - 1) await _next(tester);
        }
      });
    }

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

      final total = athleteCustomExerciseSlides.length;
      expect(find.bySemanticsLabel('Paso 1 de $total'), findsOneWidget);

      await _next(tester);
      expect(find.bySemanticsLabel('Paso 2 de $total'), findsOneWidget);
      expect(find.bySemanticsLabel('Paso 1 de $total'), findsNothing);
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
      expect(trainerCustomExerciseSlides, hasLength(9));
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
