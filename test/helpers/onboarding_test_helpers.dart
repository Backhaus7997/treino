import 'package:treino/features/onboarding/domain/onboarding_surface.dart';

/// Every welcome tour already seen.
///
/// Pass as `UserProfile.onboardingSeen` in any test that is NOT about
/// onboarding. The tour (#627) is pushed full-screen over the app right after
/// login, so a profile that has not seen it covers the screen under test and
/// every finder misses — a legitimate signal, just not the one those tests are
/// asserting.
///
/// Tests that DO exercise the tour leave `onboardingSeen` empty, or mark only
/// the surfaces they want out of the way.
Map<String, int> allSurfacesSeen() => <String, int>{
      for (final surface in OnboardingSurface.values)
        surface.wireKey: surface.currentVersion,
    };
