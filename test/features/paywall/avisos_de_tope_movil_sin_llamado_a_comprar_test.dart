// Guard — los TRES avisos de tope del PF (alumnos, ejercicios propios,
// plantillas), en su forma MÓVIL, no llaman a comprar — ni en castellano ni en
// inglés — y en inglés no filtran castellano.
//
// ─── Qué regla protege ──────────────────────────────────────────────────────
//
// Guideline 3.1.3(f) de Apple (misma cita que `anti_steering_movil_test.dart`
// y `superficie_de_cobro_alumno_test.dart`):
//
//   «Free apps acting as a stand-alone companion to a paid web based tool
//   [...] do not need to use in-app purchase, **provided there is no
//   purchasing inside the app, or calls to action for purchase outside of
//   the app**.»
//
// Los otros dos guards de esta carpeta cuidan que el móvil no diga DÓNDE se
// paga (carteles tipo "en la web", "TREINO web"). Éste cuida un eje
// distinto: que el móvil no LLAME a pagar, aunque no diga dónde — "subí de
// plan", "pasate a Plan 1", "reactivalo", "regularizá" son calls to action
// igual que un cartel con la palabra "web", sólo que sin nombrar el canal.
//
// ─── La decisión que este guard fija ────────────────────────────────────────
//
// Antes de esto, el sheet MÓVIL de los tres avisos decía exactamente lo
// mismo que el dialog WEB: "Para sumar más, subí de plan.", "PASATE A PLAN
// 1", "Reactivalo y volvés a tus N alumnos". El dueño decidió, 2026-09-29:
// mismo estilo visual en las tres superficies (candado, tarjeta de precio,
// botón de acento, link de descarte) — pero en el MÓVIL el cuerpo sólo dice
// el ESTADO, la tarjeta del siguiente plan dice sólo su NOMBRE (sin "PASATE
// A"), y el link de descarte dice "Entendido" en vez de "Ahora no" (que
// presupone una oferta que el móvil ya no hace). La WEB no cambia: sigue
// vendiendo.
//
// ─── Las DOS lenguas del móvil (hallazgo Codex, PR #1266) ───────────────────
//
// La forma móvil de los tres avisos sale de AppL10n, con su traducción al
// inglés. Este guard recorre CADA variante que el móvil puede renderizar en
// los dos locales (es_AR y en), y en cada una chequea dos cosas:
//
//   1. que no llame a comprar — con agujas en castellano Y en inglés
//      («upgrade», «subscribe», «buy», «purchase», «get plan»…): una
//      traducción descuidada («Upgrade to Plan 2») reintroduce el mismo call
//      to action en otra lengua;
//   2. que en inglés no aparezca castellano — un string que se quedó
//      hardcodeado (el bug que motivó este recorrido) no lo agarra ninguna
//      aguja de compra, así que se busca por lo que es: palabras y letras
//      que no existen en inglés. El detector tiene su propio control (el
//      mismo barrido sobre es_AR TIENE que encontrar castellano), porque un
//      detector que nunca encuentra nada tampoco prueba nada.
//
// ─── Por qué esto no reemplaza a los otros dos guards ───────────────────────
//
// Un texto puede evitar decir "web" y CTA igual ("¡Subí de plan ya!" no
// nombra ningún canal). Los tres guards juntos cubren los dos ejes: dónde se
// paga (los otros dos) y si se llama a pagar (éste).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/subscription_tier.dart';
import 'package:treino/features/coach/presentation/widgets/trainer_limit_notice.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/plan_limit_paywall.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/plan_limit_shared.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Los DOS locales que hablan los avisos móviles — recorrido completo del
/// guard en las dos lenguas.
const _kLocales = [Locale('es', 'AR'), Locale('en')];

/// El texto listo para buscarle una aguja: minúsculas y sin acentos. Mismo
/// criterio que `anti_steering_movil_test.dart` — normalizar las dos puntas
/// es lo que hace que la lista de agujas signifique lo que uno cree que
/// significa al leerla.
String _normalizado(String s) => s
    .toLowerCase()
    .replaceAll('á', 'a')
    .replaceAll('é', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ú', 'u');

/// Frases que le piden al PF que compre, pague o suba de plan. Normalizadas:
/// minúsculas, sin acentos. No pretende ser exhaustiva — mismo criterio que
/// `_carteles` en `anti_steering_movil_test.dart`: frena al distraído que
/// copia un cuerpo existente, no al malicioso.
const _llamadosAComprar = <String>[
  'subi de plan',
  'pasate',
  'pasa a',
  'suscribite',
  'contrata',
  'reactiva',
  'regulariza',
  'paga ',
  'compra',
  'mejora tu plan',
  'elegi',
  // Inglés — el espejo de la lista de arriba, para el recorrido en
  // Locale('en'). «subscribe» no matchea «subscription»: la aguja termina en
  // «-be».
  'upgrade',
  'subscribe',
  'buy',
  'purchase',
  'get plan',
  'reactivate',
  'renew',
  'pay ',
  'choose',
  'switch to',
];

/// Los `Text` visibles del árbol actual, uno por renglón, SIN normalizar.
String _textoCrudo(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .join('\n');

/// Todo el texto visible del árbol actual, normalizado y concatenado.
String _textoVisible(WidgetTester tester) => _normalizado(_textoCrudo(tester));

/// Las agujas de [_llamadosAComprar] que aparecen en el texto visible.
List<String> _llamadosEncontrados(WidgetTester tester) {
  final texto = _textoVisible(tester);
  return [
    for (final aguja in _llamadosAComprar)
      if (texto.contains(aguja)) aguja,
  ];
}

void _sinLlamadosAComprar(WidgetTester tester, String aviso) {
  for (final aguja in _llamadosEncontrados(tester)) {
    fail('$aviso (móvil) dice «$aguja» — Guideline 3.1.3(f): el binario '
        'móvil no puede tener calls to action de compra.');
  }
}

/// Palabras que sólo existen en castellano (normalizadas, con límite de
/// palabra). Elegidas para NO chocar con inglés: nada de «sin», «con», «me»,
/// «ver»-como-prefijo ni «limite» (que sí es prefijo de «limited»).
final _palabrasDeCastellano = RegExp(
  r'\b(tu|tus|de|del|el|los|las|que|para|una|incluye|hasta|mientras|tanto|'
  r'alumno|alumnos|ejercicio|ejercicios|plantilla|plantillas|suscripcion|'
  r'limite|tope|ver|estado|activa|pausada|cancelada|entendido|contactanos|'
  r'medida|mes|tenes|conservas|propio|propios)\b',
);

/// Letras que no existen en inglés.
final _letrasDeCastellano = RegExp('[áéíóúñ¿¡ÁÉÍÓÚÑ]');

/// Los renglones visibles que suenan a castellano.
List<String> _castellanoEncontrado(WidgetTester tester) => [
      for (final renglon in _textoCrudo(tester).split('\n'))
        if (_letrasDeCastellano.hasMatch(renglon) ||
            _palabrasDeCastellano.hasMatch(_normalizado(renglon)))
          renglon,
    ];

void _sinCastellano(WidgetTester tester, String aviso) {
  expect(
    _castellanoEncontrado(tester),
    isEmpty,
    reason: '$aviso, en Locale(en), muestra castellano: algún string quedó '
        'hardcodeado en la forma móvil en vez de salir de AppL10n '
        '(hallazgo Codex, PR #1266).',
  );
}

/// Chequeos que corren sobre CADA variante renderizada, según su locale.
void _verificar(WidgetTester tester, String aviso, Locale locale) {
  _sinLlamadosAComprar(tester, aviso);
  if (locale.languageCode == 'en') _sinCastellano(tester, aviso);
}

Future<void> _abrirPaywallAlumnos(
  WidgetTester tester, {
  required PlanLimitPaywallForm form,
  required SubscriptionTier tier,
  PlanLimitReason reason = PlanLimitReason.planLimit,
  SubscriptionStatus? subscriptionStatus,
  Locale locale = const Locale('es', 'AR'),
}) async {
  debugPlanLimitPaywallForm = form;
  addTearDown(() => debugPlanLimitPaywallForm = null);

  await tester.pumpWidget(MaterialApp(
    // Sin esto, la forma móvil revienta con "Null check operator used on a
    // null value" apenas toca AppL10n (mismo motivo que documenta
    // `custom_exercise_limit_gate_test.dart`).
    localizationsDelegates: AppL10n.localizationsDelegates,
    supportedLocales: AppL10n.supportedLocales,
    locale: locale,
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showPlanLimitPaywall(
            context,
            currentTier: tier,
            reason: reason,
            subscriptionStatus: subscriptionStatus,
          ),
          child: const Text('abrir'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

Future<void> _abrirAvisoTrainer(
  WidgetTester tester, {
  required TrainerLimitNoticeForm form,
  required TrainerLimitKind kind,
  SubscriptionTier currentTier = SubscriptionTier.free,
  SubscriptionStatus subscriptionStatus = SubscriptionStatus.active,
  required int limit,
  required int count,
  Locale locale = const Locale('es', 'AR'),
}) async {
  debugTrainerLimitNoticeForm = form;
  addTearDown(() => debugTrainerLimitNoticeForm = null);

  await tester.pumpWidget(MaterialApp(
    // Sin esto, la forma móvil revienta con "Null check operator used on a
    // null value" apenas toca AppL10n (mismo motivo que documenta
    // `custom_exercise_limit_gate_test.dart`).
    localizationsDelegates: AppL10n.localizationsDelegates,
    supportedLocales: AppL10n.supportedLocales,
    locale: locale,
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showTrainerLimitNotice(
            context,
            kind: kind,
            currentTier: currentTier,
            subscriptionStatus: subscriptionStatus,
            limit: limit,
            count: count,
          ),
          child: const Text('abrir'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

typedef _Abrir = Future<void> Function(WidgetTester tester, Locale locale);

Future<void> _alumnos(
  WidgetTester tester,
  Locale locale, {
  required SubscriptionTier tier,
  PlanLimitReason reason = PlanLimitReason.planLimit,
  SubscriptionStatus? status,
}) =>
    _abrirPaywallAlumnos(
      tester,
      form: PlanLimitPaywallForm.sheet,
      tier: tier,
      reason: reason,
      subscriptionStatus: status,
      locale: locale,
    );

Future<void> _trainer(
  WidgetTester tester,
  Locale locale, {
  required TrainerLimitKind kind,
  SubscriptionTier tier = SubscriptionTier.free,
  SubscriptionStatus status = SubscriptionStatus.active,
  required int limit,
  required int count,
}) =>
    _abrirAvisoTrainer(
      tester,
      form: TrainerLimitNoticeForm.sheet,
      kind: kind,
      currentTier: tier,
      subscriptionStatus: status,
      limit: limit,
      count: count,
      locale: locale,
    );

/// CADA variante que el móvil puede renderizar de los tres avisos. Si se suma
/// un estado nuevo a cualquiera de los tres, entra acá — y queda cubierto en
/// las dos lenguas de una.
final List<({String nombre, _Abrir abrir})> _variantes = [
  // ── Alumnos ──
  (
    nombre: 'alumnos, en el tope (con tarjeta del siguiente plan)',
    abrir: (t, l) => _alumnos(t, l, tier: SubscriptionTier.free),
  ),
  (
    nombre: 'alumnos, Plan 2 (beneficio «sin límite»)',
    abrir: (t, l) => _alumnos(t, l, tier: SubscriptionTier.plan2),
  ),
  (
    nombre: 'alumnos, Plan 3 (plan a medida)',
    abrir: (t, l) => _alumnos(t, l, tier: SubscriptionTier.plan3),
  ),
  (
    nombre: 'alumnos, suscripción inactiva',
    abrir: (t, l) => _alumnos(
          t,
          l,
          tier: SubscriptionTier.plan1,
          reason: PlanLimitReason.subscriptionInactive,
          status: SubscriptionStatus.paused,
        ),
  ),
  // ── Ejercicios propios ──
  (
    nombre: 'ejercicios propios, en el tope',
    abrir: (t, l) => _trainer(t, l,
        kind: TrainerLimitKind.customExercises, limit: 20, count: 20),
  ),
  (
    nombre: 'ejercicios propios, Plan 2 (beneficio «sin límite»)',
    abrir: (t, l) => _trainer(t, l,
        kind: TrainerLimitKind.customExercises,
        tier: SubscriptionTier.plan2,
        limit: 120,
        count: 120),
  ),
  (
    nombre: 'ejercicios propios, pasado de tope',
    abrir: (t, l) => _trainer(t, l,
        kind: TrainerLimitKind.customExercises,
        tier: SubscriptionTier.plan1,
        limit: 60,
        count: 80),
  ),
  (
    nombre: 'ejercicios propios, suscripción inactiva',
    abrir: (t, l) => _trainer(t, l,
        kind: TrainerLimitKind.customExercises,
        tier: SubscriptionTier.plan1,
        status: SubscriptionStatus.paused,
        limit: 20,
        count: 20),
  ),
  (
    nombre: 'ejercicios propios, pausada con el límite del plan (piso prepago)',
    abrir: (t, l) => _trainer(t, l,
        kind: TrainerLimitKind.customExercises,
        tier: SubscriptionTier.plan1,
        status: SubscriptionStatus.paused,
        limit: 60,
        count: 60),
  ),
  (
    nombre: 'ejercicios propios, cuerpo genérico (tope a mano)',
    abrir: (t, l) => _trainer(t, l,
        kind: TrainerLimitKind.customExercises, limit: 45, count: 45),
  ),
  // ── Plantillas ──
  (
    nombre: 'plantillas, en el tope',
    abrir: (t, l) =>
        _trainer(t, l, kind: TrainerLimitKind.templates, limit: 3, count: 3),
  ),
  (
    nombre: 'plantillas, pasado de tope',
    abrir: (t, l) =>
        _trainer(t, l, kind: TrainerLimitKind.templates, limit: 3, count: 5),
  ),
  (
    nombre: 'plantillas, suscripción inactiva',
    abrir: (t, l) => _trainer(t, l,
        kind: TrainerLimitKind.templates,
        tier: SubscriptionTier.plan1,
        status: SubscriptionStatus.paused,
        limit: 3,
        count: 3),
  ),
  (
    nombre: 'plantillas, cuerpo genérico (tope a mano)',
    abrir: (t, l) =>
        _trainer(t, l, kind: TrainerLimitKind.templates, limit: 10, count: 10),
  ),
];

void main() {
  group('avisos de tope — móvil, sin llamado a comprar (3.1.3(f))', () {
    // Cada variante corre en LOS DOS locales que hablan los avisos móviles
    // (es_AR y en). Antes de este recorrido, ejercicios propios y plantillas
    // sólo se probaban en castellano, y el inglés (hardcodeado en la
    // unificación) nunca pasó por este guard.
    for (final locale in _kLocales) {
      for (final v in _variantes) {
        testWidgets('${v.nombre} (${locale.languageCode})', (tester) async {
          await v.abrir(tester, locale);
          _verificar(tester, v.nombre, locale);
        });
      }

      // Los SnackBars que disparan los botones del aviso de ALUMNOS también
      // son texto que el PF lee dentro del binario móvil.
      testWidgets(
          'alumnos, suscripción inactiva: el SnackBar de VER ESTADO '
          '(${locale.languageCode})', (tester) async {
        await _alumnos(
          tester,
          locale,
          tier: SubscriptionTier.plan1,
          reason: PlanLimitReason.subscriptionInactive,
          status: SubscriptionStatus.paused,
        );
        await tester.tap(find.byType(PlanLimitAccentButton));
        await tester.pumpAndSettle();

        expect(find.byType(SnackBar), findsOneWidget);
        _verificar(tester, 'el SnackBar de VER ESTADO', locale);
      });

      testWidgets(
          'alumnos, plan a medida: el SnackBar de CONTACTANOS '
          '(${locale.languageCode})', (tester) async {
        await _alumnos(tester, locale, tier: SubscriptionTier.plan3);
        await tester.tap(find.byType(PlanLimitAccentButton));
        await tester.pumpAndSettle();

        expect(find.byType(SnackBar), findsOneWidget);
        _verificar(tester, 'el SnackBar de CONTACTANOS', locale);
      });

      // La bifurcación tiene que EXISTIR: si esto no encontrara "PASATE A" en
      // la WEB, el barrido de arriba no probaría nada — un texto que nunca
      // aparece en ningún lado no es "neutral", es "no implementado". La WEB
      // no se traduce (i18n Fase W3): "PASATE A" tiene que seguir apareciendo
      // aunque el Locale sea inglés.
      testWidgets(
          'control: en WEB, ejercicios sí vende ("PASATE A") '
          '(${locale.languageCode})', (tester) async {
        await _abrirAvisoTrainer(
          tester,
          form: TrainerLimitNoticeForm.dialog,
          kind: TrainerLimitKind.customExercises,
          limit: 20,
          count: 20,
          locale: locale,
        );
        expect(find.textContaining('PASATE A'), findsOneWidget);
      });
    }

    // ── Controles de los detectores ─────────────────────────────────────────
    //
    // Un guard que nunca encuentra nada es indistinguible de uno roto. Cada
    // detector se prueba contra un texto que SÍ tiene que agarrar.

    testWidgets(
        'control: las agujas de compra SÍ encuentran el llamado de la WEB',
        (tester) async {
      await _abrirPaywallAlumnos(
        tester,
        form: PlanLimitPaywallForm.dialog,
        tier: SubscriptionTier.free,
      );
      // «Para sumar más, subí de plan.» y «PASATE A PLAN 1».
      expect(_llamadosEncontrados(tester),
          containsAll(['subi de plan', 'pasate']));
    });

    testWidgets(
        'control: el detector de castellano SÍ encuentra el castellano de '
        'es_AR', (tester) async {
      await _trainer(
        tester,
        const Locale('es', 'AR'),
        kind: TrainerLimitKind.customExercises,
        limit: 20,
        count: 20,
      );
      final hallazgos = _castellanoEncontrado(tester);
      expect(hallazgos, isNotEmpty);
      // El título, el cuerpo y el botón: los tres son castellano.
      expect(hallazgos, contains('TOPE DE EJERCICIOS PROPIOS'));
      expect(hallazgos, contains('VER PLANES'));
    });

    testWidgets(
        'control: el detector de castellano NO da falsos positivos sobre '
        'un aviso en inglés', (tester) async {
      await _trainer(
        tester,
        const Locale('en'),
        kind: TrainerLimitKind.customExercises,
        limit: 20,
        count: 20,
      );
      // El árbol incluye el botón del harness («abrir»), que tampoco matchea.
      expect(_castellanoEncontrado(tester), isEmpty);
      expect(find.text('CUSTOM EXERCISE LIMIT'), findsOneWidget);
    });
  });
}
