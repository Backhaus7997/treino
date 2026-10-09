// El scroll de EXPLORAR con el catálogo REAL de 50 plantillas (#1393).
//
// Reporte de device (iPhone 16, release): al llegar al final el scroll "se
// traba" y la barra flotante tapa las últimas plantillas. Dos cosas se miden
// acá, las dos contra el JSON que siembra `scripts/seed_templates.js`:
//
//  1. Que la última tarjeta pueda quedar ENTERA por encima de la barra. Dentro
//     del shell, la barra publica su caja en `MediaQuery.padding.bottom`
//     (ver el dartdoc de `TreinoBottomBar.minHeight`); acá se simula ese
//     inset y se mide la tarjeta contra el borde superior del vidrio.
//  2. Que las tarjetas se armen a demanda: con un Column se construían las 50
//     siempre, y cualquier rebuild de la pestaña las rehacía todas.
//
// No se mira el TIPO de los widgets de layout (Table, Column, slivers): esos
// tests revientan al migrar sin que nada cambie en pantalla. Se mide lo que
// ve el usuario: posiciones y cuántas tarjetas existen.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/paywall/application/athlete_entitlement_provider.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/unified_templates_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/presentation/widgets/plantillas_tab.dart';
import 'package:treino/features/workout/presentation/widgets/routine_card.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Lo que mide la caja de la barra dentro del shell con un home indicator de
/// 34 y los labels a la vista (medido, #830).
const double _kBarBox = 114;
const double _kAlto = 800;

Future<void> _pump(WidgetTester tester, List<Routine> catalogo) async {
  // Pantalla de teléfono (ancho de un Pro Max: con la fuente de fallback de los tests, la barra de preferencias desborda a 393), no el 800×600 default del
  // tester: con 600 de alto el SizedBox de 800 se corta y los números mienten.
  tester.view
    ..physicalSize = const Size(440, _kAlto)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        routinesProvider.overrideWith((ref) async => catalogo),
        currentAthleteLinkProvider.overrideWith((ref) => Stream.value(null)),
        communityTemplatesProvider.overrideWith((ref) => const []),
        // Sin candados: este test es del scroll, no del paywall. Con el
        // candado, el PremiumChip desborda a 393 de ancho SOLO en tests (la
        // fuente de fallback mide ~2,5× más ancho que la del design system).
        catalogLockActiveProvider.overrideWith((ref) => false),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: const EdgeInsets.only(bottom: _kBarBox),
            ),
            child: const Material(
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(height: _kAlto, child: PlantillasTab()),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}

Finder _tarjeta(String nombre) => find.ancestor(
      of: find.text(nombre.toUpperCase(), skipOffstage: false),
      matching: find.byType(RoutineCard, skipOffstage: false),
    );

void main() {
  late List<Routine> catalogo;

  setUpAll(() {
    catalogo = (jsonDecode(
      File('docs/video-catalog-audit/improved-templates.json')
          .readAsStringSync(),
    ) as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((t) => Routine.fromJson({...t, 'id': t['id']}))
        .toList();
  });

  testWidgets('el catálogo real tiene 50 plantillas', (tester) async {
    // Ancla de los otros dos tests: si el JSON cambia de tamaño, que lo diga
    // este y no un conteo de tarjetas que pasa por otra razón.
    expect(catalogo, hasLength(50));
  });

  testWidgets(
      'las tarjetas se arman a demanda: al abrir existen menos que las 50',
      (tester) async {
    await _pump(tester, catalogo);

    final construidas =
        find.byType(RoutineCard, skipOffstage: false).evaluate().length;
    expect(construidas, greaterThan(0));
    expect(construidas, lessThan(20),
        reason: 'con un Column se construían las 50 al abrir la pestaña');
  });

  testWidgets(
      'la última plantilla se puede scrollear ENTERA por encima de la barra',
      (tester) async {
    await _pump(tester, catalogo);

    final scroller = find.byType(Scrollable).first;
    // Arrastres de usuario hasta el final; varios porque con armado a demanda
    // el largo total se va descubriendo a medida que se scrollea.
    for (var i = 0; i < 12; i++) {
      await tester.drag(scroller, const Offset(0, -1500));
      await tester.pumpAndSettle();
    }

    final ultima = _tarjeta(catalogo.last.name);
    expect(ultima, findsOneWidget);
    final rect = tester.getRect(ultima);
    const bordeDeLaBarra = _kAlto - _kBarBox;
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(bordeDeLaBarra),
        reason: 'la barra flotante tapa la última plantilla');
    // Y con aire: el mismo gap de 20 que el resto de las pestañas del shell.
    expect(bordeDeLaBarra - rect.bottom, moreOrLessEquals(20, epsilon: 0.5));
  });
}
