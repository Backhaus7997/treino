import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:treino/app/theme/app_palette.dart';
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

  testWidgets(
      'T5: LogMeasurementScreen.selfLog attributes the measurement to the '
      'authenticated athlete (recordedBy == athleteId == uid)', (tester) async {
    final repo = _MockMeasurementRepository();
    when(() => repo.add(any())).thenAnswer(
      (inv) async => inv.positionalArguments.first as Measurement,
    );

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
        home: const LogMeasurementScreen.selfLog(),
      ),
    ));
    await tester.pumpAndSettle();

    // First field is body weight. Any value enables GUARDAR.
    await tester.enterText(find.byType(TextField).first, '80');
    await tester.pump();

    await tester.tap(find.text('GUARDAR MEDICIÓN'));
    await tester.pump();

    final captured =
        verify(() => repo.add(captureAny())).captured.single as Measurement;
    expect(captured.recordedBy, 'athleteX');
    expect(captured.athleteId, 'athleteX');
    expect(captured.weightKg, 80);
  });

  testWidgets(
      '#439 edit mode: prefills the form and saves via update() preserving '
      'id/athleteId/recordedBy/recordedAt', (tester) async {
    final repo = _MockMeasurementRepository();
    when(() => repo.update(any())).thenAnswer((_) async {});

    // El caso QA del bug: 500 kg tipeados en vez de 50, hoy imposible de
    // corregir desde mobile.
    final initial = Measurement(
      id: 'm1',
      athleteId: 'athleteX',
      recordedBy: 'trainerT',
      recordedAt: DateTime.utc(2026, 3, 10, 14, 30),
      weightKg: 500,
      fatPercentage: 15.5,
      notes: 'nota original',
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        measurementRepositoryProvider.overrideWithValue(repo),
        currentUidProvider.overrideWithValue('trainerT'),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: LogMeasurementScreen(athleteId: 'athleteX', initial: initial),
      ),
    ));
    await tester.pumpAndSettle();

    // Pre-poblado: valores exactos sin ".0" redundante, notas incluidas.
    expect(find.text('Editar medición'), findsOneWidget);
    expect(find.text('500'), findsOneWidget);
    expect(find.text('15.5'), findsOneWidget);
    expect(find.text('nota original'), findsOneWidget);

    // Corrige el typo y guarda.
    await tester.enterText(find.byType(TextField).first, '50');
    await tester.pump();
    await tester.tap(find.text('GUARDAR CAMBIOS'));
    await tester.pump();

    final captured =
        verify(() => repo.update(captureAny())).captured.single as Measurement;
    expect(captured.id, 'm1');
    expect(captured.athleteId, 'athleteX');
    expect(captured.recordedBy, 'trainerT');
    expect(captured.recordedAt, DateTime.utc(2026, 3, 10, 14, 30),
        reason: 'editar valores no mueve el punto en la línea de tiempo');
    expect(captured.weightKg, 50);
    expect(captured.fatPercentage, 15.5);
    expect(captured.notes, 'nota original');
    verifyNever(() => repo.add(any()));
  });

  // ── #1483: rango por campo ────────────────────────────────────────────────

  testWidgets(
      '#1483: 150 % de grasa muestra el rango, deshabilita GUARDAR, y al '
      'corregir el error se va', (tester) async {
    final repo = _MockMeasurementRepository();
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
        home: const LogMeasurementScreen.selfLog(),
      ),
    ));
    await tester.pumpAndSettle();

    ButtonStyleButton guardar() => tester.widget<ButtonStyleButton>(
          find.ancestor(
            of: find.text('GUARDAR MEDICIÓN'),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          ),
        );

    // Segundo campo: % de grasa.
    final grasa = find.byType(TextField).at(1);
    await tester.enterText(grasa, '150');
    await tester.pump();

    expect(find.text('Entre 2 y 70 %'), findsOneWidget);
    expect(guardar().onPressed, isNull,
        reason: 'no se puede guardar un valor fuera de rango');

    await tester.enterText(grasa, '20');
    await tester.pump();

    expect(find.text('Entre 2 y 70 %'), findsNothing,
        reason: 'el error se limpia al corregir (no repetir #1500)');
    expect(guardar().onPressed, isNotNull);
  });

  testWidgets(
      '#1483 edición: un valor viejo fuera de rango muestra su error al abrir, '
      'sin esperar a que el PF toque el campo', (tester) async {
    // Lo marcó Codex en #1524: válido con el tope viejo de 500, inválido con
    // el rango nuevo. GUARDAR arrancaba deshabilitado sin decir por qué.
    final initial = Measurement(
      id: 'm1',
      athleteId: 'athleteX',
      recordedBy: 'trainerT',
      recordedAt: DateTime.utc(2026, 3, 10, 14, 30),
      fatPercentage: 150,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        measurementRepositoryProvider
            .overrideWithValue(_MockMeasurementRepository()),
        currentUidProvider.overrideWithValue('trainerT'),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: LogMeasurementScreen(athleteId: 'athleteX', initial: initial),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Entre 2 y 70 %'), findsOneWidget);
  });

  // #1484: el header iba con el título a la derecha y «Cancelar» en MAGENTA.
  // Se alinea al de Nuevo post: CANCELAR neutro a la izquierda, título al
  // centro.
  testWidgets('#1484: header con CANCELAR neutro y título centrado',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        measurementRepositoryProvider
            .overrideWithValue(_MockMeasurementRepository()),
        currentUidProvider.overrideWithValue('athleteX'),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const LogMeasurementScreen.selfLog(),
      ),
    ));
    await tester.pumpAndSettle();

    final cancelar = find.text('CANCELAR');
    expect(cancelar, findsOneWidget);
    expect(tester.widget<Text>(cancelar).style!.color,
        AppPalette.mintMagentaLight.textMuted);

    final titulo = find.text('Cargar medición');
    final anchoPantalla =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(tester.getCenter(titulo).dx, closeTo(anchoPantalla / 2, 1));
    expect(tester.getCenter(cancelar).dx, lessThan(anchoPantalla / 4));
  });

  // Lo marcó la revisión de #1544: el título centrado en un Stack no le
  // reservaba lugar a CANCELAR, y con texto grande en un teléfono angosto
  // podían pisarse.
  testWidgets('#1484: con texto grande en 375 pt el título no pisa CANCELAR',
      (tester) async {
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        measurementRepositoryProvider
            .overrideWithValue(_MockMeasurementRepository()),
        currentUidProvider.overrideWithValue('athleteX'),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: LogMeasurementScreen(
          athleteId: 'athleteX',
          initial: Measurement(
            id: 'm1',
            athleteId: 'athleteX',
            recordedBy: 'athleteX',
            recordedAt: DateTime.utc(2026, 3, 10, 14, 30),
            weightKg: 80,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final cancelar = tester.getRect(find.text('CANCELAR'));
    final titulo = tester.getRect(find.text('Editar medición'));
    expect(titulo.overlaps(cancelar), isFalse,
        reason: 'título $titulo pisa a CANCELAR $cancelar');
  });
}
