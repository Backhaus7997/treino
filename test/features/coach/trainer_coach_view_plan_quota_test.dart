import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/utils/app_clock.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/subscription_tier.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach/domain/trainer_subscription.dart';
import 'package:treino/features/coach/trainer_coach_view.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Medidor de cupo del roster móvil (artboard G): «2 DE 2 · PLAN FREE».
///
/// El valor del header es avisar ANTES del choque, así que lo que se testea es
/// el contrato del string: numerador ponderado, denominador solo cuando el tier
/// tiene tope, estado visual distinto al llegar al límite, y qué tier y qué
/// tope rigen cuando el PF dio de baja su plan.

const _headerKey = Key('plan-quota-header');

TrainerLink _link(
  String athleteId,
  TrainerLinkStatus status,
) =>
    TrainerLink(
      id: 'link-$athleteId',
      trainerId: 'pf1',
      athleteId: athleteId,
      status: status,
      requestedAt: DateTime.utc(2026, 1, 1),
      acceptedAt: DateTime.utc(2026, 1, 2),
    );

UserProfile _trainer(TrainerSubscription? subscription) => UserProfile(
      uid: 'pf1',
      email: 'pf@test.com',
      displayName: 'Profe',
      role: UserRole.trainer,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      subscription: subscription,
    );

/// `weightLimit` se deja sin setear a propósito: el servidor no escribe ese
/// campo (ver [TrainerSubscription]), así que es la forma de los docs que
/// escribe él. Sin el campo, el header toma el tope de la tabla del tier.
/// Ojo, eso no quiere decir que lo ignore: si el doc lo trae, el header puede
/// preferirlo a la tabla (las condiciones están en `_PlanQuotaHeader`). El
/// Plan 3 que lo trae tiene su propio test.
TrainerSubscription _sub(SubscriptionTier tier) => TrainerSubscription(
      tier: tier,
      status: SubscriptionStatus.active,
    );

Widget _harness({
  required List<TrainerLink> links,
  TrainerSubscription? subscription,
}) =>
    ProviderScope(
      overrides: [
        userProfileProvider.overrideWith(
          (ref) => Stream<UserProfile?>.value(_trainer(subscription)),
        ),
        trainerLinksStreamProvider.overrideWith((ref) => Stream.value(links)),
        for (final l in links) ...[
          userPublicProfileProvider(l.athleteId).overrideWith(
            (ref) => Stream.value(
              UserPublicProfile(
                uid: l.athleteId,
                displayName: 'Atleta ${l.athleteId}',
                displayNameLowercase: 'atleta ${l.athleteId}',
              ),
            ),
          ),
          hasUnreadFromProvider(l.athleteId).overrideWith((ref) => false),
        ],
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: const Scaffold(body: TrainerCoachView()),
      ),
    );

String _headerText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(_headerKey)).data!;

Color _headerColor(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(_headerKey)).style!.color!;

/// El perfil que leyó el medidor, desde el MISMO contenedor que lo alimenta.
///
/// Una baja vencida y un perfil que no cargó dicen lo mismo en el header
/// («PLAN FREE»), y este tab no dibuja el nombre del PF. Leerlo de acá es lo
/// que prueba que el override se aplicó.
UserProfile? _perfilLeido(WidgetTester tester) {
  final perfil = ProviderScope.containerOf(
    tester.element(find.byKey(_headerKey)),
    listen: false,
  ).read(userProfileProvider);
  expect(perfil.hasValue, isTrue, reason: 'el perfil del PF no cargó');
  return perfil.requireValue;
}

void main() {
  group('medidor de cupo — un tier, un denominador', () {
    testWidgets('Free: 2 activos → "2 DE 2 · PLAN FREE"', (tester) async {
      await tester.pumpWidget(_harness(
        subscription: _sub(SubscriptionTier.free),
        links: [
          _link('a1', TrainerLinkStatus.active),
          _link('a2', TrainerLinkStatus.active),
        ],
      ));
      await tester.pumpAndSettle();

      expect(_headerText(tester), '2 DE 2 · PLAN FREE');
    });

    testWidgets('Plan 1: 3 activos → "3 DE 7 · PLAN 1"', (tester) async {
      await tester.pumpWidget(_harness(
        subscription: _sub(SubscriptionTier.plan1),
        links: [
          _link('a1', TrainerLinkStatus.active),
          _link('a2', TrainerLinkStatus.active),
          _link('a3', TrainerLinkStatus.active),
        ],
      ));
      await tester.pumpAndSettle();

      expect(_headerText(tester), '3 DE 7 · PLAN 1');
    });

    testWidgets('Plan 2: 1 activo → "1 DE 15 · PLAN 2"', (tester) async {
      await tester.pumpWidget(_harness(
        subscription: _sub(SubscriptionTier.plan2),
        links: [_link('a1', TrainerLinkStatus.active)],
      ));
      await tester.pumpAndSettle();

      expect(_headerText(tester), '1 DE 15 · PLAN 2');
    });

    testWidgets(
        'sin suscripción en el doc → Free por definición (sin backfill)',
        (tester) async {
      await tester.pumpWidget(_harness(
        links: [_link('a1', TrainerLinkStatus.active)],
      ));
      await tester.pumpAndSettle();

      expect(_headerText(tester), '1 DE 2 · PLAN FREE');
    });
  });

  group('medidor de cupo — Plan 3 no tiene tope', () {
    testWidgets('Plan 3: sin denominador y SIN la palabra "null"',
        (tester) async {
      await tester.pumpWidget(_harness(
        subscription: _sub(SubscriptionTier.plan3),
        links: [
          _link('a1', TrainerLinkStatus.active),
          _link('a2', TrainerLinkStatus.active),
        ],
      ));
      await tester.pumpAndSettle();

      final text = _headerText(tester);
      expect(text, '2 ALUMNOS · PLAN 3');
      expect(text, isNot(contains('DE')));
      expect(text.toLowerCase(), isNot(contains('null')));
    });

    testWidgets('Plan 3 con un weightLimit en el doc sigue sin denominador',
        (tester) async {
      // El servidor no escribe `weightLimit` (ver `TrainerSubscription`), pero
      // si un doc lo trajera igual, el tier manda: el header pregunta
      // `tier.isUnlimited` ANTES de mirar el campo. Sin esa guarda, el plan
      // ilimitado mostraría un tope que no existe.
      await tester.pumpWidget(_harness(
        subscription: const TrainerSubscription(
          tier: SubscriptionTier.plan3,
          status: SubscriptionStatus.active,
          weightLimit: 15,
        ),
        links: [_link('a1', TrainerLinkStatus.active)],
      ));
      await tester.pumpAndSettle();

      expect(_headerText(tester), '1 ALUMNO · PLAN 3');
    });

    // Un testWidgets POR tier, no un loop adentro de uno solo. Re-pumpear
    // `_harness` en el mismo test reusa el elemento del ProviderScope: el
    // container sobrevive y sigue sirviendo el perfil de la primera vuelta.
    // Medido: las cuatro vueltas dibujaban «1.5 DE 2 · PLAN FREE», y el test
    // pasaba sin haber visto nunca un Plan 3.
    group('ningún tier renderiza "null" en el header', () {
      for (final tier in SubscriptionTier.values) {
        testWidgets(tier.name, (tester) async {
          await tester.pumpWidget(_harness(
            subscription: _sub(tier),
            links: [
              _link('a1', TrainerLinkStatus.active),
              _link('a2', TrainerLinkStatus.paused),
            ],
          ));
          await tester.pumpAndSettle();

          final text = _headerText(tester);
          // Control: el header es el de ESTE tier. Sin esto, un harness que
          // dibujara otro perfil pasaría el chequeo de abajo sin probar nada.
          final etiqueta = switch (tier) {
            SubscriptionTier.free => 'PLAN FREE',
            SubscriptionTier.plan1 => 'PLAN 1',
            SubscriptionTier.plan2 => 'PLAN 2',
            SubscriptionTier.plan3 => 'PLAN 3',
          };
          expect(text, endsWith(etiqueta));
          expect(text.toLowerCase(), isNot(contains('null')));
        });
      }
    });
  });

  group('medidor de cupo — la carga es ponderada y fraccionaria', () {
    testWidgets('un pausado pesa 0.5 → "0.5", no "0.5.0" ni "1"',
        (tester) async {
      await tester.pumpWidget(_harness(
        subscription: _sub(SubscriptionTier.free),
        links: [_link('a1', TrainerLinkStatus.paused)],
      ));
      await tester.pumpAndSettle();

      expect(_headerText(tester), '0.5 DE 2 · PLAN FREE');
    });

    testWidgets('activo + pausado = 1.5 (un decimal, no dos)', (tester) async {
      await tester.pumpWidget(_harness(
        subscription: _sub(SubscriptionTier.plan1),
        links: [
          _link('a1', TrainerLinkStatus.active),
          _link('a2', TrainerLinkStatus.paused),
        ],
      ));
      await tester.pumpAndSettle();

      expect(_headerText(tester), '1.5 DE 7 · PLAN 1');
    });

    testWidgets('entero no arrastra decimal ("2", no "2.0")', (tester) async {
      await tester.pumpWidget(_harness(
        subscription: _sub(SubscriptionTier.plan1),
        links: [
          _link('a1', TrainerLinkStatus.paused),
          _link('a2', TrainerLinkStatus.paused),
          _link('a3', TrainerLinkStatus.paused),
          _link('a4', TrainerLinkStatus.paused),
        ],
      ));
      await tester.pumpAndSettle();

      expect(_headerText(tester), '2 DE 7 · PLAN 1');
    });

    testWidgets('sin tope: 1 exacto va en singular, 0.5 en plural',
        (tester) async {
      await tester.pumpWidget(_harness(
        subscription: _sub(SubscriptionTier.plan3),
        links: [_link('a1', TrainerLinkStatus.paused)],
      ));
      await tester.pumpAndSettle();

      expect(_headerText(tester), '0.5 ALUMNOS · PLAN 3');
    });
  });

  group('medidor de cupo — estado visual al límite', () {
    testWidgets('bajo el límite queda en textMuted', (tester) async {
      final palette = AppTheme.dark().extension<AppPalette>()!;

      await tester.pumpWidget(_harness(
        subscription: _sub(SubscriptionTier.free),
        links: [_link('a1', TrainerLinkStatus.active)],
      ));
      await tester.pumpAndSettle();

      expect(_headerText(tester), '1 DE 2 · PLAN FREE');
      expect(_headerColor(tester), palette.textMuted);
    });

    testWidgets('al límite (load == limit) cambia a highlight', (tester) async {
      final palette = AppTheme.dark().extension<AppPalette>()!;

      await tester.pumpWidget(_harness(
        subscription: _sub(SubscriptionTier.free),
        links: [
          _link('a1', TrainerLinkStatus.active),
          _link('a2', TrainerLinkStatus.active),
        ],
      ));
      await tester.pumpAndSettle();

      expect(_headerText(tester), '2 DE 2 · PLAN FREE');
      expect(
        _headerColor(tester),
        palette.highlight,
        reason: 'al llegar al tope el PF tiene que VERLO, no leerlo',
      );
      expect(
        palette.highlight,
        isNot(palette.textMuted),
        reason:
            'si los dos tokens coincidieran, el estado no distinguiría nada',
      );
    });

    testWidgets('por encima del límite también queda en highlight',
        (tester) async {
      final palette = AppTheme.dark().extension<AppPalette>()!;

      await tester.pumpWidget(_harness(
        subscription: _sub(SubscriptionTier.free),
        links: [
          _link('a1', TrainerLinkStatus.active),
          _link('a2', TrainerLinkStatus.active),
          _link('a3', TrainerLinkStatus.paused),
        ],
      ));
      await tester.pumpAndSettle();

      expect(_headerText(tester), '2.5 DE 2 · PLAN FREE');
      expect(_headerColor(tester), palette.highlight);
    });

    testWidgets('Plan 3 nunca entra en el estado de límite', (tester) async {
      final palette = AppTheme.dark().extension<AppPalette>()!;

      await tester.pumpWidget(_harness(
        subscription: _sub(SubscriptionTier.plan3),
        links: [
          for (var i = 0; i < 20; i++) _link('a$i', TrainerLinkStatus.active),
        ],
      ));
      await tester.pumpAndSettle();

      expect(_headerText(tester), '20 ALUMNOS · PLAN 3');
      expect(_headerColor(tester), palette.textMuted);
    });
  });

  group('medidor de cupo — presencia', () {
    testWidgets('se muestra también con el roster vacío', (tester) async {
      await tester.pumpWidget(_harness(
        subscription: _sub(SubscriptionTier.free),
        links: const [],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Sin alumnos activos todavía.'), findsOneWidget);
      expect(_headerText(tester), '0 DE 2 · PLAN FREE');
    });
  });

  // ── Una baja ──
  //
  // El servidor le respeta el tier pago a una baja HASTA `currentPeriodEnd` y
  // después la baja a Free (`limiteDelStatus` en
  // `functions/src/subscriptions/effective-limit.ts`) sin reescribir
  // `subscription`: el doc sigue diciendo el tier viejo. Para una baja, el
  // medidor tiene que
  // decir lo mismo que el servidor, como Facturación en la web.
  group('medidor de cupo — plan dado de baja', () {
    // Jueves 1/10/2026 12:00, LOCAL (`AppClock.freeze` lo exige). Los bordes
    // van en UTC, una semana antes y una semana después. Según el timezone del
    // runner, ese mediodía local es un instante entre el 30/9 22:00Z (UTC+14)
    // y el 2/10 00:00Z (UTC−12): el borde más cercano queda a más de seis días
    // en cualquiera.
    setUp(() => AppClock.freeze(DateTime(2026, 10, 1, 12)));
    tearDown(AppClock.unfreeze);

    final vencida = DateTime.utc(2026, 9, 24, 12);
    final conDiasPagos = DateTime.utc(2026, 10, 8, 12);

    /// El doc de un plan pago CON su `weightLimit`. El servidor no lo escribe
    /// (`reconcile.ts` escribe tier, estado, fin de período y piso prepago),
    /// pero un doc puede traerlo, y es la forma que distingue: sin él, un
    /// arreglo que cambiara sólo el tier también daría «DE 2», y con él se le
    /// colaría el «DE 7».
    TrainerSubscription suscripcion({
      required DateTime fin,
      SubscriptionTier tier = SubscriptionTier.plan1,
      SubscriptionStatus status = SubscriptionStatus.cancelled,
    }) =>
        TrainerSubscription(
          tier: tier,
          status: status,
          weightLimit: tier.weightLimit,
          currentPeriodEnd: fin,
        );

    final tresActivos = [
      _link('a1', TrainerLinkStatus.active),
      _link('a2', TrainerLinkStatus.active),
      _link('a3', TrainerLinkStatus.active),
    ];

    testWidgets('baja vencida: PLAN FREE con el tope de Free, y pasado de tope',
        (tester) async {
      final palette = AppTheme.dark().extension<AppPalette>()!;

      await tester.pumpWidget(_harness(
        subscription: suscripcion(fin: vencida),
        links: tresActivos,
      ));
      await tester.pumpAndSettle();

      // El perfil SE LEYÓ, y el doc sigue diciendo Plan 1 con su tope de 7.
      // Sin esto el test pasaría igual con el override roto: un perfil que no
      // carga también cae a Free.
      final perfil = _perfilLeido(tester);
      expect(perfil?.displayName, 'Profe');
      expect(perfil?.subscription?.tier, SubscriptionTier.plan1);
      expect(perfil?.subscription?.weightLimit, 7);

      expect(_headerText(tester), '3 DE 2 · PLAN FREE');
      expect(
        _headerColor(tester),
        palette.highlight,
        reason: 'con 3 alumnos y el tope de Free, el PF ya está pasado',
      );
    });

    // Control del de arriba: misma baja, mismo reloj, sólo cambia la fecha. Si
    // el Free saliera de `cancelled` a secas y no del vencimiento, esto
    // también diría Free.
    testWidgets('baja con días pagos: sigue en PLAN 1 con el tope de Plan 1',
        (tester) async {
      await tester.pumpWidget(_harness(
        subscription: suscripcion(fin: conDiasPagos),
        links: tresActivos,
      ));
      await tester.pumpAndSettle();

      expect(_headerText(tester), '3 DE 7 · PLAN 1');
    });

    // Control del eje del estado: con el plan ACTIVO el servidor ni mira la
    // fecha (`limiteDelStatus` devuelve el tope del tier). Por vencimiento
    // sólo cae una baja.
    testWidgets('plan activo con el período vencido: sigue en PLAN 1',
        (tester) async {
      await tester.pumpWidget(_harness(
        subscription: suscripcion(
          fin: vencida,
          status: SubscriptionStatus.active,
        ),
        links: tresActivos,
      ));
      await tester.pumpAndSettle();

      expect(_headerText(tester), '3 DE 7 · PLAN 1');
    });

    // Plan 3 no tiene tope, así que acá no cambia sólo el nombre: vencida la
    // baja, el medidor vuelve a tener denominador, el de Free.
    testWidgets('Plan 3 con la baja vencida: vuelve a tener el tope de Free',
        (tester) async {
      await tester.pumpWidget(_harness(
        subscription: suscripcion(tier: SubscriptionTier.plan3, fin: vencida),
        links: [_link('a1', TrainerLinkStatus.active)],
      ));
      await tester.pumpAndSettle();

      final perfil = _perfilLeido(tester);
      expect(perfil?.displayName, 'Profe');
      expect(perfil?.subscription?.tier, SubscriptionTier.plan3);

      expect(_headerText(tester), '1 DE 2 · PLAN FREE');
    });

    // El tab puede seguir montado cuando vence la baja, y en ese borde no emite
    // nadie: el servidor no reescribe `subscription` (el perfil no vuelve a
    // emitir) y `AppClock` no avisa. Calculada en el build, la vigencia
    // quedaba en «PLAN 1» hasta un rebuild ajeno. La lee
    // `vigenciaDelPlanProvider`, que se recalcula solo al llegar al borde.
    testWidgets('vence con el tab montado: pasa a PLAN FREE solo',
        (tester) async {
      final fin = DateTime.utc(2026, 10, 15, 15);
      AppClock.freeze(fin.subtract(const Duration(hours: 1)).toLocal());
      await tester.pumpWidget(_harness(
        subscription: suscripcion(fin: fin),
        links: tresActivos,
      ));
      await tester.pumpAndSettle();
      expect(_headerText(tester), '3 DE 7 · PLAN 1');

      // Sólo pasa la hora: el reloj cruza el fin y nada más cambia (ni el
      // perfil ni los vínculos emiten de nuevo).
      AppClock.freeze(fin.add(const Duration(minutes: 1)).toLocal());
      await tester.pump(const Duration(hours: 1));
      await tester.pump();

      expect(_headerText(tester), '3 DE 2 · PLAN FREE');
    });

    // Control: con días pagos, el Plan 3 sigue sin tope.
    testWidgets('Plan 3 con días pagos: sigue sin denominador', (tester) async {
      await tester.pumpWidget(_harness(
        subscription: suscripcion(
          tier: SubscriptionTier.plan3,
          fin: conDiasPagos,
        ),
        links: [_link('a1', TrainerLinkStatus.active)],
      ));
      await tester.pumpAndSettle();

      expect(_headerText(tester), '1 ALUMNO · PLAN 3');
    });
  });
}
