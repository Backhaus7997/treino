// #1510: el descanso entre series sólo existía en el reloj. La barra cuenta
// contra un instante fijo con `clock`, que el tiempo falso del test adelanta.
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/workout/presentation/widgets/rest_timer_bar.dart';

void main() {
  testWidgets('cuenta para atrás, suma 15 s y avisa al llegar a cero',
      (tester) async {
    var hasta = clock.now().add(const Duration(seconds: 90));
    var total = 90;
    var termino = 0;

    Widget barra() => MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => RestTimerBar(
                key: ValueKey(hasta),
                endsAt: hasta,
                totalSeconds: total,
                onSkip: () {},
                onAddSeconds: (s) => setState(() {
                  hasta = hasta.add(Duration(seconds: s));
                  total += s;
                }),
                onDone: () => termino++,
              ),
            ),
          ),
        );

    await tester.pumpWidget(barra());
    expect(find.text('1:30'), findsOneWidget);

    await tester.pump(const Duration(seconds: 30));
    expect(find.text('1:00'), findsOneWidget);

    await tester.tap(find.text('+15 s'));
    await tester.pump();
    expect(find.text('1:15'), findsOneWidget);

    await tester.pump(const Duration(seconds: 75));
    expect(termino, 1);
  });

  // #1616 × #1617: la barra NO dice «terminó» antes del instante de fin, ni
  // por una fracción de milisegundo. Su `onDone` le llega a `RestEndAlerts`
  // como `update(null)`, y con el fin todavía por venir eso es un SALTAR: la
  // notificación se cancelaba justo cuando tenía que salir. Pasaba con los
  // fines redondeados al milisegundo del descanso compartido, porque la cuenta
  // truncaba la diferencia a ms y 0,4 ms daban «cero».
  testWidgets('no termina mientras quede una fracción de milisegundo',
      (tester) async {
    final hasta =
        clock.now().add(const Duration(seconds: 1, microseconds: 400));
    var termino = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: RestTimerBar(
          endsAt: hasta,
          totalSeconds: 1,
          onSkip: () {},
          onAddSeconds: (_) {},
          onDone: () => termino++,
        ),
      ),
    ));

    // El tick cae 400 µs ANTES del fin.
    await tester.pump(const Duration(seconds: 1));
    expect(termino, 0, reason: 'todavía no terminó');
    expect(clock.now().isBefore(hasta), isTrue);

    await tester.pump(const Duration(seconds: 1));
    expect(termino, 1);
  });

  // El lector de pantalla oye UN aviso al empezar y otro al terminar, no la
  // cuenta segundo a segundo (era un liveRegion con el número en el label).
  testWidgets('anuncia sólo al empezar y al terminar', (tester) async {
    final anuncios = <String>[];
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler(
      SystemChannels.accessibility,
      (dynamic msg) async {
        final data = (msg as Map)['data'] as Map;
        anuncios.add(data['message'] as String);
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockDecodedMessageHandler(SystemChannels.accessibility, null));

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: RestTimerBar(
          endsAt: clock.now().add(const Duration(seconds: 61)),
          totalSeconds: 61,
          onSkip: () {},
          onAddSeconds: (_) {},
          onDone: () {},
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 30));
    expect(anuncios, ['Descanso de 1 minuto 1 segundo']);

    await tester.pump(const Duration(seconds: 31));
    expect(anuncios, ['Descanso de 1 minuto 1 segundo', 'Terminó el descanso']);
  });
}
