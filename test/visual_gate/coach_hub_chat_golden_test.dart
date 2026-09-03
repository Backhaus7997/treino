/// Gate de regresión visual — Chat del Coach Hub (#761).
///
/// ## Por qué Chat
///
/// Es el único layout de dos paneles del Hub: lista de hilos a la izquierda,
/// detalle y composer a la derecha. Ese reparto de ancho no vive en ninguna
/// otra pantalla, así que ningún otro golden lo cubre.
///
/// También es donde el reloj se ve más directo: `_formatTimestamp` decide entre
/// `HH:mm` (hoy), día abreviado (esta semana) y `dd/MM` (más viejo) comparando
/// contra ahora. Sin el seam congelado, los tres formatos rotan solos y el
/// golden cambia de forma sin que nadie toque la UI.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/presentation/sections/chat/chat_section_screen.dart';

import 'gate_environment.dart';
import 'gate_harness.dart';
import 'gate_seed.dart';

void main() {
  group(
    'Visual gate — Coach Hub chat',
    skip: gateSkipReason(),
    () {
      useGateEnvironment();

      for (final theme in GateTheme.values) {
        testWidgets('desktop 1440x900 — ${theme.slug}', (tester) async {
          await pumpGate(
            tester,
            theme: theme,
            viewport: GateViewport.desktop,
            route: '/chat',
          );

          expect(find.byType(ChatSectionScreen), findsOneWidget);
          expect(
            find.text('No pudimos cargar tus chats.'),
            findsNothing,
            reason: 'un estado de error no es un baseline válido',
          );
          expect(
            find.textContaining(kGateAthletes[0].name),
            findsWidgets,
            reason: 'el hilo de hoy del seed llegó a la lista',
          );
          expectGatePalette(tester, theme);
          expectGateNoOverflow(tester);

          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(gateGoldenName(
              screen: 'chat',
              theme: theme,
              viewport: GateViewport.desktop,
            )),
          );
        });
      }
    },
  );
}
