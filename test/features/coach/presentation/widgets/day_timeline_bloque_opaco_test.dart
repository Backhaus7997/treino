import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/presentation/widgets/day_timeline.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

// #1491: la grilla de la agenda se dibuja ANTES que los bloques, pero el
// relleno de la sesión era un tinte translúcido (alpha 30), así que la línea
// de media hora se veía cruzando el nombre del alumno. El relleno tiene que
// ser opaco: el mismo tinte, ya mezclado con el fondo de la pantalla.

final _dia = DateTime(2026, 10, 2);

Widget _timeline() {
  final sesion = Appointment(
    id: 'a1',
    trainerId: 'trainer-1',
    athleteId: 'athlete-1',
    athleteDisplayName: 'Sofía Ramírez',
    // ADR-7: los campos UTC son la hora de reloj.
    startsAt: DateTime.utc(_dia.year, _dia.month, _dia.day, 17),
    durationMin: 60,
    status: AppointmentStatus.confirmed,
  );
  return ProviderScope(
    overrides: [
      trainerAppointmentsStreamProvider
          .overrideWith((ref, key) => Stream.value([sesion])),
      userPublicProfileProvider.overrideWith((ref, uid) => Stream.value(null)),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(
        body: DayTimeline(
          trainerId: 'trainer-1',
          day: _dia,
          rangeFrom: DateTime(2026, 10, 1),
          rangeTo: DateTime(2026, 10, 31),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('el relleno del bloque de una sesión es opaco', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_timeline());
    await tester.pumpAndSettle();

    // El texto de la hora aparece dos veces: el rótulo de la grilla y el
    // bloque (el último, porque la grilla se arma antes).
    final enElBloque = find.text('17:00').last;
    final rellenos = tester
        .widgetList<Container>(
          find.ancestor(of: enElBloque, matching: find.byType(Container)),
        )
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.borderRadius == BorderRadius.circular(8))
        .map((d) => d.color)
        .toList();

    expect(rellenos, hasLength(1), reason: 'no encontré el relleno del bloque');
    expect(
      rellenos.single!.a,
      1.0,
      reason: 'translúcido: la grilla se ve a través de la sesión',
    );
  });
}
