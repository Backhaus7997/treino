import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/onboarding/domain/onboarding_module.dart';
import 'package:treino/features/onboarding/domain/onboarding_surface.dart';

/// Pure domain tests — no widget tree, no providers, no Firestore. The
/// versioning algebra is where an off-by-one would hide, so it is verified in
/// isolation and in milliseconds.
void main() {
  group('wireKey', () {
    test('matches the enum name and is unique', () {
      expect(OnboardingSurface.athleteMobile.wireKey, 'athleteMobile');
      final keys = OnboardingSurface.values.map((s) => s.wireKey).toSet();
      expect(keys.length, OnboardingSurface.values.length);
    });
  });

  group('slides', () {
    test('mobile surfaces run the five bottom-bar tabs, in order', () {
      const expected = [
        OnboardingModule.home,
        OnboardingModule.workout,
        OnboardingModule.feed,
        OnboardingModule.coach,
        OnboardingModule.profile,
      ];
      expect(OnboardingSurface.athleteMobile.slides, expected);
      expect(OnboardingSurface.trainerMobile.slides, expected);
    });

    test('the web surface runs the eight sidebar sections', () {
      // Eight after the "W2 reduce" — not the ~20 directories on disk, and not
      // the 19 the openspec doc still claims.
      final web = OnboardingSurface.trainerWeb.slides;
      expect(web.length, 8);
      expect(web.every((m) => m.name.startsWith('web')), isTrue);
    });

    test('no surface mixes mobile and web modules', () {
      for (final surface in OnboardingSurface.values) {
        final isWeb = surface == OnboardingSurface.trainerWeb;
        expect(
          surface.slides.every((m) => m.name.startsWith('web') == isWeb),
          isTrue,
          reason: '${surface.name} mixes surfaces',
        );
      }
    });

    test('every surface has slides and none repeat', () {
      for (final surface in OnboardingSurface.values) {
        expect(surface.slides, isNotEmpty);
        expect(surface.slides.toSet().length, surface.slides.length,
            reason: '${surface.name} repeats a slide');
      }
    });
  });

  group('shouldShow', () {
    const surface = OnboardingSurface.athleteMobile;

    test('shows on an empty map — no backfill needed', () {
      expect(surface.shouldShow(const {}), isTrue);
    });

    test('shows when another surface is marked but this one is not', () {
      expect(surface.shouldShow(const {'trainerWeb': 99}), isTrue);
    });

    test('does NOT show at the current version', () {
      expect(surface.shouldShow({surface.wireKey: surface.currentVersion}),
          isFalse);
    });

    test('does NOT show at a NEWER version', () {
      // An older client must never re-trigger a tour it has no copy for. This
      // is why the comparison is `<` and not `!=`.
      expect(
        surface.shouldShow({surface.wireKey: surface.currentVersion + 1}),
        isFalse,
      );
    });
  });

  group('markedIn', () {
    test('PRESERVES the other surfaces', () {
      // The contract that stops a trainer from losing their web flag when they
      // finish the mobile tour, and vice versa.
      const other = OnboardingSurface.trainerWeb;
      const surface = OnboardingSurface.trainerMobile;

      final result = surface.markedIn({other.wireKey: other.currentVersion});

      expect(result[other.wireKey], other.currentVersion);
      expect(result[surface.wireKey], surface.currentVersion);
      expect(result.length, 2);
    });

    test('does not mutate the input', () {
      final original = <String, int>{'trainerWeb': 1};
      OnboardingSurface.athleteMobile.markedIn(original);
      expect(original, {'trainerWeb': 1});
    });

    test('the result satisfies shouldShow == false', () {
      for (final surface in OnboardingSurface.values) {
        expect(surface.shouldShow(surface.markedIn(const {})), isFalse);
      }
    });
  });
}
