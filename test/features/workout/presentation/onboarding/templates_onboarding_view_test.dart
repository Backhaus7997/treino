import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/onboarding/presentation/onboarding_chrome.dart';
import 'package:treino/features/workout/domain/routine_goal.dart';
import 'package:treino/features/workout/domain/template_preferences.dart';
import 'package:treino/features/workout/presentation/onboarding/templates_onboarding_steps.dart';
import 'package:treino/features/workout/presentation/onboarding/templates_onboarding_view.dart';
import 'package:treino/l10n/app_l10n.dart';

/// What the view last handed to `onFinish`. Reset by every [_pumpView].
TemplatePreferences? _finished;

/// Hosts the view with the real ES-AR copy and no provider overrides — the
/// no-Riverpod contract the view is built to keep.
Future<void> _pumpView(
  WidgetTester tester, {
  VoidCallback? onSkip,
  ThemeData? theme,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  _finished = null;

  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            final l10n = AppL10n.of(context);
            return SingleChildScrollView(
              child: TemplatesOnboardingView(
                steps: templatesOnboardingSteps(l10n),
                onFinish: (p) => _finished = p,
                onSkip: onSkip ?? () {},
                skipLabel: l10n.onboardingTourSkip,
                nextLabel: l10n.onboardingTourNext,
                finishLabel: l10n.templatesOnboardingCta,
                backLabel: l10n.templatesOnboardingBack,
                stepSemanticsLabel: (c, t) => l10n.onboardingTourProgress(c, t),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Key key) async {
  // Steps differ in height; on the shorter viewport the CTA can sit below the
  // fold. Scroll it in first — `tap` refuses to hit an off-screen target.
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

/// Advances to step [target] (1-based) without answering anything.
Future<void> _advanceTo(WidgetTester tester, int target) async {
  for (var i = 1; i < target; i++) {
    await _tap(tester, templatesOnboardingCtaKey);
  }
}

void main() {
  group('TemplatesOnboardingView — paso 1: días', () {
    testWidgets('renders kicker, title, body, card label and hint',
        (tester) async {
      await _pumpView(tester);

      expect(find.text('Paso 1 de 4'.toUpperCase()), findsOneWidget);
      expect(find.text('¿CUÁNTOS DÍAS PODÉS ENTRENAR?'), findsOneWidget);
      expect(
        find.textContaining('Elegí lo que vas a sostener'),
        findsOneWidget,
      );
      expect(find.text('Días por semana'), findsOneWidget);
      expect(
        find.textContaining('Ninguna respuesta filtra el catálogo'),
        findsOneWidget,
      );
    });

    testWidgets('offers 2 through 6', (tester) async {
      await _pumpView(tester);

      for (var d = 2; d <= 6; d++) {
        expect(
          find.byKey(templatesOnboardingOptionKey('days', '$d')),
          findsOneWidget,
          reason: '$d días',
        );
      }
    });

    testWidgets('the chosen pill spells the unit out, the rest do not',
        (tester) async {
      await _pumpView(tester);

      // Unselected: bare numbers, no unit anywhere.
      expect(find.text('3 DÍAS'), findsNothing);
      expect(find.text('3'), findsOneWidget);

      await _tap(tester, templatesOnboardingOptionKey('days', '3'));

      expect(find.text('3 DÍAS'), findsOneWidget);
    });
  });

  group('TemplatesOnboardingView — paso 2: minutos', () {
    testWidgets('renders the four durations with their sub-labels',
        (tester) async {
      await _pumpView(tester);
      await _advanceTo(tester, 2);

      expect(find.text('¿CUÁNTO DURA TU SESIÓN?'), findsOneWidget);
      expect(find.text('Minutos por sesión'), findsOneWidget);

      expect(find.text('30 MIN'), findsOneWidget);
      expect(find.text('Entro y salgo'), findsOneWidget);
      expect(find.text('45 MIN'), findsOneWidget);
      expect(find.text('Lo de siempre'), findsOneWidget);
      expect(find.text('60 MIN'), findsOneWidget);
      expect(find.text('Hora completa'), findsOneWidget);
      expect(find.text('75 MIN O MÁS'), findsOneWidget);
      expect(find.text('Fuerza'), findsOneWidget);
    });
  });

  group('TemplatesOnboardingView — paso 3: objetivo', () {
    testWidgets('renders the five goals', (tester) async {
      await _pumpView(tester);
      await _advanceTo(tester, 3);

      expect(find.text('¿PARA QUÉ QUERÉS ENTRENAR?'), findsOneWidget);
      expect(find.text('Objetivo'), findsOneWidget);

      for (final goal in RoutineGoal.values) {
        expect(
          find.byKey(templatesOnboardingOptionKey('goal', goal.wireKey)),
          findsOneWidget,
          reason: goal.wireKey,
        );
      }
      expect(find.text('SALUD'), findsOneWidget);
      expect(find.text('PREVENCIÓN'), findsOneWidget);
      expect(find.text('ESTÉTICA'), findsOneWidget);
      expect(find.text('DEPORTE'), findsOneWidget);
      expect(find.text('BIENESTAR'), findsOneWidget);
    });

    testWidgets('is single-choice: a second pick replaces the first',
        (tester) async {
      await _pumpView(tester);
      await _advanceTo(tester, 3);

      await _tap(tester, templatesOnboardingOptionKey('goal', 'health'));
      await _tap(tester, templatesOnboardingOptionKey('goal', 'sport'));
      await _tap(tester, templatesOnboardingCtaKey);

      final result = await _finishFrom(tester);
      expect(result?.goal, RoutineGoal.sport);
    });

    testWidgets('tapping the chosen pill again clears it', (tester) async {
      await _pumpView(tester);
      await _advanceTo(tester, 3);

      await _tap(tester, templatesOnboardingOptionKey('goal', 'health'));
      await _tap(tester, templatesOnboardingOptionKey('goal', 'health'));
      await _tap(tester, templatesOnboardingCtaKey);

      final result = await _finishFrom(tester);
      expect(result?.goal, isNull);
    });
  });

  group('TemplatesOnboardingView — paso 4: zonas', () {
    testWidgets('renders the six zones and marks the step optional',
        (tester) async {
      await _pumpView(tester);
      await _advanceTo(tester, 4);

      expect(find.text('ESTO NO ES UN EXAMEN'), findsOneWidget);
      expect(find.text('Zonas a priorizar · opcional'), findsOneWidget);

      for (final label in const [
        'ESPALDA',
        'PECHO',
        'HOMBROS',
        'GLÚTEOS',
        'CUÁDRICEPS',
        'CORE',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('is multi-select: picks accumulate instead of replacing',
        (tester) async {
      await _pumpView(tester);
      await _advanceTo(tester, 4);

      await _tap(tester, templatesOnboardingOptionKey('zones', 'back'));
      await _tap(tester, templatesOnboardingOptionKey('zones', 'chest'));
      await _tap(tester, templatesOnboardingOptionKey('zones', 'core'));

      final result = await _finishFrom(tester);
      expect(
        result?.priorityMuscleGroups.toSet(),
        {'back', 'chest', 'core'},
      );
    });

    testWidgets('the CTA reads VER MIS PLANTILLAS on the last step',
        (tester) async {
      await _pumpView(tester);
      await _advanceTo(tester, 4);

      expect(find.text('VER MIS PLANTILLAS'), findsOneWidget);
      expect(find.text('SIGUIENTE'), findsNothing);
    });
  });

  group('TemplatesOnboardingView — salidas', () {
    testWidgets('SALTAR fires onSkip without producing preferences',
        (tester) async {
      var skipped = false;
      await _pumpView(tester, onSkip: () => skipped = true);

      await _tap(tester, templatesOnboardingOptionKey('days', '4'));
      await _tap(tester, templatesOnboardingSkipKey);

      expect(skipped, isTrue);
    });

    testWidgets('an untouched run finishes with empty preferences',
        (tester) async {
      await _pumpView(tester);
      await _advanceTo(tester, 4);

      final result = await _finishFrom(tester);
      expect(result, isNotNull);
      expect(result!.isEmpty, isTrue,
          reason: 'nothing answered must stay neutral, not default');
    });

    testWidgets('collects all four dimensions in one run', (tester) async {
      await _pumpView(tester);

      await _tap(tester, templatesOnboardingOptionKey('days', '5'));
      await _tap(tester, templatesOnboardingCtaKey);
      await _tap(tester, templatesOnboardingOptionKey('minutes', '75'));
      await _tap(tester, templatesOnboardingCtaKey);
      await _tap(tester, templatesOnboardingOptionKey('goal', 'aesthetics'));
      await _tap(tester, templatesOnboardingCtaKey);
      await _tap(tester, templatesOnboardingOptionKey('zones', 'glutes'));

      final result = await _finishFrom(tester);
      expect(result?.daysPerWeek, 5);
      expect(result?.minutesPerSession, 75);
      expect(result?.goal, RoutineGoal.aesthetics);
      expect(result?.priorityMuscleGroups, ['glutes']);
      expect(result?.isEmpty, isFalse);
    });
  });

  group('TemplatesOnboardingView — VOLVER', () {
    testWidgets('is absent on step 1', (tester) async {
      await _pumpView(tester);
      expect(find.byKey(templatesOnboardingBackKey), findsNothing);
    });

    testWidgets('appears from step 2 onward', (tester) async {
      await _pumpView(tester);
      await _advanceTo(tester, 2);
      expect(find.byKey(templatesOnboardingBackKey), findsOneWidget);
      expect(find.text('VOLVER'), findsOneWidget);
    });

    testWidgets('steps back one question at a time', (tester) async {
      await _pumpView(tester);
      await _advanceTo(tester, 3);
      expect(find.text('¿PARA QUÉ QUERÉS ENTRENAR?'), findsOneWidget);

      await _tap(tester, templatesOnboardingBackKey);
      expect(find.text('¿CUÁNTO DURA TU SESIÓN?'), findsOneWidget);

      await _tap(tester, templatesOnboardingBackKey);
      expect(find.text('¿CUÁNTOS DÍAS PODÉS ENTRENAR?'), findsOneWidget);
      expect(find.byKey(templatesOnboardingBackKey), findsNothing);
    });

    testWidgets('keeps every answer across back and forward', (tester) async {
      // A back button that discarded what you already picked would be worse
      // than not having one.
      await _pumpView(tester);

      await _tap(tester, templatesOnboardingOptionKey('days', '4'));
      await _tap(tester, templatesOnboardingCtaKey);
      await _tap(tester, templatesOnboardingOptionKey('minutes', '60'));

      // Back to step 1 and forward again.
      await _tap(tester, templatesOnboardingBackKey);
      expect(find.text('4 DÍAS'), findsOneWidget,
          reason: 'the day pill is still the chosen one');
      await _tap(tester, templatesOnboardingCtaKey);
      await _tap(tester, templatesOnboardingCtaKey);
      await _tap(tester, templatesOnboardingCtaKey);

      final result = await _finishFrom(tester);
      expect(result?.daysPerWeek, 4);
      expect(result?.minutesPerSession, 60);
    });

    testWidgets('lets a previous answer be corrected', (tester) async {
      await _pumpView(tester);

      await _tap(tester, templatesOnboardingOptionKey('days', '2'));
      await _tap(tester, templatesOnboardingCtaKey);
      await _tap(tester, templatesOnboardingBackKey);
      await _tap(tester, templatesOnboardingOptionKey('days', '5'));

      await _advanceTo(tester, 4);
      final result = await _finishFrom(tester);
      expect(result?.daysPerWeek, 5);
    });
  });

  group('TemplatesOnboardingView — deslizar', () {
    /// A horizontal fling across the sheet body. Negative dx = swipe left.
    Future<void> fling(WidgetTester tester, double dx) async {
      await tester.fling(
        find.byType(OnboardingDots),
        Offset(dx, 0),
        800,
      );
      await tester.pumpAndSettle();
    }

    /// A SLOW drag — distance without a fling's velocity, which is the gesture
    /// a velocity-only implementation ignored. `tester.drag` handles the touch
    /// slop and reports no meaningful velocity, so only the distance rule can
    /// commit it.
    Future<void> slowDrag(WidgetTester tester, double dx) async {
      await tester.drag(find.byType(OnboardingDots), Offset(dx, 0));
      await tester.pumpAndSettle();
    }

    testWidgets('a SLOW drag left advances one step', (tester) async {
      await _pumpView(tester);
      expect(find.text('¿CUÁNTOS DÍAS PODÉS ENTRENAR?'), findsOneWidget);

      await slowDrag(tester, -200);
      expect(find.text('¿CUÁNTO DURA TU SESIÓN?'), findsOneWidget);
    });

    testWidgets('a SLOW drag right goes back one step', (tester) async {
      await _pumpView(tester);
      await _advanceTo(tester, 2);

      await slowDrag(tester, 200);
      expect(find.text('¿CUÁNTOS DÍAS PODÉS ENTRENAR?'), findsOneWidget);
    });

    testWidgets('a short drag under the threshold does NOT change step',
        (tester) async {
      await _pumpView(tester);

      await slowDrag(tester, -40);
      expect(find.text('¿CUÁNTOS DÍAS PODÉS ENTRENAR?'), findsOneWidget);
    });

    testWidgets('a fling left advances one step', (tester) async {
      await _pumpView(tester);
      expect(find.text('¿CUÁNTOS DÍAS PODÉS ENTRENAR?'), findsOneWidget);

      await fling(tester, -300);
      expect(find.text('¿CUÁNTO DURA TU SESIÓN?'), findsOneWidget);
    });

    testWidgets('a fling right goes back one step', (tester) async {
      await _pumpView(tester);
      await _advanceTo(tester, 3);

      await fling(tester, 300);
      expect(find.text('¿CUÁNTO DURA TU SESIÓN?'), findsOneWidget);
    });

    testWidgets('a fling right on step 1 does nothing', (tester) async {
      await _pumpView(tester);

      await fling(tester, 300);
      expect(find.text('¿CUÁNTOS DÍAS PODÉS ENTRENAR?'), findsOneWidget);
    });

    testWidgets('a fling left on the LAST step does NOT finish',
        (tester) async {
      // A gesture navigates; it must never be what commits four answers to the
      // user's document. Only the CTA does that.
      await _pumpView(tester);
      await _advanceTo(tester, 4);

      await fling(tester, -300);

      expect(find.text('ESTO NO ES UN EXAMEN'), findsOneWidget);
      expect(_finished, isNull, reason: 'a swipe must not persist anything');
    });

    testWidgets('swiping keeps the answers already chosen', (tester) async {
      await _pumpView(tester);
      await _tap(tester, templatesOnboardingOptionKey('days', '6'));

      await fling(tester, -300);
      await fling(tester, 300);

      expect(find.text('6 DÍAS'), findsOneWidget);
    });
  });

  group('TemplatesOnboardingView — transición entre pasos', () {
    testWidgets('nunca hay dos pasos en pantalla a la vez', (tester) async {
      // Regresión: con un cross-fade los dos pasos compartían el frame y el
      // Stack tomaba la altura del MÁS ALTO, así que volver de las cuatro filas
      // de duración a las pills de días dejaba las filas viejas fantasmeando
      // sobre un hueco alto. La transición es fade-THROUGH: sale, cambia, entra.
      await _pumpView(tester);
      expect(find.text('¿CUÁNTOS DÍAS PODÉS ENTRENAR?'), findsOneWidget);

      await tester.tap(find.byKey(templatesOnboardingCtaKey));
      // A mitad del fade-out el paso entrante todavía no debe existir.
      await tester.pump(const Duration(milliseconds: 90));
      expect(
        find.text('¿CUÁNTO DURA TU SESIÓN?'),
        findsNothing,
        reason: 'el paso entrante no comparte frame con el saliente',
      );

      await tester.pumpAndSettle();
      expect(find.text('¿CUÁNTO DURA TU SESIÓN?'), findsOneWidget);
      expect(find.text('¿CUÁNTOS DÍAS PODÉS ENTRENAR?'), findsNothing);
    });

    testWidgets('volver del paso 2 al 1 tampoco los superpone', (tester) async {
      // El sentido en el que apareció el defecto: de alto a bajo.
      await _pumpView(tester);
      await _advanceTo(tester, 2);

      await tester.tap(find.byKey(templatesOnboardingBackKey));
      await tester.pump(const Duration(milliseconds: 90));
      expect(find.text('¿CUÁNTOS DÍAS PODÉS ENTRENAR?'), findsNothing);

      await tester.pumpAndSettle();
      expect(find.text('¿CUÁNTOS DÍAS PODÉS ENTRENAR?'), findsOneWidget);
      expect(find.text('¿CUÁNTO DURA TU SESIÓN?'), findsNothing);
    });
  });

  group('TemplatesOnboardingView — temas', () {
    testWidgets('renders in light as well as dark', (tester) async {
      await _pumpView(tester, theme: AppTheme.light());
      expect(find.text('¿CUÁNTOS DÍAS PODÉS ENTRENAR?'), findsOneWidget);

      await _pumpView(tester, theme: AppTheme.dark());
      expect(find.text('¿CUÁNTOS DÍAS PODÉS ENTRENAR?'), findsOneWidget);
    });
  });
}

/// Taps the final CTA and returns what `onFinish` produced.
///
/// Driven through the real button rather than by calling the callback directly:
/// the state machine, not the test, decides the payload.
Future<TemplatePreferences?> _finishFrom(WidgetTester tester) async {
  await _tap(tester, templatesOnboardingCtaKey);
  return _finished;
}
