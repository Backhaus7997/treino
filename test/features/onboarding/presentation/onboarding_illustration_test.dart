import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/onboarding/presentation/onboarding_illustration.dart';

/// Every illustration the tour can show, named so a failure says which one.
const _all = <String, Widget>{
  'athleteHome': OnboardingIllustration.athleteHome(),
  'athleteWorkout': OnboardingIllustration.athleteWorkout(),
  'athleteFeed': OnboardingIllustration.athleteFeed(),
  'athleteCoach': OnboardingIllustration.athleteCoach(),
  'athleteProfile': OnboardingIllustration.athleteProfile(),
  'trainerHome': OnboardingIllustration.trainerHome(),
  'trainerWorkout': OnboardingIllustration.trainerWorkout(),
  'trainerFeed': OnboardingIllustration.trainerFeed(),
  'trainerCoach': OnboardingIllustration.trainerCoach(),
  'trainerProfile': OnboardingIllustration.trainerProfile(),
  'webDashboard': OnboardingIllustration.webDashboard(),
  'webAlumnos': OnboardingIllustration.webAlumnos(),
  'webAgenda': OnboardingIllustration.webAgenda(),
  'webChat': OnboardingIllustration.webChat(),
  'webBiblioteca': OnboardingIllustration.webBiblioteca(),
  'webRutinas': OnboardingIllustration.webRutinas(),
  'webPagos': OnboardingIllustration.webPagos(),
  'webAjustes': OnboardingIllustration.webAjustes(),
};

Future<void> _pump(
  WidgetTester tester,
  Widget illustration, {
  required ThemeData theme,
  required double height,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 400, height: height, child: illustration),
        ),
      ),
    ),
  );
}

void main() {
  group('OnboardingIllustration', () {
    // The height the slide can hand down is clamped to [130, 400], but 40 is
    // included deliberately: the FittedBox invariant is what keeps this widget
    // from overflowing, and a guard that only tests comfortable sizes would not
    // notice if someone removed it. 40 already caught a real 12px overflow in
    // the avatar rows.
    for (final height in [40.0, 130.0, 400.0]) {
      testWidgets('renders at ${height.toInt()}pt tall without overflowing',
          (tester) async {
        for (final entry in _all.entries) {
          await _pump(
            tester,
            entry.value,
            theme: AppTheme.dark(),
            height: height,
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '${entry.key} overflowed at ${height}pt',
          );
        }
      });
    }

    // Screenshots were rejected for this exact reason: the app defaults to
    // ThemeMode.system, so every slide has to hold up in both themes.
    //
    // The ThemeData is built INSIDE the test body, never in the loop header —
    // AppTheme reaches google_fonts, which throws "no current invoker" when it
    // runs outside a test zone.
    for (final name in ['light', 'dark']) {
      testWidgets('paints itself from the $name palette', (tester) async {
        final theme = name == 'light' ? AppTheme.light() : AppTheme.dark();
        final palette = name == 'light'
            ? AppPalette.mintMagentaLight
            : AppPalette.mintMagenta;

        for (final entry in _all.entries) {
          await _pump(tester, entry.value, theme: theme, height: 260);
          expect(
            tester.takeException(),
            isNull,
            reason: '${entry.key} failed in $name',
          );

          // The assertion that matters: the frame takes its fill and border
          // from the ACTIVE palette. Rendering without throwing would still
          // pass if the colours were hardcoded — which is exactly the failure
          // an image asset would have.
          final frame = tester.widget<Container>(
            find
                .descendant(
                  of: find.byWidget(entry.value),
                  matching: find.byType(Container),
                )
                .first,
          );
          final decoration = frame.decoration! as BoxDecoration;
          expect(
            decoration.color,
            palette.bgCard,
            reason: '${entry.key} did not use the $name card colour',
          );
          expect(
            decoration.border,
            Border.all(color: palette.border, width: 1.5),
            reason: '${entry.key} did not use the $name border colour',
          );
        }
      });
    }

    test('the two palettes actually differ, so the check above has teeth', () {
      expect(
        AppPalette.mintMagentaLight.bgCard,
        isNot(AppPalette.mintMagenta.bgCard),
      );
    });
  });
}
