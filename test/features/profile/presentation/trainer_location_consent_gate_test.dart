// Serialización del gate de consentimiento de ubicación contra el prompt de
// permisos del sistema operativo (P2-b).
//
// POR QUÉ ESTE ARCHIVO NO EXISTÍA Y TENÍA QUE EXISTIR:
//
// `TrainerLocationConsentGate` no tenía UN SOLO test. El sheet sí
// (`trainer_location_consent_sheet_test.dart`), pero el sheet no decide
// cuándo aparece — eso es el gate. Toda la suite pasaba en verde sobre un
// gate que en un device muestra su sheet DEBAJO del alert del SO.
//
// El bug: #627 se arregló haciendo que `PermissionGate` esperara a
// `onboardingBlocksProvider`. Este gate copió esa espera y su dartdoc decía
// que con eso "never stacks with the push-permission prompt". Falso: dos gates
// hermanos esperando la MISMA condición la ven cumplirse en el MISMO frame y
// encolan los dos su post-frame callback.
//
// Y para un PF que ya vio el tour en otra sesión, `onboardingBlocksProvider`
// da false desde el primer frame de CADA cold start, así que la colisión no es
// un caso raro: es todos los arranques.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/domain/trainer_location.dart';
import 'package:treino/features/notifications/presentation/permission_gate.dart'
    show permissionGateAttemptedProvider, permissionPromptInFlightProvider;
import 'package:treino/features/onboarding/application/onboarding_providers.dart'
    show onboardingBlocksProvider;
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/presentation/trainer_location_consent_sheet.dart';
import 'package:treino/l10n/app_l10n.dart';

const _uid = 'pf-gate-1';

const _location = TrainerLocation(
  id: 'loc-1',
  type: TrainerLocationType.custom,
  customLabel: 'Parque Centenario',
  lat: -34.606,
  lng: -58.435,
  geohash: '69y7pkxfb',
);

class _FakeRepo extends Fake implements UserRepository {
  @override
  Future<void> update(
    String uid,
    Map<String, Object?> partial, {
    bool grantLocationConsent = false,
  }) async {}
}

/// PF con ubicaciones y sin consentimiento: `shouldAsk` da true, o sea que lo
/// único que puede impedir que el sheet aparezca es la serialización.
UserProfile _pf() => UserProfile(
      uid: _uid,
      email: 'pf@test.com',
      displayName: 'Coach',
      role: UserRole.trainer,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      trainerLocations: const [_location],
    );

Future<void> _pump(
  WidgetTester tester, {
  required bool permisosIntentados,
  required bool promptEnPantalla,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userProfileProvider.overrideWith((_) => Stream.value(_pf())),
        userRepositoryProvider.overrideWithValue(_FakeRepo()),
        onboardingBlocksProvider.overrideWithValue(false),
        permissionGateAttemptedProvider
            .overrideWith((ref) => permisosIntentados),
        permissionPromptInFlightProvider
            .overrideWith((ref) => promptEnPantalla),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const Scaffold(
          body: Column(
            children: [Text('HOME'), TrainerLocationConsentGate()],
          ),
        ),
      ),
    ),
  );
  // El gate empuja el sheet desde un post-frame callback y el modal entra con
  // una transición: hacen falta varios frames.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  group('TrainerLocationConsentGate — serialización (P2-b)', () {
    testWidgets('NO muestra el sheet mientras el alert del SO está en pantalla',
        (tester) async {
      await _pump(
        tester,
        permisosIntentados: true,
        promptEnPantalla: true,
      );

      expect(find.byType(TrainerLocationConsentSheet), findsNothing);
    });

    testWidgets('NO muestra el sheet antes de que el prompt de permisos corra',
        (tester) async {
      // `permissionGateAttemptedProvider` arranca en false en cada cold start,
      // así que este es el primer frame de /home: el PermissionGate todavía no
      // encoló nada y este gate NO puede adelantársele.
      await _pump(
        tester,
        permisosIntentados: false,
        promptEnPantalla: false,
      );

      expect(find.byType(TrainerLocationConsentSheet), findsNothing);
    });

    testWidgets('SÍ lo muestra una vez que el prompt de permisos terminó',
        (tester) async {
      // CONTROL POSITIVO. Sin este, los dos de arriba pasarían igual con el
      // gate roto y el sheet no apareciendo nunca — que es exactamente el modo
      // de falla que una serialización mal hecha produce.
      await _pump(
        tester,
        permisosIntentados: true,
        promptEnPantalla: false,
      );

      expect(find.byType(TrainerLocationConsentSheet), findsOneWidget);
    });
  });
}
