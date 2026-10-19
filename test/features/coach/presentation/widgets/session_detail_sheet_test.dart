// #1492 — el detalle de sesión del PF en la agenda mobile.
//
// El hallazgo de QA: en una sesión de hoy el PF veía «No se puede cancelar
// (menos de 24h)». La regla de 24 h es del ATLETA; aplicada al PF lo dejaba
// sin forma de avisar que no podía ir. Y una vez pasada la sesión no había
// cómo decir que el alumno faltó.
//
// `isPast` lo calcula el llamador (day_timeline / trainer_day_detail_sheet) y
// significa "ya empezó", así que estos tests no dependen del reloj.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/application/athlete_note_providers.dart';
import 'package:treino/features/coach/data/appointment_repository.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/presentation/widgets/session_detail_sheet.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

const _kTrainerId = 'trainer-1492';

Appointment _appt(String id, {String? recurringId}) => Appointment(
      id: id,
      trainerId: _kTrainerId,
      athleteId: 'athlete-1492',
      athleteDisplayName: 'Ana López',
      startsAt: DateTime.utc(2026, 7, 1, 10, 0),
      durationMin: 60,
      status: AppointmentStatus.confirmed,
      recurringId: recurringId,
    );

Widget _wrap({
  required Appointment appointment,
  required FakeFirebaseFirestore firestore,
  required bool isPast,
}) =>
    ProviderScope(
      overrides: [
        appointmentRepositoryProvider.overrideWithValue(
          AppointmentRepository(firestore: firestore),
        ),
        userPublicProfileProvider
            .overrideWith((ref, uid) => Stream.value(null)),
        athleteNoteProvider.overrideWith((ref, key) => Stream.value(null)),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => SessionDetailSheet(
                  appointment: appointment,
                  trainerId: _kTrainerId,
                  isPast: isPast,
                ),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() => firestore = FakeFirebaseFirestore());

  Future<Appointment> seed(Appointment a) async {
    await firestore.collection('appointments').doc(a.id).set(a.toJson());
    return a;
  }

  Future<Map<String, Object?>> docOf(String id) async =>
      (await firestore.collection('appointments').doc(id).get()).data()!;

  testWidgets('antes de empezar el PF cancela, sin la regla de 24 h',
      (tester) async {
    final appt = await seed(_appt('s-1492-cancel'));
    await tester.pumpWidget(
      _wrap(appointment: appt, firestore: firestore, isPast: false),
    );
    await _tap(tester, find.text('abrir'));

    expect(find.text('No se puede cancelar (menos de 24h).'), findsNothing);
    expect(find.text('MARCAR AUSENTE'), findsNothing);

    await _tap(tester, find.text('CANCELAR RESERVA'));
    await _tap(tester, find.text('Sí, cancelar'));

    final data = await docOf(appt.id);
    expect(data['status'], 'cancelled');
    expect(data['cancelledBy'], _kTrainerId);
  });

  testWidgets('empezada: no hay CANCELAR; MARCAR AUSENTE escribe y se deshace',
      (tester) async {
    final appt = await seed(_appt('s-1492-ausente'));
    await tester.pumpWidget(
      _wrap(appointment: appt, firestore: firestore, isPast: true),
    );
    await _tap(tester, find.text('abrir'));

    expect(find.text('CANCELAR RESERVA'), findsNothing);

    await _tap(tester, find.text('MARCAR AUSENTE'));
    expect((await docOf(appt.id))['attendance'], 'absent');
    expect(find.text('Marcaste que el alumno faltó.'), findsOneWidget);

    await _tap(tester, find.text('DESHACER AUSENTE'));
    expect((await docOf(appt.id))['attendance'], isNull);
  });

  testWidgets('la serie se cancela entera, aunque ésta falte menos de 24 h',
      (tester) async {
    final appt = await seed(_appt('s-1492-serie', recurringId: 'serie-1492'));
    await tester.pumpWidget(
      _wrap(appointment: appt, firestore: firestore, isPast: false),
    );
    await _tap(tester, find.text('abrir'));

    expect(
      find.textContaining('todavía no empezaron'),
      findsNothing,
      reason: 'el texto vive en el diálogo de confirmación',
    );
    await _tap(tester, find.text('CANCELAR TODA LA SERIE'));
    expect(find.textContaining('todavía no empezaron'), findsOneWidget);
    expect(find.textContaining('más de 24h'), findsNothing);
  });
}
