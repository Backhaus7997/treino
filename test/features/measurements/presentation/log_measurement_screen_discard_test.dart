// log_measurement_screen_discard_test.dart — #1502: salir de «Cargar medición»
// con datos cargados pregunta antes de descartarlos.
//
// Cancelar hacía `Navigator.pop()` derecho y el back del sistema también: un
// valor tipeado a mano se perdía sin aviso. Mismo guard que el editor de
// planes (`PopScope(canPop: !dirty)` + "¿Descartar cambios?").

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/measurements/application/measurement_providers.dart';
import 'package:treino/features/measurements/data/measurement_repository.dart';
import 'package:treino/features/measurements/domain/measurement.dart';
import 'package:treino/features/measurements/presentation/log_measurement_screen.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

class _MockMeasurementRepository extends Mock
    implements MeasurementRepository {}

const _discardTitle = '¿Descartar cambios?';
const _homeText = 'HOME';

/// Home → push a la pantalla, para que haya a dónde volver y el pop se vea.
Future<void> _pumpScreen(
  WidgetTester tester, {
  required MeasurementRepository repo,
  Measurement? initial,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      measurementRepositoryProvider.overrideWithValue(repo),
      currentUidProvider.overrideWithValue('athleteX'),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Builder(
        builder: (context) => Scaffold(
          body: Column(
            children: [
              const Text(_homeText),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => initial == null
                        ? const LogMeasurementScreen.selfLog()
                        : LogMeasurementScreen.selfLog(initial: initial),
                  ),
                ),
                child: const Text('ABRIR'),
              ),
            ],
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('ABRIR'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      Measurement(
        id: '',
        athleteId: 'x',
        recordedBy: 'x',
        recordedAt: DateTime.utc(2026, 1, 1),
      ),
    );
  });

  group('#1502 — Cargar medición', () {
    testWidgets('sin datos cargados, Cancelar sale directo (sin diálogo)',
        (tester) async {
      await _pumpScreen(tester, repo: _MockMeasurementRepository());

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.text(_discardTitle), findsNothing);
      expect(find.text(_homeText), findsOneWidget);
    });

    testWidgets('con un valor cargado, Cancelar pregunta; Cancelar se queda',
        (tester) async {
      await _pumpScreen(tester, repo: _MockMeasurementRepository());
      await tester.enterText(find.byType(TextField).first, '80');
      await tester.pump();

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.text(_discardTitle), findsOneWidget);
      await tester.tap(find.byKey(const Key('discard_changes_cancel')));
      await tester.pumpAndSettle();

      // Sigue en el formulario y NO perdió el valor.
      expect(find.text(_discardTitle), findsNothing);
      expect(find.text('GUARDAR MEDICIÓN'), findsOneWidget);
      expect(find.text('80'), findsOneWidget);
    });

    testWidgets('con un valor cargado, Descartar sale de la pantalla',
        (tester) async {
      await _pumpScreen(tester, repo: _MockMeasurementRepository());
      await tester.enterText(find.byType(TextField).first, '80');
      await tester.pump();

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('discard_changes_confirm')));
      await tester.pumpAndSettle();

      expect(find.text(_homeText), findsOneWidget);
      expect(find.text('GUARDAR MEDICIÓN'), findsNothing);
    });

    testWidgets('el back del sistema / swipe de iOS también pregunta',
        (tester) async {
      await _pumpScreen(tester, repo: _MockMeasurementRepository());
      await tester.enterText(find.byType(TextField).first, '80');
      await tester.pump();

      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      await navigator.maybePop();
      await tester.pumpAndSettle();

      expect(find.text(_discardTitle), findsOneWidget);
      expect(find.text('GUARDAR MEDICIÓN'), findsOneWidget);
    });

    testWidgets('GUARDAR con valores no se frena a sí mismo ni pregunta',
        (tester) async {
      final repo = _MockMeasurementRepository();
      when(() => repo.add(any())).thenAnswer(
        (inv) async => inv.positionalArguments.first as Measurement,
      );
      await _pumpScreen(tester, repo: repo);
      await tester.enterText(find.byType(TextField).first, '80');
      await tester.pump();

      await tester.tap(find.text('GUARDAR MEDICIÓN'));
      await tester.pumpAndSettle();

      expect(find.text(_discardTitle), findsNothing);
      expect(find.text(_homeText), findsOneWidget);
    });
  });

  group('#1502 — Editar medición', () {
    final initial = Measurement(
      id: 'm1',
      athleteId: 'athleteX',
      recordedBy: 'athleteX',
      recordedAt: DateTime.utc(2026, 3, 10, 14, 30),
      weightKg: 50,
      notes: 'nota original',
    );

    testWidgets('sin tocar nada, Cancelar sale directo', (tester) async {
      await _pumpScreen(
        tester,
        repo: _MockMeasurementRepository(),
        initial: initial,
      );

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.text(_discardTitle), findsNothing);
      expect(find.text(_homeText), findsOneWidget);
    });

    testWidgets('si cambió un valor, Cancelar pregunta', (tester) async {
      await _pumpScreen(
        tester,
        repo: _MockMeasurementRepository(),
        initial: initial,
      );
      await tester.enterText(find.byType(TextField).first, '55');
      await tester.pump();

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.text(_discardTitle), findsOneWidget);
    });

    testWidgets('volver al valor original deja salir sin preguntar',
        (tester) async {
      await _pumpScreen(
        tester,
        repo: _MockMeasurementRepository(),
        initial: initial,
      );
      await tester.enterText(find.byType(TextField).first, '55');
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, '50');
      await tester.pump();

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.text(_discardTitle), findsNothing);
      expect(find.text(_homeText), findsOneWidget);
    });
  });
}
