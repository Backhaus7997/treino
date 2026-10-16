// #1510: el descanso entre series sólo existía en el reloj. La barra cuenta
// contra un instante fijo con `clock`, que el tiempo falso del test adelanta.
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
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
}
