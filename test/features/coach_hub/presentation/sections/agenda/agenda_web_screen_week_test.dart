// PR-D — Cableado de la vista SEMANA en AgendaWebScreen.
//
// Los ocho archivos de test previos de agenda quedan intactos: corren en el
// viewport default (800px) y por lo tanto en el branch ANGOSTO, donde ni el
// toggle ni la grilla existen. Todo lo de PR-D vive acá.
//
// Todas las strings son español hardcodeado + comentario // i18n (C-6). Sin
// AppL10n: los delegates de flutter_localizations alcanzan, y son los que
// inicializan los datos de locale que TableCalendar('es') necesita.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/utils/appointment_window.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach_hub/presentation/sections/agenda/agenda_web_screen.dart';
import 'package:treino/features/coach_hub/presentation/sections/agenda/agenda_web_week_grid.dart';
import 'package:treino/features/payments/application/billing_providers.dart';
import 'package:treino/features/payments/domain/athlete_billing.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;

// ─── Constantes y fixtures ────────────────────────────────────────────────────

const _kTrainerId = 'trainer-web-week';
const _kAthleteId = 'athlete-web-week';

/// Ventana rodante: la MISMA que calcula la pantalla en `initState`.
final _kWindow = rollingAppointmentWindow(DateTime.now().toUtc());

/// Los siete nombres de día que dibuja el encabezado de la grilla.
const _kWeekdayNames = [
  'Lunes', // i18n
  'Martes', // i18n
  'Miércoles', // i18n
  'Jueves', // i18n
  'Viernes', // i18n
  'Sábado', // i18n
  'Domingo', // i18n
];

// ─── Harness ──────────────────────────────────────────────────────────────────

/// Setea el viewport lógico. El `devicePixelRatio = 1.0` NO es opcional: sin
/// él, 1280×900 físicos son 426×300 lógicos y el test ejercita en silencio otro
/// layout (el angosto, justamente el que NO tiene vista semana).
void _setViewport(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

List<Override> _overrides({List<Appointment> appointments = const []}) => [
      currentUidProvider.overrideWithValue(_kTrainerId),
      // Override FAMILY-WIDE: la key incluye la ventana rodante derivada de
      // DateTime.now(), así que un override por key exacta es inestable.
      trainerAppointmentsStreamProvider.overrideWith(
        (ref, key) => Stream.value(appointments),
      ),
      trainerLinksStreamProvider.overrideWith(
        (ref) => Stream.value(const <TrainerLink>[]),
      ),
      userPublicProfileProvider(_kAthleteId)
          .overrideWith((ref) => Stream.value(null)),
      athleteBillingProvider(_kAthleteId).overrideWith(
        (ref) => Stream<AthleteBilling?>.value(null),
      ),
    ];

/// El shell (CoachHubScaffold) provee Scaffold y SafeArea — acá va el Scaffold
/// mínimo y nada más (ADR-CHW-005).
Widget _wrap({List<Appointment> appointments = const []}) => ProviderScope(
      overrides: _overrides(appointments: appointments),
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('es'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('es'), Locale('en')],
        home: const Scaffold(body: AgendaWebScreen()),
      ),
    );

Future<void> _toWeek(WidgetTester tester) async {
  await tester.tap(find.text('SEMANA')); // i18n
  await tester.pumpAndSettle();
}

/// Título del encabezado del panel (el único texto en MAYÚSCULAS que arranca
/// con "SEMANA DEL").
String _headerTitle(WidgetTester tester) => tester
    .widgetList<Text>(find.textContaining('SEMANA DEL')) // i18n
    .first
    .data!;

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // ─── Toggle DÍA / SEMANA ────────────────────────────────────────────────────

  group('toggle de vista', () {
    testWidgets(
      'pasar a SEMANA monta la grilla con los siete días y desmonta el '
      'mini-calendario',
      (tester) async {
        _setViewport(tester, 1280);
        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();

        // Punto de partida: DÍA, con el calendario de table_calendar.
        expect(find.byType(TableCalendar<dynamic>), findsOneWidget);
        expect(find.byType(AgendaWebWeekGrid), findsNothing);

        await _toWeek(tester);

        expect(find.byType(AgendaWebWeekGrid), findsOneWidget);
        // El mini-calendario de 420px se esconde: si no, las columnas quedan
        // en ~86px a 1440 de viewport.
        expect(find.byType(TableCalendar<dynamic>), findsNothing);
        for (final name in _kWeekdayNames) {
          expect(find.text(name), findsOneWidget, reason: 'falta $name');
        }
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('volver a DÍA restaura el calendario y la lista del día',
        (tester) async {
      _setViewport(tester, 1280);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await _toWeek(tester);
      expect(find.byType(AgendaWebWeekGrid), findsOneWidget);

      await tester.tap(find.text('DÍA')); // i18n
      await tester.pumpAndSettle();

      expect(find.byType(AgendaWebWeekGrid), findsNothing);
      expect(find.byType(TableCalendar<dynamic>), findsOneWidget);
      expect(find.text('No hay sesiones este día.'), findsOneWidget); // i18n
    });

    testWidgets('tocar el encabezado de una columna vuelve a DÍA con ese día',
        (tester) async {
      _setViewport(tester, 1280);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await _toWeek(tester);
      await tester.tap(find.text('Jueves')); // i18n
      await tester.pumpAndSettle();

      expect(find.byType(AgendaWebWeekGrid), findsNothing);
      expect(find.byType(TableCalendar<dynamic>), findsOneWidget);
      // El día del encabezado del panel es el jueves que se tocó.
      expect(find.textContaining('JUEVES'), findsOneWidget); // i18n
    });

    testWidgets('los dos chips del toggle cumplen el target de 44pt',
        (tester) async {
      _setViewport(tester, 1280);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      for (final label in ['DÍA', 'SEMANA']) {
        final size = tester.getSize(
          find
              .ancestor(
                of: find.text(label), // i18n
                matching: find.byType(GestureDetector),
              )
              .first,
        );
        expect(size.height, greaterThanOrEqualTo(44.0), reason: '$label alto');
        expect(size.width, greaterThanOrEqualTo(44.0), reason: '$label ancho');
      }
    });
  });

  // ─── Accesibilidad del toggle ───────────────────────────────────────────────

  group('accesibilidad del toggle', () {
    testWidgets('cada chip es un botón con estado seleccionado y acción de tap',
        (tester) async {
      final handle = tester.ensureSemantics();
      _setViewport(tester, 1280);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.bySemanticsLabel('Vista día')), // i18n
        isSemantics(isButton: true, isSelected: true, hasTapAction: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Vista semana')), // i18n
        isSemantics(isButton: true, isSelected: false, hasTapAction: true),
      );

      await _toWeek(tester);

      expect(
        tester.getSemantics(find.bySemanticsLabel('Vista semana')), // i18n
        isSemantics(isButton: true, isSelected: true, hasTapAction: true),
      );

      handle.dispose();
    });
  });

  // ─── Navegación de semana ───────────────────────────────────────────────────

  group('navegación de semana', () {
    testWidgets('› corre la semana siete días', (tester) async {
      _setViewport(tester, 1280);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _toWeek(tester);

      final before = _headerTitle(tester);
      await tester.tap(find.byTooltip('Semana siguiente')); // i18n
      await tester.pumpAndSettle();
      final after = _headerTitle(tester);

      expect(after, isNot(equals(before)));
      expect(
        after,
        equals(
          weekRangeLabel(DateTime.now().add(const Duration(days: 7)))
              .toUpperCase(),
        ),
      );
    });

    testWidgets(
      '‹ no puede salir de la ventana del stream: clampea en _rangeFrom',
      (tester) async {
        _setViewport(tester, 1280);
        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();
        await _toWeek(tester);

        // La ventana arranca el 1° del mes anterior: como mucho ~9 semanas
        // atrás. Veinte taps garantizan tocar el borde.
        for (var i = 0; i < 20; i++) {
          await tester.tap(find.byTooltip('Semana anterior')); // i18n
          await tester.pumpAndSettle();
        }

        final clamped = weekRangeLabel(_kWindow.from).toUpperCase();
        expect(_headerTitle(tester), equals(clamped));

        // Un tap más NO mueve nada: sin el clamp, el PF terminaría mirando una
        // grilla vacía indistinguible de una semana sin turnos.
        await tester.tap(find.byTooltip('Semana anterior')); // i18n
        await tester.pumpAndSettle();
        expect(_headerTitle(tester), equals(clamped));
      },
    );
  });

  // ─── Branch angosto ─────────────────────────────────────────────────────────

  group('branch angosto', () {
    testWidgets('a 800px no hay toggle ni grilla', (tester) async {
      _setViewport(tester, 800);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.text('SEMANA'), findsNothing); // i18n
      expect(find.text('DÍA'), findsNothing); // i18n
      expect(find.byType(AgendaWebWeekGrid), findsNothing);
      expect(find.byType(TableCalendar<dynamic>), findsOneWidget);
    });

    testWidgets(
      'achicar la ventana con SEMANA activa resetea el modo a DÍA (al '
      'ensanchar de nuevo NO reaparece la grilla)',
      (tester) async {
        _setViewport(tester, 1280);
        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();
        await _toWeek(tester);
        expect(find.byType(AgendaWebWeekGrid), findsOneWidget);

        tester.view.physicalSize = const Size(800, 900);
        await tester.pumpAndSettle();
        expect(find.byType(AgendaWebWeekGrid), findsNothing);

        tester.view.physicalSize = const Size(1280, 900);
        await tester.pumpAndSettle();

        expect(find.byType(AgendaWebWeekGrid), findsNothing);
        expect(find.byType(TableCalendar<dynamic>), findsOneWidget);
      },
    );
  });

  // ─── Encabezado a lo ancho ──────────────────────────────────────────────────

  group('encabezado', () {
    testWidgets(
      'en el umbral de 900px el encabezado no desborda ni en DÍA ni en SEMANA',
      (tester) async {
        _setViewport(tester, 900);
        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();

        // Un RenderFlex overflow es una excepción en widget tests.
        expect(tester.takeException(), isNull);

        await _toWeek(tester);
        expect(tester.takeException(), isNull);
        expect(find.byType(AgendaWebWeekGrid), findsOneWidget);
      },
    );
  });
}
