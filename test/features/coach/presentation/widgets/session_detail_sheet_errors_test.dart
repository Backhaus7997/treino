import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/utils/app_clock.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/application/athlete_note_providers.dart';
import 'package:treino/features/coach/data/appointment_repository.dart';
import 'package:treino/features/coach/domain/agenda_exceptions.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/presentation/widgets/session_detail_sheet.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

// Los avisos del SessionDetailSheet (guardar notas / cancelar) se mostraban
// con un SnackBar. El sheet se abre con `useRootNavigator: true` desde la
// grilla del día, o sea POR ENCIMA del Scaffold donde se dibuja el SnackBar: el
// PF tocaba la acción y no veía nada. Estos tests fijan que el aviso esté
// adentro del sheet, a la vista.

const _trainerId = 'trainer-1';
const _athleteId = 'athlete-1';

/// Repo cuyas escrituras fallan con [error].
class _FailingRepository extends Fake implements AppointmentRepository {
  _FailingRepository(this.error);

  final Object error;

  @override
  Future<void> updateNotes({
    required String appointmentId,
    String? noteBefore,
    String? noteAfter,
  }) async {
    throw error;
  }

  @override
  Future<void> cancel({
    required Appointment appointment,
    required String actorUid,
    String? reason,
    DateTime? now,
  }) async {
    throw error;
  }

  @override
  Future<int> cancelFutureSeries({
    required String recurringId,
    required String trainerId,
    required String actorUid,
    String? reason,
    DateTime? now,
  }) async {
    throw error;
  }
}

Appointment _appt({String? recurringId}) => Appointment(
      id: 'appt-1',
      trainerId: _trainerId,
      athleteId: _athleteId,
      athleteDisplayName: 'Ana López',
      // 1/7/2026 10:00 (wall-clock): a más de 24h del reloj congelado.
      startsAt: DateTime.utc(2026, 7, 1, 10),
      durationMin: 60,
      status: AppointmentStatus.confirmed,
      recurringId: recurringId,
    );

Widget _wrap(AppointmentRepository repo, Appointment appointment) {
  return ProviderScope(
    overrides: [
      appointmentRepositoryProvider.overrideWithValue(repo),
      userPublicProfileProvider(_athleteId)
          .overrideWith((ref) => Stream.value(null)),
      athleteNoteProvider((trainerId: _trainerId, athleteId: _athleteId))
          .overrideWith((ref) => Stream.value(null)),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(
        body: SessionDetailSheet(
          appointment: appointment,
          trainerId: _trainerId,
          isPast: false,
        ),
      ),
    ),
  );
}

/// Un aviso a la vista: descendiente del sheet, sin nada encima y sin SnackBar.
void _expectAvisoAdentro(WidgetTester tester, String texto) {
  final aviso = find.text(texto);
  expect(
    find.descendant(
      of: find.byType(SessionDetailSheet),
      matching: aviso,
    ),
    findsOneWidget,
  );
  expect(aviso.hitTestable(), findsOneWidget);
  expect(find.byType(SnackBar), findsNothing);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => AppClock.freeze(DateTime(2026, 6, 1, 10)));
  tearDown(AppClock.unfreeze);

  testWidgets('guardar notas falla: el aviso va adentro del sheet',
      (tester) async {
    await tester
        .pumpWidget(_wrap(_FailingRepository(Exception('red')), _appt()));
    await tester.pumpAndSettle();

    await _tap(tester, find.text('GUARDAR NOTAS'));

    _expectAvisoAdentro(tester, 'No pudimos guardar. Probá de nuevo.');
    // Puede reintentar: el botón volvió a estar habilitado.
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'GUARDAR NOTAS'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('cancelar falla (genérico): el aviso va adentro', (tester) async {
    final l10n = await AppL10n.delegate.load(const Locale('es', 'AR'));
    await tester
        .pumpWidget(_wrap(_FailingRepository(Exception('red')), _appt()));
    await tester.pumpAndSettle();

    await _tap(tester, find.text('CANCELAR RESERVA'));
    await _tap(tester, find.text(l10n.agendaCancellationConfirmCta));

    _expectAvisoAdentro(tester, l10n.agendaGenericError);
  });

  testWidgets('cancelar con menos de 24h: el aviso va adentro', (tester) async {
    final l10n = await AppL10n.delegate.load(const Locale('es', 'AR'));
    await tester.pumpWidget(_wrap(
      _FailingRepository(const CancellationTooLateException('appt-1')),
      _appt(),
    ));
    await tester.pumpAndSettle();

    await _tap(tester, find.text('CANCELAR RESERVA'));
    await _tap(tester, find.text(l10n.agendaCancellationConfirmCta));

    _expectAvisoAdentro(tester, l10n.agendaCancellationTooLate);
  });

  testWidgets('cancelar la serie falla: el aviso va adentro', (tester) async {
    final l10n = await AppL10n.delegate.load(const Locale('es', 'AR'));
    await tester.pumpWidget(_wrap(
      _FailingRepository(Exception('red')),
      _appt(recurringId: 'serie-1'),
    ));
    await tester.pumpAndSettle();

    await _tap(tester, find.text('CANCELAR TODA LA SERIE'));
    await _tap(tester, find.text('Cancelar serie'));

    _expectAvisoAdentro(tester, l10n.agendaGenericError);
  });

  testWidgets('el aviso se limpia al reintentar una acción', (tester) async {
    final l10n = await AppL10n.delegate.load(const Locale('es', 'AR'));
    await tester
        .pumpWidget(_wrap(_FailingRepository(Exception('red')), _appt()));
    await tester.pumpAndSettle();

    await _tap(tester, find.text('GUARDAR NOTAS'));
    expect(find.text('No pudimos guardar. Probá de nuevo.'), findsOneWidget);

    // Otra acción: el aviso viejo no puede quedar pegado junto al nuevo.
    await _tap(tester, find.text('CANCELAR RESERVA'));
    await _tap(tester, find.text(l10n.agendaCancellationConfirmCta));

    expect(find.text('No pudimos guardar. Probá de nuevo.'), findsNothing);
    expect(find.text(l10n.agendaGenericError), findsOneWidget);
  });
}
