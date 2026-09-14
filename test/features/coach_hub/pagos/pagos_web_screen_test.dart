import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart'
    show trainerLinksStreamProvider;
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/pagos_web_screen.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart'
    show TreinoFilterChips, TreinoInteractiveState;
import 'package:treino/features/payments/application/pagos_por_cobrar_provider.dart'
    show pagosPorCobrarProvider;
import 'package:treino/features/payments/application/payment_providers.dart'
    show paymentRepositoryProvider, trainerPaymentsProvider;
import 'package:treino/features/payments/data/payment_repository.dart';
import 'package:treino/features/payments/domain/payment.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart'
    show userPublicProfilesBatchProvider;
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class _MockPaymentRepo extends Mock implements PaymentRepository {}

// ── Fakes ─────────────────────────────────────────────────────────────────────

TrainerLink _link(String athleteId, TrainerLinkStatus status) => TrainerLink(
      id: 'l_$athleteId',
      trainerId: 'trainer-1',
      athleteId: athleteId,
      status: status,
      requestedAt: DateTime.utc(2026, 1, 1),
    );

UserPublicProfile _prof(String uid, String name) =>
    UserPublicProfile(uid: uid, displayName: name);

// ── Setup ─────────────────────────────────────────────────────────────────────

const _kDesktopSize = Size(1440, 900);

Widget _wrap(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        // Wrap in Scaffold as the shell would — screen itself adds none
        home: Scaffold(body: child),
      ),
    );

List<Override> _emptyOverrides({
  List<TrainerLink> links = const [],
  List<UserPublicProfile> profiles = const [],
  PaymentRepository? repo,
  String? trainerId,
}) =>
    [
      trainerPaymentsProvider.overrideWith((ref) => Stream.value(const [])),
      pagosPorCobrarProvider.overrideWith((ref) => const AsyncValue.data([])),
      // RegistrarPagoDialog (opened by the "+ Registrar pago" button) now
      // reads these to populate the alumno dropdown.
      trainerLinksStreamProvider.overrideWith((ref) => Stream.value(links)),
      userPublicProfilesBatchProvider.overrideWith(
        (ref, key) => {for (final p in profiles) p.uid: p},
      ),
      if (repo != null) paymentRepositoryProvider.overrideWithValue(repo),
      if (trainerId != null) currentUidProvider.overrideWithValue(trainerId),
    ];

// Buckets: `_periodStart` = primer día del mes actual (UTC). Un `createdAt`
// anterior cae en Vencidos; en o después, en PorVencer (mismo criterio que
// pagosBucketsProvider — ver pagos_buckets_provider_test.dart).
final _now = DateTime.now().toUtc();
final _periodStart = DateTime.utc(_now.year, _now.month, 1);

Payment _payment({
  required String id,
  required String concept,
  required PaymentStatus status,
  required DateTime createdAt,
}) =>
    Payment(
      id: id,
      trainerId: 'trainer-1',
      athleteId: 'athlete-1',
      amountArs: 1000,
      concept: concept,
      status: status,
      createdAt: createdAt,
      paidAt: status == PaymentStatus.paid ? createdAt : null,
    );

List<Override> _mixedBucketsOverrides() {
  final vencido = _payment(
    id: 'v1',
    concept: 'Cuota vencida', // i18n
    status: PaymentStatus.pending,
    createdAt: _periodStart.subtract(const Duration(days: 5)),
  );
  final porVencer = _payment(
    id: 'pv1',
    concept: 'Cuota por vencer', // i18n
    status: PaymentStatus.pending,
    createdAt: _periodStart,
  );
  final pagado = _payment(
    id: 'p1',
    concept: 'Cuota pagada', // i18n
    status: PaymentStatus.paid,
    createdAt: _periodStart,
  );
  return [
    trainerPaymentsProvider
        .overrideWith((ref) => Stream.value([vencido, porVencer, pagado])),
    pagosPorCobrarProvider.overrideWith((ref) => const AsyncValue.data([])),
  ];
}

/// 30 pagos PAGADOS, uno por dia hacia atras. El bucket «Pagados» del filtro
/// por defecto no los toma —arranca en «Por vencer»—, asi que el test entra
/// por el chip.
List<Override> _treintaPagadosOverrides() => [
      trainerPaymentsProvider.overrideWith(
        (ref) => Stream.value([
          for (var i = 0; i < 30; i++)
            _payment(
              id: 'pg$i',
              concept: 'Cuota $i', // i18n
              status: PaymentStatus.paid,
              createdAt: _periodStart.subtract(Duration(days: i)),
            ),
        ]),
      ),
      pagosPorCobrarProvider.overrideWith((ref) => const AsyncValue.data([])),
    ];

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    registerFallbackValue(
      Payment(
        id: '',
        trainerId: 'trainer-1',
        athleteId: 'athlete-1',
        amountArs: 1000,
        concept: 'test',
        status: PaymentStatus.paid,
        createdAt: DateTime.utc(2026, 1, 1),
        paidAt: DateTime.utc(2026, 1, 1),
      ),
    );
  });

  // Desktop viewport for all tests
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('PagosScreen smoke (REQ-PAGW-SHELL-001/002, TAB-002, EMPTY-001)', () {
    // (a) Header, subtitle and CTA action present
    testWidgets(
        'SCENARIO 1 — section header "PAGOS", subtítulo y CTA "Registrar '
        'pago" presentes', (tester) async {
      tester.view.physicalSize = _kDesktopSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _wrap(const PagosScreen(), overrides: _emptyOverrides()),
      );
      await tester.pumpAndSettle();

      expect(find.text('PAGOS'), findsOneWidget); // i18n header
      expect(
        find.textContaining('Cobros, vencimientos'), // i18n
        findsOneWidget,
      );
      expect(find.text('Registrar pago'), findsOneWidget); // i18n CTA
      expect(find.byKey(const Key('pagos_registrar_pago_cta')), findsOneWidget);
    });

    // (b) Tap CTA "Registrar pago" → AlertDialog opens
    testWidgets(
        'SCENARIO 2 — tap CTA "Registrar pago" opens AlertDialog '
        '(REQ-PAGW-SHELL-002)', (tester) async {
      tester.view.physicalSize = _kDesktopSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _wrap(const PagosScreen(), overrides: _emptyOverrides()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('pagos_registrar_pago_cta')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
    });

    // (c) No Scaffold or SafeArea inside PagosScreen (REQ-PAGW-SHELL-001)
    testWidgets(
        'SCENARIO — no extra Scaffold or SafeArea inside PagosScreen '
        '(REQ-PAGW-SHELL-001)', (tester) async {
      tester.view.physicalSize = _kDesktopSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _wrap(const PagosScreen(), overrides: _emptyOverrides()),
      );
      await tester.pumpAndSettle();

      // The outer Scaffold is from _wrap — expect exactly 1.
      expect(find.byType(Scaffold), findsOneWidget);
      // No SafeArea inside PagosScreen.
      expect(find.byType(SafeArea), findsNothing);
    });

    // (d) TreinoFilterChips with the 4 filter labels, no Material TabBar
    testWidgets(
        'SCENARIO — TreinoFilterChips con los 4 filtros, sin TabBar '
        '(REQ-PAGW-TAB-002)', (tester) async {
      tester.view.physicalSize = _kDesktopSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _wrap(const PagosScreen(), overrides: _emptyOverrides()),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TreinoFilterChips), findsOneWidget);
      expect(find.byType(TabBar), findsNothing);

      expect(find.textContaining('Vencidos'), findsOneWidget);
      expect(find.textContaining('Por vencer'), findsOneWidget);
      expect(find.textContaining('Pagados'), findsOneWidget);
      expect(find.textContaining('Todos'), findsOneWidget);
    });

    // (d2) Tapping a chip switches the bucket shown in the table
    testWidgets(
        'SCENARIO — tocar un chip cambia el bucket mostrado en la tabla',
        (tester) async {
      tester.view.physicalSize = _kDesktopSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _wrap(const PagosScreen(), overrides: _mixedBucketsOverrides()),
      );
      await tester.pumpAndSettle();

      // El filtro por defecto es Por vencer (#605), no Vencidos.
      expect(find.text('Cuota por vencer'), findsOneWidget);
      expect(find.text('Cuota vencida'), findsNothing);
      expect(find.text('Cuota pagada'), findsNothing);

      await tester.tap(find.text('Vencidos'));
      await tester.pumpAndSettle();

      expect(find.text('Cuota vencida'), findsOneWidget);
      expect(find.text('Cuota por vencer'), findsNothing);
      expect(find.text('Cuota pagada'), findsNothing);

      await tester.tap(find.text('Pagados'));
      await tester.pumpAndSettle();

      expect(find.text('Cuota vencida'), findsNothing);
      expect(find.text('Cuota por vencer'), findsNothing);
      expect(find.text('Cuota pagada'), findsOneWidget);
    });

    // (e) Empty state per tab
    testWidgets(
        'SCENARIO — empty state text in default tab (REQ-PAGW-EMPTY-001)',
        (tester) async {
      tester.view.physicalSize = _kDesktopSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _wrap(const PagosScreen(), overrides: _emptyOverrides()),
      );
      await tester.pumpAndSettle();

      // Default tab is Por vencer (index 0) — it should show empty state.
      expect(
        find.text('No hay pagos pendientes'), // i18n
        findsOneWidget,
      );
    });

    // KPI row is present
    testWidgets('KPI row rendered with 3 tiles', (tester) async {
      tester.view.physicalSize = _kDesktopSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _wrap(const PagosScreen(), overrides: _emptyOverrides()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ingreso del mes'), findsOneWidget); // i18n
      expect(find.text('Pendiente cobrar'), findsOneWidget); // i18n
      expect(find.text('Vencido'), findsOneWidget); // i18n
    });
  });

  group('PagosScreen _onRegistrarPago persistence', () {
    late _MockPaymentRepo mockRepo;

    setUpAll(() {
      registerFallbackValue(
        Payment(
          id: '',
          trainerId: 'trainer-1',
          athleteId: 'athlete-1',
          amountArs: 1000,
          concept: 'test',
          status: PaymentStatus.paid,
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );
    });

    setUp(() {
      mockRepo = _MockPaymentRepo();
      when(() => mockRepo.add(any())).thenAnswer((_) async {});
    });

    // Full round trip: open the dialog from the header button, fill it in,
    // confirm → the caller (_onRegistrarPago) must build and persist a real
    // Payment via paymentRepositoryProvider.add. Covers the wiring between
    // the dialog's RegistrarPagoResult and the screen's write path.
    testWidgets(
        'SCENARIO — fill dialog + Registrar → repo.add called with a paid '
        'Payment for the selected athlete', (tester) async {
      tester.view.physicalSize = _kDesktopSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _wrap(
          const PagosScreen(),
          overrides: _emptyOverrides(
            links: [_link('athlete-1', TrainerLinkStatus.active)],
            profiles: [_prof('athlete-1', 'Ana Activa')],
            repo: mockRepo,
            trainerId: 'trainer-1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
          find.widgetWithText(TreinoInteractiveState, 'Registrar pago').first);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ana Activa').last);
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'Monto (ARS)'), '5000');
      await tester.enterText(
          find.widgetWithText(TextField, 'Concepto'), 'Clase suelta');

      await tester.tap(find.text('Registrar')); // i18n
      await tester.pumpAndSettle();

      final captured =
          verify(() => mockRepo.add(captureAny())).captured.single as Payment;
      expect(captured.trainerId, 'trainer-1');
      expect(captured.athleteId, 'athlete-1');
      expect(captured.amountArs, 5000);
      expect(captured.concept, 'Clase suelta');
      expect(captured.status, PaymentStatus.paid);
      expect(captured.dueAt, isNull);
      expect(find.text('Pago registrado.'), findsOneWidget); // i18n
    });

    // Cancelling the dialog must not touch the repository at all.
    testWidgets('SCENARIO — cancel dialog → repo.add NOT called',
        (tester) async {
      tester.view.physicalSize = _kDesktopSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _wrap(
          const PagosScreen(),
          overrides: _emptyOverrides(
            links: [_link('athlete-1', TrainerLinkStatus.active)],
            profiles: [_prof('athlete-1', 'Ana Activa')],
            repo: mockRepo,
            trainerId: 'trainer-1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
          find.widgetWithText(TreinoInteractiveState, 'Registrar pago').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancelar')); // i18n
      await tester.pumpAndSettle();

      verifyNever(() => mockRepo.add(any()));
    });
  });

  // ── Scroll ────────────────────────────────────────────────────────────────
  //
  // Regresión: con más pagos de los que entran en pantalla, la lista se cortaba
  // abajo y no había forma de bajar. La pantalla era un `Column` con la tabla
  // adentro de un `Expanded`, y `CoachHubDataTable` NO tiene scroller propio
  // (es un `Column` de filas): el `Expanded` le daba una caja del alto del
  // viewport y lo que sobraba quedaba afuera.
  //
  // No se veía como un overflow de Flutter —nada de rayas amarillas— porque el
  // `ClipRRect` de la tabla lo recorta en silencio. En producción, con 11 pagos
  // cargados, el PF veía 7 y los otros 4 no existían.

  group('PagosScreen — orden por estado y ventana de tiempo', () {
    testWidgets('la columna ESTADO es ordenable y agrupa por lo que se ve',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(const PagosScreen(), overrides: _mixedBucketsOverrides()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Todos'));
      await tester.pumpAndSettle();

      // Antes ESTADO no era ordenable: era la unica de las cuatro columnas de
      // datos sin flecha, y es justo la que agrupa «a quien le tengo que
      // cobrar».
      await tester.tap(find.text('ESTADO'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sort_indicator_estado')), findsOneWidget);
    });

    testWidgets('el selector de periodo arranca en «todo el historial»',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(const PagosScreen(), overrides: _mixedBucketsOverrides()),
      );
      await tester.pumpAndSettle();

      // Una ventana por default esconde pagos sin avisar, y el primero que se
      // esconde es el mas viejo — que en una lista de deudas es el que mas
      // importa.
      expect(find.text('Todo el historial'), findsOneWidget);
      expect(find.byKey(const Key('pagos_periodo_selector')), findsOneWidget);
    });

    testWidgets('elegir 30 dias saca los pagos viejos de la lista',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(const PagosScreen(), overrides: _treintaPagadosOverrides()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pagados'));
      await tester.pumpAndSettle();
      expect(find.text('1–25 de 30'), findsOneWidget);

      await tester.tap(find.byKey(const Key('pagos_periodo_selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pagos_periodo_treintaDias')));
      await tester.pumpAndSettle();

      // Los 30 pagos son uno por dia hacia atras desde `_periodStart`, asi
      // que con la ventana de 30 dias el paginado deja de hacer falta: la
      // lista entra en una pagina y el pie se esconde solo.
      expect(find.text('1–25 de 30'), findsNothing);
    });
  });

  group('PagosScreen — paginado de 25', () {
    testWidgets('con 30 pagos la tabla muestra 25 y aparece el pie',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(const PagosScreen(), overrides: _treintaPagadosOverrides()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pagados'));
      await tester.pumpAndSettle();

      // Cuota 0..24 entran; la 25 ya es de la segunda pagina.
      expect(find.text('Cuota 0'), findsOneWidget);
      expect(find.text('Cuota 24'), findsOneWidget);
      expect(find.text('Cuota 25'), findsNothing);
      expect(find.text('1–25 de 30'), findsOneWidget);
    });

    testWidgets('la segunda pagina trae los 5 que faltan', (tester) async {
      tester.view.physicalSize = const Size(1440, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(const PagosScreen(), overrides: _treintaPagadosOverrides()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pagados'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('coach_hub_pager_next')));
      await tester.pumpAndSettle();

      expect(find.text('Cuota 25'), findsOneWidget);
      expect(find.text('Cuota 29'), findsOneWidget);
      expect(find.text('Cuota 0'), findsNothing);
      expect(find.text('26–30 de 30'), findsOneWidget);
    });

    testWidgets('cambiar de pestaña vuelve a la pagina 1', (tester) async {
      // Sin esto el PF sale de la pagina 2 de «Pagados» y entra en la pagina
      // 2 de «Todos», que puede no existir: ve una tabla vacia y nada que
      // explique por que.
      tester.view.physicalSize = const Size(1440, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(const PagosScreen(), overrides: _treintaPagadosOverrides()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pagados'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('coach_hub_pager_next')));
      await tester.pumpAndSettle();
      expect(find.text('26–30 de 30'), findsOneWidget);

      await tester.tap(find.text('Todos'));
      await tester.pumpAndSettle();

      expect(find.text('1–25 de 30'), findsOneWidget);
      expect(find.text('Cuota 0'), findsOneWidget);
    });
  });

  group('la tabla scrollea cuando hay más pagos que pantalla', () {
    /// 20 pagos: bastante más de lo que entra en 1440x900.
    List<Override> muchosPagosOverrides() {
      final pagos = [
        for (var i = 0; i < 20; i++)
          _payment(
            id: 'p$i',
            concept: 'Cuota $i', // i18n
            status: PaymentStatus.paid,
            createdAt: _periodStart,
          ),
      ];
      return [
        trainerPaymentsProvider.overrideWith((ref) => Stream.value(pagos)),
        pagosPorCobrarProvider.overrideWith((ref) => const AsyncValue.data([])),
      ];
    }

    /// Monta la pantalla y se para en el tab Pagados, que es donde caen los
    /// 20 (el filtro por defecto es Vencidos y quedaría vacío).
    Future<void> pumpEnPagados(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(_kDesktopSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrap(const PagosScreen(), overrides: muchosPagosOverrides()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pagados')); // i18n
      await tester.pumpAndSettle();
    }

    testWidgets('hay un Scrollable y el contenido excede el viewport',
        (tester) async {
      await pumpEnPagados(tester);

      final scrollable = find.byType(Scrollable);
      expect(
        scrollable,
        findsWidgets,
        reason: 'sin un Scrollable, las filas que no entran en pantalla no se '
            'pueden alcanzar — y el ClipRRect de la tabla las oculta sin avisar',
      );

      final state = tester.state<ScrollableState>(scrollable.first);
      expect(
        state.position.maxScrollExtent,
        greaterThan(0),
        reason:
            'el contenido tiene que exceder el viewport: si maxScrollExtent '
            'es 0 la pantalla entra entera y este test no prueba nada',
      );
    });

    testWidgets('scrollear hasta abajo trae la última fila a la pantalla',
        (tester) async {
      await pumpEnPagados(tester);

      // Se mide la POSICIÓN, no la existencia. `SingleChildScrollView`
      // construye todo su hijo de una, así que `find.text('Cuota 19')` lo
      // encuentra desde el primer frame aunque esté 600px abajo del borde. Lo
      // que el PF reportó no es que la fila no exista: es que no la puede
      // alcanzar.
      final antes = tester.getTopLeft(find.text('Cuota 19')).dy;
      expect(
        antes,
        greaterThan(_kDesktopSize.height),
        reason: 'la última fila tiene que arrancar fuera de pantalla, si no '
            'este test no está probando el scroll',
      );

      // Se salta al final por el `ScrollPosition` en vez de arrastrar:
      // `scrollUntilVisible` necesita un `Scrollable` único y acá hay más de
      // uno. Lo que importa probar es que llegando abajo la fila entra, no
      // cómo se llega.
      final state =
          tester.state<ScrollableState>(find.byType(Scrollable).first);
      state.position.jumpTo(state.position.maxScrollExtent);
      await tester.pumpAndSettle();

      final despues = tester.getTopLeft(find.text('Cuota 19')).dy;
      expect(
        despues,
        lessThan(_kDesktopSize.height),
        reason: 'después de scrollear al fondo, la última fila tiene que estar '
            'dentro del viewport — que es exactamente lo que no pasaba',
      );
    });
  });
}
