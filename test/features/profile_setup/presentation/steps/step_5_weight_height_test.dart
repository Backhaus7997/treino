// Paso 5 del alta (peso y altura). #1698: el paso no tiene `Form`, así que el
// `validator:` de los campos nunca corría y SIGUIENTE quedaba apagado sin decir
// por qué.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/profile_setup/application/profile_setup_providers.dart';
import 'package:treino/features/profile_setup/presentation/steps/step_5_weight_height.dart';
import 'package:treino/l10n/app_l10n.dart';

Widget _wrap(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: Step5WeightHeight()),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
      ),
    );

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  // El primer campo es el peso; el segundo, la altura.
  Finder peso() => find.byType(TextField).at(0);
  Finder altura() => find.byType(TextField).at(1);

  Future<void> escribir(WidgetTester tester, Finder campo, String texto) async {
    await tester.enterText(campo, texto);
    await tester.pump();
  }

  bool pasoValido() =>
      container.read(profileSetupNotifierProvider).draft.isStep5Valid;

  testWidgets('sin escribir nada no hay ningún error', (tester) async {
    await tester.pumpWidget(_wrap(container));
    await tester.pump();

    expect(find.text('Ingresá tu peso'), findsNothing);
    expect(find.text('Ingresá tu altura'), findsNothing);
  });

  group('peso', () {
    testWidgets('por debajo del mínimo dice por qué no se puede seguir',
        (tester) async {
      await tester.pumpWidget(_wrap(container));
      await tester.pump();

      await escribir(tester, peso(), '19');
      await escribir(tester, altura(), '168');

      expect(find.text('Mínimo 20 kg'), findsOneWidget);
      expect(pasoValido(), isFalse);
    });

    testWidgets('por encima del máximo', (tester) async {
      await tester.pumpWidget(_wrap(container));
      await tester.pump();

      await escribir(tester, peso(), '300');

      expect(find.text('Máximo 300 kg'), findsOneWidget);
    });

    testWidgets('texto que no es un número', (tester) async {
      await tester.pumpWidget(_wrap(container));
      await tester.pump();

      await escribir(tester, peso(), 'abc');

      expect(find.text('Número inválido'), findsOneWidget);
    });

    testWidgets('borrar lo escrito pide el peso', (tester) async {
      await tester.pumpWidget(_wrap(container));
      await tester.pump();

      await escribir(tester, peso(), '82');
      await escribir(tester, peso(), '');

      expect(find.text('Ingresá tu peso'), findsOneWidget);
    });
  });

  group('altura', () {
    testWidgets('por debajo del mínimo', (tester) async {
      await tester.pumpWidget(_wrap(container));
      await tester.pump();

      await escribir(tester, peso(), '82');
      await escribir(tester, altura(), '100');

      expect(find.text('Mínimo 100 cm'), findsOneWidget);
      expect(pasoValido(), isFalse);
    });

    testWidgets('por encima del máximo', (tester) async {
      await tester.pumpWidget(_wrap(container));
      await tester.pump();

      await escribir(tester, altura(), '250');

      expect(find.text('Máximo 250 cm'), findsOneWidget);
    });

    testWidgets('borrar lo escrito pide la altura', (tester) async {
      await tester.pumpWidget(_wrap(container));
      await tester.pump();

      await escribir(tester, altura(), '168');
      await escribir(tester, altura(), '');

      expect(find.text('Ingresá tu altura'), findsOneWidget);
    });
  });

  testWidgets('con valores válidos no hay errores y el paso queda completo',
      (tester) async {
    await tester.pumpWidget(_wrap(container));
    await tester.pump();

    await escribir(tester, peso(), '19');
    await escribir(tester, altura(), '99');
    expect(find.text('Mínimo 20 kg'), findsOneWidget);
    expect(find.text('Mínimo 100 cm'), findsOneWidget);

    await escribir(tester, peso(), '82,5');
    await escribir(tester, altura(), '168');

    expect(find.text('Mínimo 20 kg'), findsNothing);
    expect(find.text('Mínimo 100 cm'), findsNothing);
    expect(pasoValido(), isTrue);
  });
}
