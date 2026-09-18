/// cancel_subscription_dialog_test.dart — lo que el diálogo de baja PROMETE.
///
/// Los tres puntos de la confirmación no son copy: son lo que los Términos de
/// Suscripción §7 dicen, publicado, y lo que Mercado Pago hace de verdad. Si
/// alguno desaparece de la pantalla, el PF toma la decisión con menos
/// información de la que le corresponde.
///
/// Los tests afirman la CONDICIÓN, no las palabras exactas: se busca por lo que
/// la frase tiene que comunicar, para que reescribir el copy no los rompa.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/cancel_subscription_dialog.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/plan_cancel.dart';

/// Monta el diálogo ya abierto.
Future<void> abrir(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showCancelSubscriptionDialog(context),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

/// Busca un texto por fragmento, sin depender de la redacción entera.
Finder porFragmento(String fragmento) => find.byWidgetPredicate(
      (w) => w is Text && (w.data ?? '').contains(fragmento),
    );

void main() {
  setUp(() {
    // `kIsWeb` es false bajo `flutter test`: sin esto el diálogo no puede
    // cancelar y la mitad de los casos sería inalcanzable.
    debugPlanCancel = planCancelFor(isWeb: true);
  });

  tearDown(() {
    debugPlanCancel = null;
    debugPlanCancelCaller = null;
  });

  group('lo que dice ANTES de dar de baja', () {
    testWidgets('promete el acceso hasta el fin del período pagado',
        (tester) async {
      // Términos de Suscripción §7, publicado.
      await abrir(tester);
      expect(porFragmento('hasta el final del período'), findsOneWidget);
    });

    testWidgets('avisa que la baja es DEFINITIVA', (tester) async {
      // Es lo que cambia la decisión: un preapproval cancelado no se reactiva
      // en Mercado Pago. Sin esto alguien aprieta creyendo que puede volver
      // atrás mañana.
      await abrir(tester);
      expect(porFragmento('definitiva'), findsOneWidget);
    });

    testWidgets('aclara que no se borra nada', (tester) async {
      await abrir(tester);
      expect(porFragmento('No se borra nada'), findsOneWidget);
    });

    testWidgets('se puede salir sin dar de baja', (tester) async {
      await abrir(tester);
      expect(find.text('VOLVER'), findsOneWidget);

      await tester.tap(find.text('VOLVER'));
      await tester.pumpAndSettle();

      expect(find.text('DAR DE BAJA'), findsNothing);
    });
  });

  group('lo que dice DESPUÉS', () {
    testWidgets('con fecha, la muestra en formato argentino', (tester) async {
      debugPlanCancelCaller = () async => ResultadoDeBaja(
            estado: EstadoDeBaja.dadaDeBaja,
            accesoHasta: DateTime(2026, 10, 3, 12),
          );

      await abrir(tester);
      await tester.tap(find.text('DAR DE BAJA'));
      await tester.pumpAndSettle();

      expect(porFragmento('03/10/2026'), findsOneWidget);
    });

    testWidgets('sin fecha, igual confirma la baja', (tester) async {
      // El hecho que importa —ya no se le cobra— no depende de la fecha.
      // Quedarse callado porque falta un dato secundario sería peor.
      debugPlanCancelCaller =
          () async => const ResultadoDeBaja(estado: EstadoDeBaja.dadaDeBaja);

      await abrir(tester);
      await tester.tap(find.text('DAR DE BAJA'));
      await tester.pumpAndSettle();

      expect(porFragmento('No se te va a cobrar'), findsOneWidget);
    });

    testWidgets('⚠️ si falla, dice que la suscripción SIGUE como estaba',
        (tester) async {
      // LA aserción del archivo. Un error que se lea como baja exitosa hace
      // que el PF deje de mirar su tarjeta mientras el cobro le sigue
      // llegando. El mensaje tiene que desmentirlo explícitamente.
      debugPlanCancelCaller =
          () async => const ResultadoDeBaja(estado: EstadoDeBaja.noDisponible);

      await abrir(tester);
      await tester.tap(find.text('DAR DE BAJA'));
      await tester.pumpAndSettle();

      expect(porFragmento('sigue como estaba'), findsOneWidget);
      expect(porFragmento('no se dio de baja'), findsOneWidget);
      // Y NO dice que se dio de baja.
      expect(porFragmento('SE DIO DE BAJA'), findsNothing);
    });

    testWidgets('⚠️ el cooldown NO dice que no hay nada que dar de baja',
        (tester) async {
      // Es el estado en el que cae quien reintenta despues de un fallo, que es
      // exactamente lo que el mensaje de fallo le pide hacer. Decirle que no
      // hay nada que dar de baja lo manda a su casa con la suscripcion viva.
      debugPlanCancelCaller =
          () async => const ResultadoDeBaja(estado: EstadoDeBaja.enfriando);

      await abrir(tester);
      await tester.tap(find.text('DAR DE BAJA'));
      await tester.pumpAndSettle();

      expect(porFragmento('Esperá unos segundos'), findsOneWidget);
      expect(find.text('NO HAY NADA QUE DAR DE BAJA'), findsNothing);
      expect(find.text('LISTO, SE DIO DE BAJA'), findsNothing);
    });

    testWidgets('sin suscripción no se presenta como un error', (tester) async {
      debugPlanCancelCaller = () async =>
          const ResultadoDeBaja(estado: EstadoDeBaja.sinSuscripcion);

      await abrir(tester);
      await tester.tap(find.text('DAR DE BAJA'));
      await tester.pumpAndSettle();

      expect(porFragmento('NO HAY NADA QUE DAR DE BAJA'), findsOneWidget);
    });
  });

  group('mientras espera', () {
    testWidgets('el botón se apaga para que no se pueda pedir dos veces',
        (tester) async {
      // Dos bajas seguidas no rompen nada —el servidor tiene su cooldown— pero
      // un botón que sigue vivo mientras la primera está en vuelo le hace creer
      // al PF que no pasó nada.
      final completer = Completer<ResultadoDeBaja>();
      debugPlanCancelCaller = () => completer.future;

      await abrir(tester);
      await tester.tap(find.text('DAR DE BAJA'));
      await tester.pump();

      expect(find.text('DANDO DE BAJA…'), findsOneWidget);
      expect(find.text('DAR DE BAJA'), findsNothing);

      completer.complete(
        const ResultadoDeBaja(estado: EstadoDeBaja.dadaDeBaja),
      );
      await tester.pumpAndSettle();
    });
  });
}
