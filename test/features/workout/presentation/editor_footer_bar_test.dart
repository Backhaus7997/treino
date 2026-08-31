// El pie fijo del editor de rutina (#868), aislado.
//
// Hasta este slice la validación corría al tocar guardar y salía por
// `SnackBar`: el usuario cargaba el plan entero, apretaba el CTA, y recién ahí
// se enteraba de que el día 2 había quedado vacío — en un mensaje efímero que
// además tapaba la pantalla.
//
// El cableado con la validación real lo cubre `routine_editor_footer_test.dart`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/workout/presentation/widgets/editor_footer_bar.dart';
import 'package:treino/l10n/app_l10n.dart';

Future<void> _montar(
  WidgetTester tester, {
  List<String> problemas = const [],
  String resumen = '2 días · 41 sets · todo listo',
  VoidCallback? onIr,
  VoidCallback? onGuardar,
  bool enviando = false,
  ThemeData? tema,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: tema ?? AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: EditorFooterBar(
            summary: resumen,
            problems: problemas,
            submitLabel: 'GUARDAR RUTINA',
            submitting: enviando,
            onSubmit: onGuardar ?? () {},
            onGoToProblem: onIr,
          ),
        ),
      ),
    ),
  );
  // `pump` y no `pumpAndSettle`: con `enviando` hay un spinner que nunca
  // termina, y settle esperaría a que la animación se detenga hasta el timeout.
  await tester.pump();
}

Finder get _linea => find.byKey(const Key('footer_status_line'));
Finder get _ir => find.byKey(const Key('footer_go_to_problem'));
Finder get _cta => find.byKey(const Key('footer_submit_button'));

void main() {
  group('sin problemas', () {
    testWidgets('muestra el resumen y no ofrece IR', (tester) async {
      await _montar(tester, onIr: () {});

      expect(tester.widget<Text>(_linea).data, '2 días · 41 sets · todo listo');
      expect(_ir, findsNothing, reason: 'no hay a dónde ir si no falta nada');
    });

    testWidgets('el CTA se ve encendido', (tester) async {
      await _montar(tester);
      final boton = tester.widget<ElevatedButton>(_cta);
      expect(boton.onPressed, isNotNull);
    });
  });

  group('con problemas', () {
    testWidgets('une los problemas con " · "', (tester) async {
      await _montar(
        tester,
        problemas: const [
          'Día 2: sin ejercicios',
          'Día 3: 2 sets sin completar'
        ],
      );

      expect(
        tester.widget<Text>(_linea).data,
        'Día 2: sin ejercicios · Día 3: 2 sets sin completar',
      );
    });

    testWidgets('el resumen no se muestra si falta algo', (tester) async {
      await _montar(tester, problemas: const ['Día 2: sin ejercicios']);
      expect(find.textContaining('todo listo'), findsNothing);
    });

    testWidgets('IR aparece y dispara la navegación', (tester) async {
      var viajes = 0;
      await _montar(
        tester,
        problemas: const ['Día 2: sin ejercicios'],
        onIr: () => viajes++,
      );

      expect(_ir, findsOneWidget);
      await tester.tap(_ir);
      expect(viajes, 1);
    });

    testWidgets('sin día al que ir, IR no se dibuja', (tester) async {
      await _montar(tester, problemas: const ['Falta el nombre del plan']);
      expect(_ir, findsNothing,
          reason: 'un nombre faltante no vive en ningún día');
    });

    testWidgets('IR llega al mínimo táctil de 48', (tester) async {
      await _montar(
        tester,
        problemas: const ['Día 2: sin ejercicios'],
        onIr: () {},
      );
      expect(tester.getSize(_ir).height, greaterThanOrEqualTo(48));
    });
  });

  group('el CTA apagado NO está muerto', () {
    testWidgets('con problemas sigue respondiendo al tap', (tester) async {
      var intentos = 0;
      await _montar(
        tester,
        problemas: const ['Día 2: sin ejercicios'],
        onGuardar: () => intentos++,
      );

      final boton = tester.widget<ElevatedButton>(_cta);
      expect(boton.onPressed, isNotNull,
          reason: 'es lo que deja que el tap muestre el primer problema y '
              'salte a su día — un botón muerto no explica nada');

      await tester.tap(_cta);
      expect(intentos, 1);
    });

    testWidgets('mientras guarda sí queda inerte', (tester) async {
      var intentos = 0;
      await _montar(tester, enviando: true, onGuardar: () => intentos++);

      expect(tester.widget<ElevatedButton>(_cta).onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(_cta, warnIfMissed: false);
      expect(intentos, 0, reason: 'un doble tap no puede mandar dos guardados');
    });

    testWidgets('mide 52 de alto', (tester) async {
      await _montar(tester);
      expect(tester.getSize(_cta).height, 52);
    });
  });

  group('las dos paletas', () {
    for (final entry in <String, ThemeData>{
      'dark': AppTheme.dark(),
      'light': AppTheme.light(),
    }.entries) {
      testWidgets('${entry.key}: monta sin overflow a 320 px', (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await _montar(
          tester,
          tema: entry.value,
          problemas: const [
            'Día 2: sin ejercicios',
            'Día 3: 4 sets sin completar',
          ],
          onIr: () {},
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
