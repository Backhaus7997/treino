import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/utils/deep_link_destination.dart';
import 'package:treino/features/coach_hub/presentation/widgets/invite_athlete_dialog.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;

/// Intercepta el portapapeles y devuelve lo último que se copió.
///
/// Va en TODOS los tests que tocan copiar, no sólo en el que lo assertea: sin
/// handler, `Clipboard.setData` no resuelve nunca y el `await` de adentro deja
/// el acuse sin pintarse. El síntoma es «no encuentro ¡Copiado!», que se lee
/// como un bug de la UI y no como lo que es.
ValueGetter<String?> _interceptarPortapapeles(WidgetTester tester) {
  String? copiado;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copiado = (call.arguments as Map)['text'] as String?;
      }
      return null;
    },
  );
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
  return () => copiado;
}

Future<void> _pump(WidgetTester tester, {String? uid = 'pf-1'}) async {
  await tester.binding.setSurfaceSize(const Size(900, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [currentUidProvider.overrideWithValue(uid)],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: InviteAthleteDialog()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// El texto del link que la caja muestra.
String _linkEnPantalla(WidgetTester tester) => tester
    .widget<SelectableText>(
      find.descendant(
        of: find.byKey(const Key('invite_dialog_link')),
        matching: find.byType(SelectableText),
      ),
    )
    .data!;

void main() {
  testWidgets('el link que muestra es el que el parser resuelve a ESE PF',
      (tester) async {
    await _pump(tester, uid: 'pf-42');

    // Lo que importa del diálogo no es que dibuje una caja: es que lo que el
    // PF copia lleve a vincularse CON ÉL. Se verifica extremo a extremo,
    // parseando lo que quedó en pantalla.
    final destino = DeepLinkDestination.fromQuery(
      Uri.parse(_linkEnPantalla(tester)).queryParameters,
    );

    expect(destino!.to, DeepLinkTo.invitacion);
    expect(destino.trainerId, 'pf-42');
  });

  testWidgets('copiar deja el link en el portapapeles y lo acusa',
      (tester) async {
    final copiado = _interceptarPortapapeles(tester);
    await _pump(tester);
    final enPantalla = _linkEnPantalla(tester);

    expect(find.text('Copiar link'), findsOneWidget);
    await tester.tap(find.byKey(const Key('invite_dialog_copy')));
    await tester.pumpAndSettle();

    expect(copiado(), enPantalla, reason: 'copia el MISMO link que muestra');
    // Sin acuse, el PF no sabe si el click hizo algo.
    expect(find.text('¡Copiado!'), findsOneWidget);
  });

  testWidgets('el acuse se apaga solo', (tester) async {
    _interceptarPortapapeles(tester);
    await _pump(tester);

    await tester.tap(find.byKey(const Key('invite_dialog_copy')));
    // Dos `pump` acotados y no `pumpAndSettle`: settle avanza el reloj falso
    // de a 100 ms hasta que no queden frames, se come los 2 s del acuse y lo
    // encuentra ya apagado.
    await tester.pump();
    await tester.pump();
    expect(find.text('¡Copiado!'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Copiar link'), findsOneWidget,
        reason: 'vuelve solo, para poder copiar de nuevo');
  });

  testWidgets('sin sesión no ofrece un link roto', (tester) async {
    await _pump(tester, uid: null);

    // Mostrar una caja vacía o un link sin PF sería peor: el PF lo comparte,
    // el alumno lo abre y no pasa nada, y nadie sabe por qué.
    expect(find.byKey(const Key('invite_dialog_link')), findsNothing);
    expect(find.byKey(const Key('invite_dialog_copy')), findsNothing);
    expect(find.textContaining('sesión'), findsOneWidget);
    expect(find.byKey(const Key('invite_dialog_close')), findsOneWidget);
  });

  testWidgets('el link es seleccionable a mano', (tester) async {
    await _pump(tester);

    // Si el portapapeles falla —permisos del navegador, contexto no seguro—
    // seleccionar a mano es la única salida que le queda al PF.
    expect(
      find.descendant(
        of: find.byKey(const Key('invite_dialog_link')),
        matching: find.byType(SelectableText),
      ),
      findsOneWidget,
    );
  });
}
