import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/watch/data/watch_bridge.dart';
import 'package:treino/features/watch/data/watch_nudge_service.dart';

class _MockBridge extends Mock implements WatchBridge {}

void main() {
  late _MockBridge bridge;
  late WatchNudgeService service;

  setUp(() {
    bridge = _MockBridge();
    service = WatchNudgeService(bridge: bridge);
    when(() => bridge.isSupported).thenAnswer((_) async => true);
    when(() => bridge.isPaired).thenAnswer((_) async => true);
    when(() => bridge.isReachable).thenAnswer((_) async => true);
    when(() => bridge.sendMessage(any())).thenAnswer((_) async {});
  });

  test('manda el aviso con el kind que el reloj filtra', () async {
    expect(await service.nudge(), isTrue);

    final sent = verify(() => bridge.sendMessage(captureAny())).captured.single
        as Map<String, dynamic>;
    expect(sent['kind'], 'watchRefresh');
    expect(sent['reason'], 'activeRoutine');
  });

  test('NO usa updateApplicationContext: ahí vive la credencial', () async {
    await service.nudge();
    // El contexto es uno solo y se pisa entero. Mandar el aviso por ahí
    // borraría el payload de credencial de un reloj recién emparejado que
    // todavía no lo canjeó.
    verifyNever(() => bridge.updateApplicationContext(any()));
  });

  test('un nodo alcanzable ALCANZA, aunque isPaired diga que no', () async {
    // En Android `isPaired` no pregunta si hay un reloj: lista las apps
    // companion instaladas en el TELÉFONO. Cortar por eso dejaba sin aviso a un
    // reloj perfectamente conectado — y ese aviso es lo que despierta al
    // companion cuando el atleta arranca el entreno desde el celular.
    //
    // Un reloj alcanzable es, por definición, un reloj que está.
    when(() => bridge.isPaired).thenAnswer((_) async => false);

    expect(await service.nudge(), isTrue);
    verify(() => bridge.sendMessage(any())).called(1);
  });

  test('reloj no alcanzable: no intenta, y no rompe', () async {
    when(() => bridge.isReachable).thenAnswer((_) async => false);
    // `sendMessage` fallaría igual. El reloj se pone al día solo al cambiar de
    // página, así que perder el aviso degrada a lo que había antes.
    expect(await service.nudge(), isFalse);
    verifyNever(() => bridge.sendMessage(any()));
  });

  test('plataforma sin soporte de reloj: inerte', () async {
    when(() => bridge.isSupported).thenAnswer((_) async => false);
    expect(await service.nudge(), isFalse);
    verifyNever(() => bridge.sendMessage(any()));
  });

  test('una falla del puente NO se propaga', () async {
    when(() => bridge.sendMessage(any())).thenThrow(Exception('canal muerto'));
    // Un aviso que no llega no puede tumbar nada en el teléfono: corre en un
    // listener del perfil, en el camino caliente de la app.
    expect(await service.nudge(), isFalse);
  });
}
