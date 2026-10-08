import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/presentation/widgets/day_timeline.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

// El bloque de una sesión mide lo que dura la sesión (64 px por hora), y el
// texto de adentro se mostraba con umbrales en píxeles SIN escalar: con la
// letra al máximo de accesibilidad (≈3,1×) el bloque de una hora desbordaba
// 98 px y el texto pisaba las horas siguientes (visto en el iPhone 17e,
// 2026-10-02).
//
// Estos tests no miden anchos ni cortes de línea: `google_fonts` no carga en
// `flutter_test` y mide con la fuente de fallback, más ancha. Lo que fijan es
// estructural — que el bloque no desborde a ninguna escala —, y la fuente de
// fallback, si algo, hace el texto MÁS alto, o sea que el rojo sale más fácil.

final _dia = DateTime(2026, 10, 2);
final _desde = DateTime(2026, 10, 1);
final _hasta = DateTime(2026, 10, 31);

Appointment _sesion({
  required String id,
  required int hora,
  required int minutos,
}) =>
    Appointment(
      id: id,
      trainerId: 'trainer-1',
      athleteId: 'athlete-$id',
      athleteDisplayName: 'Sofía Ramírez',
      // ADR-7: los campos UTC son la hora de reloj.
      startsAt: DateTime.utc(_dia.year, _dia.month, _dia.day, hora),
      durationMin: minutos,
      status: AppointmentStatus.confirmed,
    );

Widget _timeline(TextScaler textScaler, List<Appointment> sesiones) {
  return ProviderScope(
    overrides: [
      trainerAppointmentsStreamProvider
          .overrideWith((ref, key) => Stream.value(sesiones)),
      userPublicProfileProvider.overrideWith((ref, uid) => Stream.value(null)),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: Scaffold(
        body: DayTimeline(
          trainerId: 'trainer-1',
          day: _dia,
          rangeFrom: _desde,
          rangeTo: _hasta,
        ),
      ),
    ),
  );
}

void _iphone17e(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets(
      'con la letra al máximo, los bloques de 60 y de 30 minutos no desbordan',
      (tester) async {
    _iphone17e(tester);
    await tester.pumpWidget(_timeline(
      const TextScaler.linear(3.1),
      [
        _sesion(id: 'una-hora', hora: 17, minutos: 60),
        _sesion(id: 'media-hora', hora: 10, minutos: 30),
      ],
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // La hora de inicio es lo único que se muestra siempre: si no entra, se
    // achica, pero no desaparece. Cada una aparece dos veces: el rótulo de la
    // grilla en el costado y el bloque (el último, porque la grilla se arma
    // antes que los bloques).
    for (final hora in ['17:00', '10:00']) {
      expect(find.text(hora), findsNWidgets(2));
      final enElBloque = find.text(hora).last;
      final bloque = tester.getRect(
        find.ancestor(of: enElBloque, matching: find.byType(Positioned)).first,
      );
      // Achicado, no recortado. Un párrafo recortado se maqueta al alto que
      // le dan, así que su rect «entra» en el bloque igual: lo que lo delata
      // es que quedó más bajo que el alto que necesita su texto.
      final parrafo = tester.renderObject<RenderParagraph>(enElBloque);
      expect(
        parrafo.size.height,
        greaterThanOrEqualTo(
          parrafo.getMinIntrinsicHeight(parrafo.size.width) - 0.5,
        ),
        reason: '$hora quedó recortada en vez de achicada',
      );
      // Y achicado lo suficiente: getBottomRight aplica la transformación del
      // FittedBox (getRect no).
      final esquina = tester.getBottomRight(enElBloque);
      expect(
        esquina.dy,
        lessThanOrEqualTo(bloque.bottom),
        reason: '$hora no entra en el bloque $bloque: termina en $esquina',
      );
    }
  });

  testWidgets(
      'a xLarge (1,12×) el bloque de una hora sigue mostrando la hora de fin',
      (tester) async {
    // La primera versión del arreglo escalaba también la holgura del 60 y
    // escondía el fin desde 1,08×, aunque entrara hasta ~1,3×.
    _iphone17e(tester);
    await tester.pumpWidget(_timeline(
      const TextScaler.linear(1.12),
      [_sesion(id: 'una-hora', hora: 17, minutos: 60)],
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Sofía Ramírez'), findsOneWidget);
    // Rótulo de la grilla + fin de la sesión.
    expect(find.text('18:00'), findsNWidgets(2));
  });

  testWidgets('a escala 1 el bloque de una hora sigue mostrando nombre y fin',
      (tester) async {
    _iphone17e(tester);
    await tester.pumpWidget(_timeline(
      TextScaler.noScaling,
      [_sesion(id: 'una-hora', hora: 17, minutos: 60)],
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Rótulo de la grilla + bloque.
    expect(find.text('17:00'), findsNWidgets(2));
    expect(find.text('Sofía Ramírez'), findsOneWidget);
    expect(find.text('18:00'), findsNWidgets(2));
  });
}
