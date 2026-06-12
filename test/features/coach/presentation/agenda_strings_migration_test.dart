// AgendaStrings ARB key existence and value verbatim tests.
// These tests verify that AppL10n exposes all AgendaStrings keys
// with the exact es-AR copy that was in agenda_strings.dart.
//
// RED → GREEN cycle:
//   RED  (T-I18N-014): this file; keys do not exist yet in ARB → all fail
//   GREEN (T-I18N-016): add keys to ARB, migrate call sites, delete agenda_strings.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/l10n/app_l10n.dart';

// ── Helper ─────────────────────────────────────────────────────────────────

AppL10n _l10n(WidgetTester tester) => AppL10n.of(tester.element(find.byType(SizedBox)));

Widget _harness() => MaterialApp(
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: const Scaffold(body: SizedBox.shrink()),
    );

// ── Tests ──────────────────────────────────────────────────────────────────

void main() {
  group('AppL10n — AgendaStrings keys (SCENARIO-762)', () {
    testWidgets('agendaButtonLabel', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).agendaButtonLabel, 'VER AGENDA DEL PF');
    });

    testWidgets('agendaScreenTitle', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).agendaScreenTitle, 'Agenda');
    });

    testWidgets('agendaEmptyAvailability', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).agendaEmptyAvailability,
          'Tu PF todavía no configuró horarios.');
    });

    testWidgets('agendaBookingConfirmTitle', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).agendaBookingConfirmTitle, 'Confirmar reserva');
    });

    testWidgets('agendaBookingConfirmBody — ICU interpolation', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      // Using a fixed date 15/03/2026 at 10:30
      final result = _l10n(t).agendaBookingConfirmBody('15/03/2026', '10:30');
      expect(result,
          '¿Confirmar reserva el 15/03/2026 a las 10:30?');
    });

    testWidgets('agendaBookingConfirmCta', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).agendaBookingConfirmCta, 'Confirmar');
    });

    testWidgets('agendaBookingCancel', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).agendaBookingCancel, 'Cancelar');
    });

    testWidgets('agendaBookingSuccess', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).agendaBookingSuccess, 'Reserva confirmada.');
    });

    testWidgets('agendaBookingRaceError', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).agendaBookingRaceError,
          'Ese horario fue reservado justo ahora. Probá con otro.');
    });

    testWidgets('agendaCancellationConfirmTitle', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).agendaCancellationConfirmTitle, 'Cancelar reserva');
    });

    testWidgets('agendaCancellationConfirmBody', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).agendaCancellationConfirmBody, '¿Cancelar esta reserva?');
    });

    testWidgets('agendaCancellationConfirmCta', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).agendaCancellationConfirmCta, 'Sí, cancelar');
    });

    testWidgets('agendaCancellationKeep', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).agendaCancellationKeep, 'No, mantener');
    });

    testWidgets('agendaCancellationSuccess', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).agendaCancellationSuccess, 'Reserva cancelada.');
    });

    testWidgets('agendaCancellationTooLate', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).agendaCancellationTooLate,
          'No podés cancelar con menos de 24h de anticipación.');
    });

    testWidgets('agendaUpcomingAppointmentsHeading', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(
          _l10n(t).agendaUpcomingAppointmentsHeading, 'TUS PRÓXIMAS RESERVAS');
    });

    testWidgets('agendaPastAppointmentsHeading', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).agendaPastAppointmentsHeading, 'TURNOS PASADOS');
    });

    testWidgets('agendaGenericError', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(
          _l10n(t).agendaGenericError, 'Hubo un problema. Intentá de nuevo.');
    });

    testWidgets('agendaTrainerEmptyAvailability', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(
        _l10n(t).agendaTrainerEmptyAvailability,
        'Todavía no configuraste tus horarios de trabajo. '
            'Agregá uno para que tus alumnos puedan reservar.',
      );
    });

    testWidgets('agendaConfigureHoursCta', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).agendaConfigureHoursCta, 'CONFIGURAR HORARIOS');
    });

    testWidgets('agendaMyWorkingHoursHeading', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).agendaMyWorkingHoursHeading, 'MIS HORARIOS DE TRABAJO');
    });

    testWidgets('agendaAddRuleCta', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).agendaAddRuleCta, 'AGREGAR HORARIO');
    });

    testWidgets('agendaBlockDayCta', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).agendaBlockDayCta, 'BLOQUEAR UN DÍA');
    });

    testWidgets('agendaEditorTitle', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).agendaEditorTitle, 'Mis horarios');
    });

    testWidgets('agendaRuleDeleteConfirm', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).agendaRuleDeleteConfirm,
          '¿Borrar este horario? Las reservas existentes se mantienen.');
    });

    testWidgets('agendaBookingCancelledByCoach', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).agendaBookingCancelledByCoach,
          'Reserva cancelada por el entrenador.');
    });

    testWidgets('agendaSlotFreeLabel', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).agendaSlotFreeLabel, 'Disponible');
    });

    testWidgets('agendaSlotBlockedLabel', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).agendaSlotBlockedLabel, 'Bloqueado');
    });

    testWidgets('agendaSlotBookedByLabel — ICU interpolation', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(_l10n(t).agendaSlotBookedByLabel('Martín'),
          'Reservado por Martín');
    });
  });
}
