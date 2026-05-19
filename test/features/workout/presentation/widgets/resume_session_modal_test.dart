// Tests para ResumeSessionModal — SCENARIO-329..333.
// RED: el widget no existe todavía.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/workout/presentation/widgets/resume_session_modal.dart';

import '../../../workout/application/stub_factories.dart';

Widget _wrap(Widget child) => ProviderScope(
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: child),
      ),
    );

void main() {
  group('ResumeSessionModal', () {
    // ── SCENARIO-329: título renderiza ────────────────────────────────────
    testWidgets('SCENARIO-329: muestra el título "Entrenamiento en curso"',
        (tester) async {
      await tester.pumpWidget(_wrap(ResumeSessionModal(
        session: makeSession(),
        onContinue: () {},
        onDiscard: () {},
      )));
      await tester.pump();
      expect(find.text('Entrenamiento en curso'), findsOneWidget);
    });

    // ── SCENARIO-330: startedAt formateado como HH:MM ─────────────────────
    testWidgets('SCENARIO-330: muestra la hora de inicio en formato HH:MM',
        (tester) async {
      // Session con startedAt 18:42 hora local
      final startedAt = DateTime(2026, 5, 18, 18, 42).toUtc();
      final session = makeSession(startedAt: startedAt);
      await tester.pumpWidget(_wrap(ResumeSessionModal(
        session: session,
        onContinue: () {},
        onDiscard: () {},
      )));
      await tester.pump();
      // El modal muestra la hora en formato HH:MM
      expect(find.textContaining('18:42'), findsOneWidget);
    });

    // ── SCENARIO-331: onContinue callback ────────────────────────────────
    testWidgets('SCENARIO-331: botón Continuar invoca onContinue',
        (tester) async {
      var called = false;
      await tester.pumpWidget(_wrap(ResumeSessionModal(
        session: makeSession(),
        onContinue: () => called = true,
        onDiscard: () {},
      )));
      await tester.pump();
      await tester.tap(find.text('Continuar'));
      expect(called, isTrue);
    });

    // ── SCENARIO-332: onDiscard callback ─────────────────────────────────
    testWidgets('SCENARIO-332: botón Descartar invoca onDiscard',
        (tester) async {
      var called = false;
      await tester.pumpWidget(_wrap(ResumeSessionModal(
        session: makeSession(),
        onContinue: () {},
        onDiscard: () => called = true,
      )));
      await tester.pump();
      await tester.tap(find.text('Descartar'));
      expect(called, isTrue);
    });

    // ── SCENARIO-333: ambos botones presentes ────────────────────────────
    testWidgets(
        'SCENARIO-333: ambos botones Continuar y Descartar están presentes',
        (tester) async {
      await tester.pumpWidget(_wrap(ResumeSessionModal(
        session: makeSession(),
        onContinue: () {},
        onDiscard: () {},
      )));
      await tester.pump();
      expect(find.text('Continuar'), findsOneWidget);
      expect(find.text('Descartar'), findsOneWidget);
    });
  });
}
