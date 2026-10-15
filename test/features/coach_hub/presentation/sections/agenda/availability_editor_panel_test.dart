// AvailabilityEditorPanel — CRUD de reglas y excepciones de disponibilidad
// (pulido-post-revision). Smoke de estados + regresión SCENARIO-STALE para
// ambos streams (reglas y excepciones).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/domain/availability_override.dart';
import 'package:treino/features/coach/domain/availability_rule.dart';
import 'package:treino/features/coach_hub/presentation/sections/agenda/availability_editor_panel.dart';

const _trainerId = 'trainer-1';
final _kRangeFrom = DateTime.utc(2026, 1, 1);
final _kRangeTo = DateTime.utc(2027, 12, 31);

final _overridesKey = OverridesKey(
  trainerId: _trainerId,
  fromDate: _kRangeFrom,
  toDate: _kRangeTo,
);

AvailabilityRule _rule() => const AvailabilityRule(
      id: 'r1',
      trainerId: _trainerId,
      dayOfWeek: 1,
      startHour: 9,
      startMinute: 0,
      endHour: 12,
      endMinute: 0,
      slotDurationMin: 60,
    );

AvailabilityOverride _override() => AvailabilityOverride.block(
      id: 'o1',
      trainerId: _trainerId,
      date: DateTime.utc(2026, 8, 1),
    );

Widget _harness({
  required Stream<List<AvailabilityRule>> rulesStream,
  required Stream<List<AvailabilityOverride>> overridesStream,
}) =>
    ProviderScope(
      overrides: [
        availabilityRulesStreamProvider(_trainerId)
            .overrideWith((ref) => rulesStream),
        overridesStreamProvider(_overridesKey)
            .overrideWith((ref) => overridesStream),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: AvailabilityEditorPanel(trainerId: _trainerId),
        ),
      ),
    );

void main() {
  group('AvailabilityEditorPanel — estados', () {
    testWidgets('data → muestra la regla y sin excepciones', (tester) async {
      await tester.pumpWidget(_harness(
        rulesStream: Stream.value([_rule()]),
        overridesStream: Stream.value(const []),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Sin excepciones.'), findsOneWidget);
    });
  });

  group(
      'SCENARIO-STALE — disponibilidad sostiene reglas y excepciones ante '
      'error transitorio (pulido-post-revision)', () {
    // Regression: `rulesAsync.when(...)` y `overridesAsync.when(...)`
    // despachan por SUBTIPO runtime (ignoran `hasValue`) —
    // `availabilityRulesStreamProvider`/`overridesStreamProvider` son
    // StreamProviders en vivo, Riverpod 2.5+ preserva el valor previo dentro
    // de un AsyncError subsiguiente (copyWithPrevious/"seamless"), así que
    // un error transitorio (con datos ya cargados) tapaba cada lista con su
    // estado de error.
    testWidgets(
        'las reglas ya cargadas no desaparecen tras un error transitorio '
        'del stream de reglas (stale-while-refresh)', (tester) async {
      var listens = 0;
      final rulesController =
          StreamController<List<AvailabilityRule>>.broadcast(
        onListen: () => listens++,
      );
      addTearDown(rulesController.close);

      await tester.pumpWidget(_harness(
        rulesStream: rulesController.stream,
        overridesStream: Stream.value(const []),
      ));
      await tester.pump();

      rulesController.add([_rule()]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('09:00 – 12:00 · 60 min'), findsOneWidget);
      expect(find.text('Datos desactualizados'), findsNothing);

      rulesController.addError(Exception('transient stream hiccup'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.text('09:00 – 12:00 · 60 min'),
        findsOneWidget,
        reason: 'un error transitorio con reglas ya cargadas no debe tapar '
            'la lista de reglas',
      );
      expect(find.text('Datos desactualizados'), findsOneWidget);

      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(listens, 2, reason: 'Reintentar tiene que re-suscribir el stream');

      rulesController.add(const [
        AvailabilityRule(
          id: 'r2',
          trainerId: _trainerId,
          dayOfWeek: 2,
          startHour: 14,
          startMinute: 0,
          endHour: 17,
          endMinute: 0,
          slotDurationMin: 60,
        ),
      ]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('14:00 – 17:00 · 60 min'), findsOneWidget);
      expect(find.text('09:00 – 12:00 · 60 min'), findsNothing);
      expect(find.text('Datos desactualizados'), findsNothing);
    });

    testWidgets(
        'las excepciones ya cargadas no desaparecen tras un error '
        'transitorio del stream de excepciones (stale-while-refresh)',
        (tester) async {
      var listens = 0;
      final overridesController =
          StreamController<List<AvailabilityOverride>>.broadcast(
        onListen: () => listens++,
      );
      addTearDown(overridesController.close);

      await tester.pumpWidget(_harness(
        rulesStream: Stream.value(const []),
        overridesStream: overridesController.stream,
      ));
      await tester.pump();

      overridesController.add([_override()]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Día bloqueado'), findsOneWidget);
      expect(find.text('Datos desactualizados'), findsNothing);

      overridesController.addError(Exception('transient stream hiccup'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.text('Día bloqueado'),
        findsOneWidget,
        reason: 'un error transitorio con excepciones ya cargadas no debe '
            'tapar la lista de excepciones',
      );
      expect(find.text('Datos desactualizados'), findsOneWidget);

      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(listens, 2, reason: 'Reintentar tiene que re-suscribir el stream');

      overridesController.add(const <AvailabilityOverride>[]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Sin excepciones.'), findsOneWidget);
      expect(find.text('Día bloqueado'), findsNothing);
      expect(find.text('Datos desactualizados'), findsNothing);
    });
  });
}
