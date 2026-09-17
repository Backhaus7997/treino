import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/features/profile_setup/application/profile_setup_notifier.dart';
import 'package:treino/features/profile_setup/application/profile_setup_providers.dart';
import 'package:treino/features/profile_setup/domain/profile_setup_draft.dart';
import 'package:treino/features/profile_setup/presentation/steps/step_2_born_at.dart';
import 'package:treino/features/profile_setup/domain/profile_setup_validators.dart';

// Interpolado, no hardcodeado: el día que kMinAgeYears cambie, este test
// tiene que seguir al código en vez de ponerse rojo por un número viejo.
final _minAgeError =
    'Tenés que tener ${ProfileSetupValidators.kMinAgeYears} años para usar TREINO';

/// Una edad claramente por debajo del piso, sea cual sea el piso.
int get _underAge => ProfileSetupValidators.kMinAgeYears - 3;

/// Relativas a hoy para que los tests no envejezcan. Los bordes exactos
/// (cumple 16 hoy / mañana, 29 de febrero) viven en
/// `profile_setup_validators_test.dart`, que inyecta `now`.
DateTime _yearsAgo(int n) => DateTime.utc(DateTime.now().year - n, 1, 1);

Widget _wrap(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: Step2BornAt()),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
      ),
    );

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });
  tearDown(() => container.dispose());

  ProfileSetupNotifier notifier() =>
      container.read(profileSetupNotifierProvider.notifier);

  group('Step2BornAt', () {
    testWidgets('sin fecha muestra el hint y ningún error', (tester) async {
      await tester.pumpWidget(_wrap(container));
      await tester.pump();

      expect(find.text('DD/MM/AAAA'), findsOneWidget);
      expect(find.text(_minAgeError), findsNothing);
    });

    testWidgets('una fecha por debajo del piso muestra el error de edad',
        (tester) async {
      await tester.pumpWidget(_wrap(container));
      notifier().updateBornAt(_yearsAgo(_underAge));
      await tester.pump();

      expect(find.text(_minAgeError), findsOneWidget);
    });

    testWidgets('una fecha válida muestra la fecha y ningún error',
        (tester) async {
      await tester.pumpWidget(_wrap(container));
      notifier().updateBornAt(DateTime.utc(1990, 5, 20));
      await tester.pump();

      expect(find.text('20/05/1990'), findsOneWidget);
      expect(find.text(_minAgeError), findsNothing);
    });
  });

  // El "no deja avanzar" del paso vive en canGoNext, no en el widget: el botón
  // SIGUIENTE lo dibuja el footer del flow, no este step. Se assertea acá
  // igual, al lado de lo que el usuario ve, porque son las dos mitades de la
  // misma promesa — y si divergen, la pantalla marca rojo con el botón
  // habilitado.
  group('canGoNext del paso 2', () {
    ProfileSetupState stateWith(DateTime? bornAt) => ProfileSetupState(
          draft: ProfileSetupDraft(bornAt: bornAt),
          currentStep: 1,
        );

    test('sin fecha no deja avanzar', () {
      expect(stateWith(null).canGoNext, isFalse);
    });

    test('con una fecha por debajo del piso no deja avanzar', () {
      expect(stateWith(_yearsAgo(_underAge)).canGoNext, isFalse);
    });

    test('con una fecha válida deja avanzar', () {
      expect(stateWith(DateTime.utc(1990, 5, 20)).canGoNext, isTrue);
    });
  });
}
