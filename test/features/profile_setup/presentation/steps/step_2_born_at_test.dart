import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/features/profile_setup/application/profile_setup_notifier.dart';
import 'package:treino/features/profile_setup/application/profile_setup_providers.dart';
import 'package:treino/features/profile_setup/domain/profile_setup_draft.dart';
import 'package:treino/features/profile_setup/presentation/steps/step_2_born_at.dart';

const _minAgeError = 'Tenés que tener 16 años para usar TREINO';

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

    testWidgets('una fecha de menor de 16 muestra el error de edad',
        (tester) async {
      await tester.pumpWidget(_wrap(container));
      notifier().updateBornAt(_yearsAgo(10));
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

    test('con una fecha de menor de 16 no deja avanzar', () {
      expect(stateWith(_yearsAgo(10)).canGoNext, isFalse);
    });

    test('con una fecha válida deja avanzar', () {
      expect(stateWith(DateTime.utc(1990, 5, 20)).canGoNext, isTrue);
    });
  });
}
