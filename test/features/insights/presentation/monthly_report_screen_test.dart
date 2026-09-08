import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/utils/date_labels.dart';
import 'package:mocktail/mocktail.dart';

import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/utils/app_clock.dart';
import 'package:treino/core/utils/argentina_time.dart';
import 'package:treino/features/insights/presentation/monthly_report_screen.dart';
import 'package:treino/features/insights/presentation/widgets/monthly_report_chart.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../workout/application/stub_factories.dart';

class MockSessionRepository extends Mock implements SessionRepository {}

/// Reloj congelado del archivo: **miércoles 16/09/2026, 10:30**.
///
/// Este archivo rompió `main` DOS VECES por leerle la fecha al runner, y las
/// dos veces sin que cambiara una línea de código:
///
///   1. **01/09/2026** — el label del radar se comparaba con
///      `DateFormat('MMM yyyy')`, que en es-AR devuelve `sept` (4 chars) sólo
///      para septiembre. Los otros once meses coincidían de casualidad. Se
///      arregló el formato (`monthAbbrev`), no la causa: el test seguía
///      preguntándole la fecha al reloj.
///   2. **08/09/2026** — el fixture de la racha armaba "hoy" y "ayer" con el
///      reloj real. El lunes 07 los dos caían en semanas ART distintas y la
///      racha valía 1; el martes 08 caen en la misma y vale 2. Verde un día,
///      rojo al siguiente, con `main` bloqueado en el medio.
///
/// Un test que pasa o falla según el día no prueba nada — dice la verdad por
/// casualidad. Ahora el reloj es un dato del test: [AppClock] es el seam que
/// ya leen `argentinaNow()` y el default de `computeWeeklyStreak`, así que
/// congelarlo acá congela TODO el camino de render de esta pantalla.
///
/// **Miércoles a propósito**: con "hoy" en lunes, "ayer" cae en la semana ART
/// anterior y el fixture de la racha cambia de significado. Un día del medio
/// de la semana deja margen por los dos lados.
///
/// **Septiembre a propósito**: es el mes que rompió el CI el 01/09. Anclado
/// acá, un `DateFormat('MMM')` que se vuelva a colar falla SIEMPRE en vez de
/// una vez al año.
DateTime get _frozenNow => DateTime(2026, 9, 16, 10, 30);

/// Mediodía UTC del día [y]-[m]-[d], para usar como `Session.startedAt`.
///
/// **UTC-flagged y no local**: `startedAt` llega siempre UTC desde el
/// `TimestampConverter`, y los agregadores lo bucketean con `toArgentina()`,
/// que resta 3h sin mirar el flag. Un `DateTime(y, m, d)` local se corre al
/// día ANTERIOR — y en el día 1 de un mes, al mes anterior. Mediodía deja
/// ±12h de margen, así que el bucket ART no depende de la timezone del runner.
DateTime _utcNoon(int y, int m, int d) => DateTime.utc(y, m, d, 12);

void main() {
  setUpAll(() {
    registerFallbackValue(makeSession());
    registerFallbackValue(makeSetLog());
  });

  setUp(() => AppClock.freeze(_frozenNow));
  tearDown(AppClock.unfreeze);

  Widget wrap(
    Widget child, {
    required List<Override> overrides,
    DateTime? initialMonth,
  }) =>
      ProviderScope(
        overrides: [
          // Defaults so the month-vs-month radar section (AD6/PR5c) doesn't
          // hit real Firebase resolving routines/exercises — individual
          // tests can still override these explicitly if needed.
          exercisesProvider.overrideWith((ref) async => []),
          visibleRoutineByIdProvider('r1').overrideWith((ref) async => null),
          ...overrides,
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
          home: Scaffold(
            body: MonthlyReportScreen(uid: 'u1', initialMonth: initialMonth),
          ),
        ),
      );

  testWidgets('renders chart + summary cards when data loads', (tester) async {
    final repo = MockSessionRepository();
    final now = _frozenNow;
    when(() => repo.listByUid('u1', limit: any(named: 'limit')))
        .thenAnswer((_) async => [
              makeSession(
                id: 's1',
                startedAt: _utcNoon(now.year, now.month, now.day),
                status: SessionStatus.finished,
                wasFullyCompleted: true,
                durationMin: 45,
              ),
            ]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's1'))
        .thenAnswer((_) async => [makeSetLog()]);

    await tester.pumpWidget(wrap(
      const SizedBox.shrink(),
      overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
    ));
    await tester.pumpAndSettle();

    expect(find.text('REPORTE MENSUAL'), findsOneWidget);
    expect(find.text('Entrenos'), findsWidgets);
    expect(find.text('Duración'), findsWidgets);
  });

  testWidgets(
      'Duration cross-check: the summary card sums Session.durationMin '
      'consistently for the selected month, matching the aggregator '
      '(AD6/PR5c pinning test — not just presence of the label)',
      (tester) async {
    final repo = MockSessionRepository();
    // [#379] Anchor in the Argentina frame (as the aggregator does via
    // argentinaNow()) and store startedAt as real UTC instants at NOON on
    // mid-month days: `toArgentina` shifts by -3h, so day-1 LOCAL midnight would
    // spill into the PREVIOUS month and drop the session — noon mid-month keeps
    // the Argentina calendar month unambiguous and TZ-independent.
    final now = argentinaNow();

    when(() => repo.listByUid('u1', limit: any(named: 'limit')))
        .thenAnswer((_) async => [
              makeSession(
                id: 's1',
                startedAt: DateTime.utc(now.year, now.month, 10, 12),
                status: SessionStatus.finished,
                wasFullyCompleted: true,
                durationMin: 40,
              ),
              makeSession(
                id: 's2',
                startedAt: DateTime.utc(now.year, now.month, 11, 12),
                status: SessionStatus.finished,
                wasFullyCompleted: true,
                durationMin: 25,
              ),
              // A non-finished session's duration must NOT be counted.
              makeSession(
                id: 's3',
                startedAt: DateTime.utc(now.year, now.month, 12, 12),
                status: SessionStatus.active,
                durationMin: 999,
              ),
            ]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: any(named: 'sessionId')))
        .thenAnswer((_) async => [makeSetLog()]);

    await tester.pumpWidget(wrap(
      const SizedBox.shrink(),
      overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
    ));
    await tester.pumpAndSettle();

    // 40 + 25 = 65 min = 1.1 h — active session's 999 must be excluded.
    expect(find.text('1.1'), findsOneWidget);
    expect(find.text('h'), findsOneWidget);
  });

  testWidgets('shows error state + retry on load failure', (tester) async {
    final repo = MockSessionRepository();
    when(() => repo.listByUid('u1', limit: any(named: 'limit')))
        .thenThrow(Exception('boom'));

    await tester.pumpWidget(wrap(
      const SizedBox.shrink(),
      overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
    ));
    await tester.pumpAndSettle();

    expect(
      find.text('No pudimos cargar tu reporte mensual. Probá de nuevo.'),
      findsOneWidget,
    );
    expect(find.text('Reintentar'), findsOneWidget);
  });

  // QA-498: `ref.invalidate` NO cascada a las dependencias, y exercisesProvider
  // NO es autoDispose — cachea su AsyncError para toda la vida del container.
  // Invalidando SOLO el provider del radar se re-leía el MISMO error del
  // catálogo: un botón que no podía recuperar justo el caso que trae al usuario
  // acá (catálogo frío que falló / offline).
  testWidgets(
      'QA-498: Reintentar en el radar RECUPERA — re-fetchea el catálogo, '
      'no repite su error cacheado', (tester) async {
    final repo = MockSessionRepository();
    final now = _frozenNow;
    when(() => repo.listByUid('u1', limit: any(named: 'limit')))
        .thenAnswer((_) async => [
              makeSession(
                id: 's1',
                startedAt: _utcNoon(now.year, now.month, now.day),
                status: SessionStatus.finished,
                wasFullyCompleted: true,
                routineId: 'r1',
              ),
            ]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's1'))
        .thenAnswer((_) async => [makeSetLog(id: 'l1', exerciseId: 'e-chest')]);

    // El catálogo falla en frío una vez y después anda.
    var catalogAttempts = 0;

    await tester.pumpWidget(wrap(
      const SizedBox.shrink(),
      overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
        exercisesProvider.overrideWith((ref) async {
          catalogAttempts++;
          if (catalogAttempts == 1) throw Exception('catalogue fetch failed');
          return [
            const Exercise(
              id: 'e-chest',
              name: 'Press',
              muscleGroup: 'chest',
              category: 'compound',
            ),
          ];
        }),
      ],
    ));
    await tester.pumpAndSettle();

    // El radar vive al fondo del scroll: hay que llegar hasta él para que se
    // construya (mismo criterio que el test del legend del radar).
    await tester.scrollUntilVisible(
      find.text('Reintentar'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // El radar cayó en error (las sesiones sí cargaron).
    expect(find.text('Reintentar'), findsOneWidget);

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(
      catalogAttempts,
      2,
      reason: 'el retry debe re-fetchear el catálogo, no repetir su error '
          'cacheado (sin el fix queda en 1)',
    );
  });

  testWidgets('switching to POR DÍA renders the daily duration chart',
      (tester) async {
    final repo = MockSessionRepository();
    final now = _frozenNow;
    final today = _utcNoon(now.year, now.month, now.day);

    when(() => repo.listByUid('u1', limit: any(named: 'limit')))
        .thenAnswer((_) async => [
              makeSession(
                id: 's1',
                startedAt: today,
                status: SessionStatus.finished,
                wasFullyCompleted: true,
                durationMin: 45,
              ),
            ]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: any(named: 'sessionId')))
        .thenAnswer((_) async => [makeSetLog()]);

    await tester.pumpWidget(wrap(
      const SizedBox.shrink(),
      overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('POR DÍA'));
    await tester.pumpAndSettle();

    expect(find.byType(DailyDurationChart), findsOneWidget);
  });

  testWidgets(
      'renders the workout-days streak calendar below the summary cards '
      'for the selected month', (tester) async {
    final repo = MockSessionRepository();
    final now = _frozenNow;
    final today = _utcNoon(now.year, now.month, now.day);
    when(() => repo.listByUid('u1', limit: any(named: 'limit')))
        .thenAnswer((_) async => [
              makeSession(
                id: 's1',
                startedAt: today,
                status: SessionStatus.finished,
                wasFullyCompleted: true,
                durationMin: 45,
              ),
              makeSession(
                id: 's2',
                startedAt: today.subtract(const Duration(days: 1)),
                status: SessionStatus.finished,
                wasFullyCompleted: true,
              ),
            ]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: any(named: 'sessionId')))
        .thenAnswer((_) async => [makeSetLog()]);

    await tester.pumpWidget(wrap(
      const SizedBox.shrink(),
      overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
    ));
    await tester.pumpAndSettle();

    // Trap: the report screen's ListView is scrollable — the calendar
    // section sits below the fold, so it must be scrolled into view before
    // asserting on it (bitten twice already per PR5b instructions).
    final streakFinder = find.textContaining('Racha de');
    await tester.scrollUntilVisible(
      streakFinder,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(streakFinder, findsOneWidget);
    // Sin rutina activa el objetivo cae al fallback de 1 sesión por semana.
    // Con el reloj congelado en MIÉRCOLES, "hoy" y "ayer" son miércoles 16 y
    // martes 15 — la misma semana ART (lunes 14). Eso es UNA semana cumplida,
    // no dos. Ver el dartdoc de `_frozenNow`: con el reloj real este número
    // valía 1 o 2 según el día en que corriera el CI.
    expect(find.text('Racha de 1 semana'), findsOneWidget);
  });

  testWidgets(
      'selecting a different month re-fetches and updates the calendar '
      "trained-day marks (not just a no-crash smoke check)", (tester) async {
    final repo = MockSessionRepository();
    final now = _frozenNow;
    final olderMonth = DateTime(now.year, now.month - 2);

    when(() => repo.listByUid('u1', limit: any(named: 'limit')))
        .thenAnswer((_) async => [
              // Only trains in the OLDER month — the current month (default
              // selection) has zero trained days.
              makeSession(
                id: 's1',
                startedAt: _utcNoon(olderMonth.year, olderMonth.month, 10),
                status: SessionStatus.finished,
                wasFullyCompleted: true,
              ),
            ]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: any(named: 'sessionId')))
        .thenAnswer((_) async => [makeSetLog()]);

    await tester.pumpWidget(wrap(
      const SizedBox.shrink(),
      overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
    ));
    await tester.pumpAndSettle();

    // Default selection is the current (most recent) month → 0 trained days
    // marked, streak is 0 (session is in a different month, not
    // yesterday/today).
    await tester.scrollUntilVisible(
      // En 0 el label ya no dice "Racha de …" sino "Sin racha", así que
      // scrolleamos hasta ESE texto: buscar el otro nunca aparecería y el
      // scroll se comería el timeout en vez de fallar donde importa.
      find.text('Sin racha'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Sin racha'), findsOneWidget);
    expect(find.byKey(const ValueKey('workout-day-trained')), findsNothing);

    // Scroll the chart itself into view before grabbing its state — the
    // ListView is lazy, so widgets below the fold aren't built yet.
    await tester.scrollUntilVisible(
      find.byType(MonthlyReportChart),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // Switch the selected month via the chart's test hook (same seam
    // `onMonthSelected` uses) to the older month that HAS a trained day.
    final chartState = tester.state<MonthlyReportChartState>(
      find.byType(MonthlyReportChart),
    );
    chartState.debugSelectMonth(olderMonth);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('workout-day-trained')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workout-day-trained')), findsOneWidget);
  });

  testWidgets(
      'renders the month-vs-month muscle distribution radar below the '
      'workout-days calendar, with month-name legend labels (AD6/PR5c)',
      (tester) async {
    final repo = MockSessionRepository();
    final now = _frozenNow;
    final currentMonthStart = DateTime(now.year, now.month, 1);

    when(() => repo.listByUid('u1', limit: any(named: 'limit')))
        .thenAnswer((_) async => [
              makeSession(
                id: 's1',
                startedAt: _utcNoon(now.year, now.month, 1),
                status: SessionStatus.finished,
                wasFullyCompleted: true,
                durationMin: 45,
              ),
            ]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: any(named: 'sessionId')))
        .thenAnswer((_) async => [makeSetLog()]);

    await tester.pumpWidget(wrap(
      const SizedBox.shrink(),
      overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
    ));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('DISTRIBUCIÓN MUSCULAR'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('DISTRIBUCIÓN MUSCULAR'), findsOneWidget);
    // Legend shows the selected month's short name, not the generic
    // "Actual"/"Anterior" labels used by the athlete-insights radar.
    // `monthAbbrev` y NO `DateFormat('MMM yyyy')`: es la misma función que usa
    // la pantalla, y usa otra cosa a propósito. El CLDR de es-AR devuelve
    // 'sept' (4 chars) para septiembre, y con eso el label quedaba desalineado
    // con el eje del chart de al lado — está escrito en el dartdoc de
    // `_monthLegendLabel`.
    //
    // El test replicaba justo el formato que la pantalla evita. Once meses del
    // año coinciden por casualidad en tres caracteres; septiembre no, así que
    // este test se rompía UNA VEZ AL AÑO y sólo si alguien corría CI en
    // septiembre. Pasó el 01/09/2026 y bloqueó el CI de todo el repo.
    final expectedCurrentLabel =
        '${monthAbbrev(currentMonthStart, 'es_AR')} ${currentMonthStart.year}';
    expect(
      find.text(_capitalize(expectedCurrentLabel)),
      findsOneWidget,
    );
  });

  testWidgets(
      'switching the selected month updates the radar legend and monthly '
      'volume-by-group card (real data-delta, not a smoke check)',
      (tester) async {
    final repo = MockSessionRepository();
    final now = _frozenNow;
    final olderMonth = DateTime(now.year, now.month - 2);

    when(() => repo.listByUid('u1', limit: any(named: 'limit')))
        .thenAnswer((_) async => [
              makeSession(
                id: 's1',
                startedAt: _utcNoon(olderMonth.year, olderMonth.month, 10),
                status: SessionStatus.finished,
                wasFullyCompleted: true,
              ),
            ]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: any(named: 'sessionId')))
        .thenAnswer((_) async => [
              makeSetLog(id: 'l1', exerciseId: 'e-chest'),
            ]);

    await tester.pumpWidget(wrap(
      const SizedBox.shrink(),
      overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
        exercisesProvider.overrideWith((ref) async => const [
              Exercise(
                id: 'e-chest',
                name: 'Press',
                muscleGroup: 'chest',
                category: 'compound',
              ),
            ]),
      ],
    ));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byType(MonthlyReportChart),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final chartState = tester.state<MonthlyReportChartState>(
      find.byType(MonthlyReportChart),
    );
    chartState.debugSelectMonth(olderMonth);
    await tester.pumpAndSettle();

    // Ver la nota de `expectedCurrentLabel`.
    final expectedLabel =
        '${monthAbbrev(olderMonth, 'es_AR')} ${olderMonth.year}';

    await tester.scrollUntilVisible(
      find.text(_capitalize(expectedLabel)),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text(_capitalize(expectedLabel)), findsOneWidget);
    expect(find.text('VOLUMEN POR GRUPO'), findsOneWidget);
    expect(find.text('PECHO'), findsOneWidget);
    expect(find.text('1 set'), findsOneWidget);
  });

  // ── Deep link del push mensual ───────────────────────────────────────────
  // El contrato de la URL (`?month=YYYY-MM`) está cubierto en
  // `monthly_report_deep_link_test.dart` del lado que parsea, y en
  // `functions/src/__tests__/notify-monthly-report.test.ts` del lado que la
  // arma. Acá se prueba lo que queda: que la pantalla HONRE el mes.

  testWidgets('initialMonth abre la pantalla en ese mes, no en el más reciente',
      (tester) async {
    final repo = MockSessionRepository();
    final now = _frozenNow;
    final currentMonthStart = DateTime(now.year, now.month, 1);
    // El mes que el push reportaría: el que cerró.
    final reportedMonth = DateTime(now.year, now.month - 1, 1);

    when(() => repo.listByUid('u1', limit: any(named: 'limit')))
        .thenAnswer((_) async => [
              makeSession(
                id: 's-actual',
                startedAt: _utcNoon(
                    currentMonthStart.year, currentMonthStart.month, 1),
                status: SessionStatus.finished,
                wasFullyCompleted: true,
                durationMin: 45,
              ),
              makeSession(
                id: 's-reportado',
                startedAt:
                    _utcNoon(reportedMonth.year, reportedMonth.month, 15),
                status: SessionStatus.finished,
                wasFullyCompleted: true,
                durationMin: 60,
              ),
            ]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: any(named: 'sessionId')))
        .thenAnswer((_) async => [makeSetLog()]);

    await tester.pumpWidget(wrap(
      const SizedBox.shrink(),
      overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
      initialMonth: reportedMonth,
    ));
    await tester.pumpAndSettle();

    // El título de la pantalla es el mes seleccionado. Sin initialMonth sería
    // el mes actual — que el 1° del mes está vacío, que es justamente el
    // motivo por el que el push manda el mes anterior.
    final expected = _capitalize(
      '${monthAbbrev(reportedMonth, 'es_AR')} ${reportedMonth.year}',
    );
    final notExpected = _capitalize(
      '${monthAbbrev(currentMonthStart, 'es_AR')} ${currentMonthStart.year}',
    );

    await tester.scrollUntilVisible(
      find.text('DISTRIBUCIÓN MUSCULAR'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text(expected), findsOneWidget);
    expect(find.text(notExpected), findsNothing);
  });

  testWidgets(
      'un initialMonth fuera de la ventana de 12 meses cae al más reciente, '
      'no a una pantalla vacía', (tester) async {
    final repo = MockSessionRepository();
    final now = _frozenNow;
    final currentMonthStart = DateTime(now.year, now.month, 1);

    when(() => repo.listByUid('u1', limit: any(named: 'limit')))
        .thenAnswer((_) async => [
              makeSession(
                id: 's1',
                startedAt: _utcNoon(
                    currentMonthStart.year, currentMonthStart.month, 1),
                status: SessionStatus.finished,
                wasFullyCompleted: true,
                durationMin: 45,
              ),
            ]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: any(named: 'sessionId')))
        .thenAnswer((_) async => [makeSetLog()]);

    await tester.pumpWidget(wrap(
      const SizedBox.shrink(),
      overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
      // Un bookmark viejo, o un push que quedó sin abrir muchos meses.
      initialMonth: DateTime(now.year - 5, 3),
    ));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('DISTRIBUCIÓN MUSCULAR'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final expected = _capitalize(
      '${monthAbbrev(currentMonthStart, 'es_AR')} ${currentMonthStart.year}',
    );
    expect(find.text(expected), findsOneWidget);
  });
}

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
