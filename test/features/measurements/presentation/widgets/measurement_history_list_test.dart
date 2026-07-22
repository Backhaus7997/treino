// MeasurementHistoryList (#439) — la pieza compartida de editar/borrar
// mediciones en mobile (sección ANTROPOMETRÍA del PF y pantalla MEDIDAS del
// atleta). Acá se testea el comportamiento UNA vez; los tests de cada pantalla
// sólo verifican el cableado (uid, tag, navegación de edición).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/measurements/application/measurement_providers.dart';
import 'package:treino/features/measurements/data/measurement_repository.dart';
import 'package:treino/features/measurements/domain/measurement.dart';
import 'package:treino/features/measurements/presentation/widgets/measurement_history_list.dart';
import 'package:treino/l10n/app_l10n.dart';

class _MockMeasurementRepository extends Mock
    implements MeasurementRepository {}

Measurement _m({
  required String id,
  required String recordedBy,
  required DateTime at,
  double? kg,
}) =>
    Measurement(
      id: id,
      athleteId: 'athleteX',
      recordedBy: recordedBy,
      recordedAt: at,
      weightKg: kg ?? 80,
    );

Widget _wrap({
  required MeasurementRepository repo,
  required List<Measurement> measurements,
  required String currentUid,
  ValueChanged<Measurement>? onEdit,
}) =>
    ProviderScope(
      overrides: [measurementRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: MeasurementHistoryList(
              measurements: measurements,
              currentUid: currentUid,
              readOnlyLabel: 'Ajena',
              onEdit: onEdit ?? (_) {},
            ),
          ),
        ),
      ),
    );

AppL10n _l10n(WidgetTester tester) =>
    AppL10n.of(tester.element(find.byType(MeasurementHistoryList)));

void main() {
  testWidgets(
      'acciones sólo en filas propias (recordedBy == uid); las ajenas '
      'muestran el tag read-only — el mismo pin que las rules', (tester) async {
    final repo = _MockMeasurementRepository();
    await tester.pumpWidget(_wrap(
      repo: repo,
      currentUid: 'me',
      measurements: [
        _m(id: 'mine', recordedBy: 'me', at: DateTime.utc(2026, 1, 1)),
        _m(id: 'theirs', recordedBy: 'other', at: DateTime.utc(2026, 2, 1)),
      ],
    ));
    await tester.pumpAndSettle();

    final l10n = _l10n(tester);
    expect(find.byTooltip(l10n.measurementHistoryEditTooltip), findsOneWidget);
    expect(
        find.byTooltip(l10n.measurementHistoryDeleteTooltip), findsOneWidget);
    expect(find.text('Ajena'), findsOneWidget);
  });

  testWidgets('orden DESC: la medición más reciente arriba', (tester) async {
    final repo = _MockMeasurementRepository();
    await tester.pumpWidget(_wrap(
      repo: repo,
      currentUid: 'me',
      measurements: [
        // Entrada más vieja PRIMERO en la lista de entrada: el widget ordena.
        // Mediodía UTC (no medianoche): el widget formatea recordedAt.toLocal(),
        // así que una medianoche UTC salta al día anterior en timezones con
        // offset negativo (ART/UTC-3) — este test pasaba en CI (UTC) pero fallaba
        // localmente en Argentina. Mediodía UTC no cruza el día en ningún tz real.
        _m(id: 'old', recordedBy: 'me', at: DateTime.utc(2026, 1, 1, 12)),
        _m(id: 'new', recordedBy: 'me', at: DateTime.utc(2026, 2, 1, 12)),
      ],
    ));
    await tester.pumpAndSettle();

    final newerY = tester.getTopLeft(find.text('1 feb 2026')).dy;
    final olderY = tester.getTopLeft(find.text('1 ene 2026')).dy;
    expect(newerY, lessThan(olderY));
  });

  testWidgets('borrar: CANCELAR en el dialog no llama al repo', (tester) async {
    final repo = _MockMeasurementRepository();
    await tester.pumpWidget(_wrap(
      repo: repo,
      currentUid: 'me',
      measurements: [
        _m(id: 'mine', recordedBy: 'me', at: DateTime.utc(2026, 1, 1)),
      ],
    ));
    await tester.pumpAndSettle();
    final l10n = _l10n(tester);

    await tester.tap(find.byTooltip(l10n.measurementHistoryDeleteTooltip));
    await tester.pumpAndSettle();

    expect(find.text(l10n.measurementDeleteConfirmTitle), findsOneWidget);
    await tester.tap(find.text(l10n.commonCancel));
    await tester.pumpAndSettle();

    verifyNever(() => repo.delete(any()));
  });

  testWidgets('borrar: CONFIRMAR llama repo.delete(id) y muestra el snackbar',
      (tester) async {
    final repo = _MockMeasurementRepository();
    when(() => repo.delete(any())).thenAnswer((_) async {});
    await tester.pumpWidget(_wrap(
      repo: repo,
      currentUid: 'me',
      measurements: [
        _m(id: 'm-typo', recordedBy: 'me', at: DateTime.utc(2026, 1, 1)),
      ],
    ));
    await tester.pumpAndSettle();
    final l10n = _l10n(tester);

    await tester.tap(find.byTooltip(l10n.measurementHistoryDeleteTooltip));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.measurementDeleteConfirmAction));
    await tester.pumpAndSettle();

    verify(() => repo.delete('m-typo')).called(1);
    expect(find.text(l10n.measurementDeleteSuccess), findsOneWidget);
  });

  testWidgets('editar: dispara onEdit con la medición de ESA fila',
      (tester) async {
    final repo = _MockMeasurementRepository();
    Measurement? edited;
    await tester.pumpWidget(_wrap(
      repo: repo,
      currentUid: 'me',
      onEdit: (m) => edited = m,
      measurements: [
        _m(id: 'mine', recordedBy: 'me', at: DateTime.utc(2026, 1, 1)),
        _m(id: 'theirs', recordedBy: 'other', at: DateTime.utc(2026, 2, 1)),
      ],
    ));
    await tester.pumpAndSettle();
    final l10n = _l10n(tester);

    await tester.tap(find.byTooltip(l10n.measurementHistoryEditTooltip));
    await tester.pump();

    expect(edited?.id, 'mine');
  });

  testWidgets(
      'más de 5 filas: cap inicial + "Ver todas (N)" expande y "Ver menos" '
      'colapsa', (tester) async {
    final repo = _MockMeasurementRepository();
    await tester.pumpWidget(_wrap(
      repo: repo,
      currentUid: 'me',
      measurements: [
        for (var d = 1; d <= 7; d++)
          _m(id: 'm$d', recordedBy: 'me', at: DateTime.utc(2026, 1, d)),
      ],
    ));
    await tester.pumpAndSettle();
    final l10n = _l10n(tester);

    expect(
      find.byTooltip(l10n.measurementHistoryEditTooltip),
      findsNWidgets(5),
      reason: 'colapsado: sólo las 5 más recientes',
    );
    expect(find.text(l10n.measurementHistoryShowAll(7)), findsOneWidget);

    await tester.tap(find.text(l10n.measurementHistoryShowAll(7)));
    await tester.pumpAndSettle();

    expect(
        find.byTooltip(l10n.measurementHistoryEditTooltip), findsNWidgets(7));

    await tester.tap(find.text(l10n.measurementHistoryShowLess));
    await tester.pumpAndSettle();

    expect(
        find.byTooltip(l10n.measurementHistoryEditTooltip), findsNWidgets(5));
  });
}
