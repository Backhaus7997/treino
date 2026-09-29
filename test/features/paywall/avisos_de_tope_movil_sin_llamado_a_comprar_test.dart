// Guard — los TRES avisos de tope del PF (alumnos, ejercicios propios,
// plantillas), en su forma MÓVIL, no llaman a comprar.
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
];

/// Todo el texto visible del árbol actual, normalizado y concatenado.
String _textoVisible(WidgetTester tester) => _normalizado(
      tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('\n'),
    );

void _sinLlamadosAComprar(WidgetTester tester, String aviso) {
  final texto = _textoVisible(tester);
  for (final aguja in _llamadosAComprar) {
    expect(
      texto.contains(aguja),
      isFalse,
      reason: '$aviso (móvil) dice «$aguja» — Guideline 3.1.3(f): el '
          'binario móvil no puede tener calls to action de compra.',
    );
  }
}

Future<void> _abrirPaywallAlumnos(
  WidgetTester tester, {
  required PlanLimitPaywallForm form,
  required SubscriptionTier tier,
  PlanLimitReason reason = PlanLimitReason.planLimit,
  SubscriptionStatus? subscriptionStatus,
}) async {
  debugPlanLimitPaywallForm = form;
  addTearDown(() => debugPlanLimitPaywallForm = null);

  await tester.pumpWidget(MaterialApp(
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
  required int limit,
  required int count,
}) async {
  debugTrainerLimitNoticeForm = form;
  addTearDown(() => debugTrainerLimitNoticeForm = null);

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showTrainerLimitNotice(
            context,
            kind: kind,
            currentTier: currentTier,
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

void main() {
  group('avisos de tope — móvil, sin llamado a comprar (3.1.3(f))', () {
    testWidgets('alumnos, en el tope', (tester) async {
      await _abrirPaywallAlumnos(
        tester,
        form: PlanLimitPaywallForm.sheet,
        tier: SubscriptionTier.free,
      );
      _sinLlamadosAComprar(tester, 'el aviso de alumnos (en el tope)');
    });

    testWidgets('alumnos, suscripción inactiva', (tester) async {
      await _abrirPaywallAlumnos(
        tester,
        form: PlanLimitPaywallForm.sheet,
        tier: SubscriptionTier.plan1,
        reason: PlanLimitReason.subscriptionInactive,
        subscriptionStatus: SubscriptionStatus.paused,
      );
      _sinLlamadosAComprar(
          tester, 'el aviso de alumnos (suscripción inactiva)');
    });

    testWidgets('ejercicios propios, en el tope', (tester) async {
      await _abrirAvisoTrainer(
        tester,
        form: TrainerLimitNoticeForm.sheet,
        kind: TrainerLimitKind.customExercises,
        limit: 20,
        count: 20,
      );
      _sinLlamadosAComprar(tester, 'el aviso de ejercicios (en el tope)');
    });

    testWidgets('ejercicios propios, pasado de tope', (tester) async {
      await _abrirAvisoTrainer(
        tester,
        form: TrainerLimitNoticeForm.sheet,
        kind: TrainerLimitKind.customExercises,
        currentTier: SubscriptionTier.plan1,
        limit: 60,
        count: 80,
      );
      _sinLlamadosAComprar(tester, 'el aviso de ejercicios (pasado de tope)');
    });

    testWidgets('plantillas, en el tope', (tester) async {
      await _abrirAvisoTrainer(
        tester,
        form: TrainerLimitNoticeForm.sheet,
        kind: TrainerLimitKind.templates,
        limit: 3,
        count: 3,
      );
      _sinLlamadosAComprar(tester, 'el aviso de plantillas (en el tope)');
    });

    testWidgets('plantillas, pasado de tope', (tester) async {
      await _abrirAvisoTrainer(
        tester,
        form: TrainerLimitNoticeForm.sheet,
        kind: TrainerLimitKind.templates,
        limit: 3,
        count: 5,
      );
      _sinLlamadosAComprar(tester, 'el aviso de plantillas (pasado de tope)');
    });

    // La bifurcación tiene que EXISTIR: si esto no encontrara "PASATE A" en
    // la WEB, el barrido de arriba no probaría nada — un texto que nunca
    // aparece en ningún lado no es "neutral", es "no implementado".
    testWidgets('control: en WEB, ejercicios sí vende ("PASATE A")',
        (tester) async {
      await _abrirAvisoTrainer(
        tester,
        form: TrainerLimitNoticeForm.dialog,
        kind: TrainerLimitKind.customExercises,
        limit: 20,
        count: 20,
      );
      expect(find.textContaining('PASATE A'), findsOneWidget);
    });
  });
}
