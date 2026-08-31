// El panel de entrada rápida (#870), aislado.
//
// Agregar un ejercicio son hoy varios taps: abrir el picker, buscar, elegir, y
// después cargar sets, reps y peso a mano. Para quien ya sabe lo que quiere,
// eso es fricción pura.
//
// El panel es tonto a propósito: recibe los resultados ya filtrados y devuelve
// cuál se eligió. Quién busca en el catálogo es la pantalla.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/workout/presentation/widgets/quick_entry_panel.dart';
import 'package:treino/features/workout/presentation/widgets/quick_entry_parser.dart';
import 'package:treino/l10n/app_l10n.dart';

const _kResultados = [
  QuickEntryResult(id: 'bench', name: 'Press de Banca', muscleGroup: 'Pecho'),
  QuickEntryResult(id: 'ohp', name: 'Press Militar', muscleGroup: 'Hombros'),
  QuickEntryResult(id: 'inc', name: 'Press Inclinado', muscleGroup: 'Pecho'),
  QuickEntryResult(id: 'dec', name: 'Press Declinado', muscleGroup: 'Pecho'),
];

Future<TextEditingController> _montarPanel(
  WidgetTester tester, {
  String texto = 'banca 4x10 60',
  List<QuickEntryResult> resultados = _kResultados,
  void Function(QuickEntryResult)? onSelect,
  VoidCallback? onConfirm,
  QuickEntryResult? elegido,
  ThemeData? tema,
}) async {
  final ctrl = TextEditingController(text: texto);
  addTearDown(ctrl.dispose);
  final foco = FocusNode();
  addTearDown(foco.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: tema ?? AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(
        body: QuickEntryPanel(
          controller: ctrl,
          focusNode: foco,
          entry: parseQuickEntry(texto),
          results: resultados,
          selected: elegido,
          onSelect: onSelect ?? (_) {},
          onConfirm: onConfirm ?? () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ctrl;
}

String _hint(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('quick_entry_hint'))).data!;

void main() {
  group('resultados', () {
    testWidgets('los muestra todos, con scroll si no entran', (tester) async {
      // Cortaba en tres y sin scroll: buscar "sentadilla" en un catálogo real
      // devuelve más variantes que eso, y las que no entraban eran justo las
      // que se buscaban. Revisión en device del 31/08.
      await _montarPanel(tester);
      expect(find.text('Press de Banca'), findsOneWidget);
      expect(find.text('Press Declinado'), findsOneWidget,
          reason: 'el cuarto ya no se pierde');
      expect(find.byKey(const Key('quick_entry_results')), findsOneWidget);
    });

    testWidgets('cada fila lleva su músculo', (tester) async {
      await _montarPanel(tester);
      expect(find.text('Hombros'), findsOneWidget);
    });

    testWidgets('la prescripción parseada va a la derecha', (tester) async {
      await _montarPanel(tester, texto: 'press 4x10 60');
      expect(find.text('4×10 · 60kg'), findsWidgets);
    });

    testWidgets('sin prescripción no se muestra nada a la derecha',
        (tester) async {
      await _montarPanel(tester, texto: 'press');
      expect(find.textContaining('×'), findsNothing);
    });

    testWidgets('tocar una fila la ELIGE, no la agrega', (tester) async {
      // El cambio central de la revisión del 31/08: el tap seleccionaba y
      // agregaba en el mismo gesto. Como el nombre se escribe primero, el
      // atajo se cerraba justo antes de poder decir "4x10 55".
      QuickEntryResult? elegido;
      var confirmaciones = 0;
      await _montarPanel(
        tester,
        onSelect: (r) => elegido = r,
        onConfirm: () => confirmaciones++,
      );

      await tester.tap(find.byKey(const Key('quick_entry_result_1')));
      expect(elegido?.id, 'ohp');
      expect(confirmaciones, 0,
          reason: 'elegir NO agrega: para eso está AGREGAR');
    });

    testWidgets('la fila entera es el target y llega a 48', (tester) async {
      await _montarPanel(tester);
      expect(
        tester.getSize(find.byKey(const Key('quick_entry_result_0'))).height,
        greaterThanOrEqualTo(48),
        reason: 'el nombre solo sería un blanco de 14 px de alto',
      );
    });

    testWidgets('sin resultados el panel sigue armando', (tester) async {
      await _montarPanel(tester, resultados: const []);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('quick_entry_field')), findsOneWidget);
    });
  });

  group('una vez elegido', () {
    testWidgets('la lista desaparece y aparece AGREGAR', (tester) async {
      await _montarPanel(tester, elegido: _kResultados.first);

      expect(find.byKey(const Key('quick_entry_results')), findsNothing,
          reason: 'ya elegiste: lo que se escribe ahora es la prescripción');
      expect(find.byKey(const Key('quick_entry_confirm')), findsOneWidget);
    });

    testWidgets('AGREGAR confirma', (tester) async {
      var confirmaciones = 0;
      await _montarPanel(
        tester,
        elegido: _kResultados.first,
        onConfirm: () => confirmaciones++,
      );

      await tester.tap(find.byKey(const Key('quick_entry_confirm')));
      expect(confirmaciones, 1);
    });

    testWidgets('sin elegir todavía no hay AGREGAR', (tester) async {
      await _montarPanel(tester);
      expect(find.byKey(const Key('quick_entry_confirm')), findsNothing);
    });

    testWidgets('AGREGAR llega al mínimo táctil', (tester) async {
      await _montarPanel(tester, elegido: _kResultados.first);
      expect(
        tester.getSize(find.byKey(const Key('quick_entry_confirm'))).height,
        greaterThanOrEqualTo(48),
      );
    });
  });

  group('el hint dice qué va a pasar', () {
    testWidgets('con prescripción, la anuncia antes de tocar', (tester) async {
      await _montarPanel(
        tester,
        texto: 'banca 4x10 60',
        elegido: _kResultados.first,
      );
      expect(_hint(tester), 'Se agrega como 4 sets × 10 a 60 kg.');
    });

    testWidgets('una pirámide se lista set por set', (tester) async {
      await _montarPanel(
        tester,
        texto: 'banca 4x10, 8, 6, 4',
        elegido: _kResultados.first,
      );
      expect(_hint(tester), contains('10 · 8 · 6 · 4'),
          reason: 'repetir cuatro veces el mismo número no informa; una '
              'pirámide sí');
    });

    testWidgets('una descarga también', (tester) async {
      await _montarPanel(
        tester,
        texto: 'banca 4x10 55, 45, 35, 25',
        elegido: _kResultados.first,
      );
      expect(_hint(tester), contains('55 · 45 · 35 · 25'));
    });

    testWidgets('sin peso lo dice, en vez de callarlo', (tester) async {
      await _montarPanel(
        tester,
        texto: 'dominadas 4x8',
        elegido: _kResultados.first,
      );
      expect(_hint(tester), contains('sin peso'));
    });

    testWidgets('elegido pero sin números, enseña la sintaxis', (tester) async {
      await _montarPanel(
        tester,
        texto: 'banca ',
        elegido: _kResultados.first,
      );
      expect(_hint(tester), contains('4x10'));
      expect(_hint(tester), contains('baja las reps'));
    });

    testWidgets('sin elegir, dice que hay que elegir', (tester) async {
      await _montarPanel(tester, texto: '');
      expect(_hint(tester), contains('tocalo'));
    });

    testWidgets('un set solo no dice "1 sets"', (tester) async {
      await _montarPanel(
        tester,
        texto: 'banca 1x10 60',
        elegido: _kResultados.first,
      );
      expect(_hint(tester), 'Se agrega como 1 set × 10 a 60 kg.');
    });
  });

  group('QuickEntryToggle', () {
    Future<void> montar(WidgetTester tester,
        {required bool activo, VoidCallback? onTap}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
          home: Scaffold(
            body: Align(
              alignment: Alignment.centerLeft,
              child: QuickEntryToggle(
                active: activo,
                onTap: onTap ?? () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('llega al mínimo táctil de 48', (tester) async {
      await montar(tester, activo: false);
      expect(
        tester.getSize(find.byKey(const Key('quick_entry_toggle'))).height,
        48,
        reason: 'el handoff pedía 36; la épica fija 48 para todo target',
      );
    });

    testWidgets('se anuncia como un toggle, con su estado', (tester) async {
      final handle = tester.ensureSemantics();
      await montar(tester, activo: true);
      final s =
          tester.getSemantics(find.byKey(const Key('quick_entry_toggle')));
      expect(s.label, 'Entrada rápida');
      handle.dispose();
    });

    testWidgets('responde al tap', (tester) async {
      var toques = 0;
      await montar(tester, activo: false, onTap: () => toques++);
      await tester.tap(find.byKey(const Key('quick_entry_toggle')));
      expect(toques, 1);
    });
  });

  group('contraste — medido en las dos paletas', () {
    Color componer(Color fg, Color bg) {
      final b = Color.alphaBlend(fg, bg);
      double q(double v) => (v * 255).round() / 255;
      return Color.from(alpha: 1.0, red: q(b.r), green: q(b.g), blue: q(b.b));
    }

    double contraste(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      final hi = la > lb ? la : lb;
      final lo = la > lb ? lb : la;
      return (hi + 0.05) / (lo + 0.05);
    }

    for (final entry in <String, AppPalette>{
      'dark': AppPalette.mintMagenta,
      'light': AppPalette.mintMagentaLight,
    }.entries) {
      final p = entry.value;

      test('${entry.key}: el borde del panel se ve — por eso va accentText',
          () {
        expect(contraste(p.accentText, p.bgCard), greaterThanOrEqualTo(3.0),
            reason: 'el borde es lo que separa el panel de la cabecera del '
                'día: le aplica el 3:1 de SC 1.4.11');
      });

      test('${entry.key}: `accent` como borde NO habría servido en light', () {
        final conAccent = contraste(p.accent, p.bgCard);
        if (entry.key == 'light') {
          expect(conAccent, lessThan(3.0),
              reason: 'el mint pleno como LÍNEA sobre papel mide '
                  '${conAccent.toStringAsFixed(2)}:1');
        }
      });

      test('${entry.key}: el toggle apagado se lee igual', () {
        final fondo = componer(p.surfaceSubtle, p.bgCard);
        final ratio = contraste(componer(p.textMuted, fondo), fondo);
        expect(ratio, greaterThanOrEqualTo(4.5),
            reason: '${entry.key}: ${ratio.toStringAsFixed(2)}:1. Lo que '
                'distingue el estado apagado del encendido es el RELLENO '
                '(delta 33 por canal contra 14), no que el texto se esconda.');
      });

      test('${entry.key}: el toggle encendido cumple AA', () {
        final fondo = componer(p.accent.withAlpha(40), p.bgCard);
        expect(
          contraste(componer(p.accentText, fondo), fondo),
          greaterThanOrEqualTo(4.5),
        );
      });
    }
  });
}
