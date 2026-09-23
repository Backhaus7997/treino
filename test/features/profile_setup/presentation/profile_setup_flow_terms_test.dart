// El checkbox de Términos del último paso del alta, desde lo que se VE.
//
// La lógica de «a quién se le pide» vive en `termsConsentRequiredProvider` y
// tiene su suite propia. Esto fija el cableado de la pantalla: con qué
// respuesta del provider aparece el checkbox. En particular, que «todavía no
// se sabe» (null) lo muestra: preguntar de más no le cuesta nada a nadie,
// preguntar de menos es un alta sin consentimiento.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/presentation/widgets/terms_checkbox.dart';
import 'package:treino/features/profile_setup/application/profile_setup_notifier.dart';
import 'package:treino/features/profile_setup/application/profile_setup_providers.dart';
import 'package:treino/features/profile_setup/application/terms_consent_provider.dart';
import 'package:treino/features/profile_setup/domain/profile_setup_draft.dart';
import 'package:treino/features/profile_setup/presentation/profile_setup_flow.dart';
import 'package:treino/l10n/app_l10n.dart';

/// El flujo parado en el último paso, que es el único que muestra el checkbox.
class _UltimoPaso extends ProfileSetupNotifier {
  @override
  ProfileSetupState build() => const ProfileSetupState(
        draft: ProfileSetupDraft(),
        currentStep: ProfileSetupState.total - 1,
      );
}

Widget _flujo({required bool? requiereConsentimiento}) => ProviderScope(
      overrides: [
        profileSetupNotifierProvider.overrideWith(_UltimoPaso.new),
        termsConsentRequiredProvider.overrideWithValue(requiereConsentimiento),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const ProfileSetupFlow(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
      ),
    );

void main() {
  group('ProfileSetupFlow — checkbox de Términos en el último paso', () {
    testWidgets('sin consentimiento registrado → aparece', (tester) async {
      await tester.pumpWidget(_flujo(requiereConsentimiento: true));
      await tester.pump();

      expect(find.byType(TermsCheckbox), findsOneWidget);
    });

    testWidgets('con consentimiento registrado (email) → no aparece',
        (tester) async {
      await tester.pumpWidget(_flujo(requiereConsentimiento: false));
      await tester.pump();

      expect(find.byType(TermsCheckbox), findsNothing);
    });

    testWidgets('todavía no se sabe → aparece', (tester) async {
      await tester.pumpWidget(_flujo(requiereConsentimiento: null));
      await tester.pump();

      expect(find.byType(TermsCheckbox), findsOneWidget);
    });
  });
}
