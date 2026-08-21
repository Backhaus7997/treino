import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/watch/data/watch_bridge.dart';
import 'package:treino/features/watch/data/watch_timer_service.dart';

class _MockBridge extends Mock implements WatchBridge {}

void main() {
  late _MockBridge bridge;
  late WatchTimerService service;

  final fin = DateTime.fromMillisecondsSinceEpoch(1800000060000, isUtc: true);

  Future<bool> arrancar() => service.start(
        exerciseId: 'plancha',
        setNumber: 2,
        totalSeconds: 60,
        endsAt: fin,
      );

  setUp(() {
    bridge = _MockBridge();
    service = WatchTimerService(bridge: bridge);
    when(() => bridge.isSupported).thenAnswer((_) async => true);
    when(() => bridge.isPaired).thenAnswer((_) async => true);
    when(() => bridge.isReachable).thenAnswer((_) async => true);
    when(() => bridge.sendMessage(any())).thenAnswer((_) async {});
  });

  test('manda el kind que el reloj filtra, y el INSTANTE de fin', () async {
    expect(await arrancar(), isTrue);

    final sent = verify(() => bridge.sendMessage(captureAny())).captured.single
        as Map<String, dynamic>;
    expect(sent['kind'], 'watchTimer');
    expect(sent['action'], 'start');
    expect(sent['exerciseId'], 'plancha');
    expect(sent['setNumber'], 2);
    expect(sent['totalSeconds'], 60);
    // Viaja el instante de fin y no los segundos que faltan: así los dos lados
    // derivan la cuenta del mismo punto contra su propio reloj de pared, sin
    // tráfico por segundo. Un envío que llega tarde sigue dando el número bien.
    expect(sent['endsAtMs'], 1800000060000);
    expect(sent.containsKey('remainingSeconds'), isFalse);
  });

  test('el instante de fin NO entra en 32 bits, y viaja entero', () async {
    await arrancar();
    final sent = verify(() => bridge.sendMessage(captureAny())).captured.single
        as Map<String, dynamic>;
    // En watchOS `Int` es de 32 bits (arm64_32). Este valor lo excede por un
    // factor de ~832, así que el lado Swift TIENE que leerlo como Int64 — ver
    // `PhoneTimerMirror.swift`. El test lo deja escrito de este lado también:
    // si alguien "achicara" el payload a un offset, la presión desaparecería.
    expect(sent['endsAtMs'] as int, greaterThan(2147483647));
  });

  test('cancelar viaja sin datos de serie', () async {
    expect(await service.cancel(), isTrue);

    final sent = verify(() => bridge.sendMessage(captureAny())).captured.single
        as Map<String, dynamic>;
    expect(sent['kind'], 'watchTimer');
    expect(sent['action'], 'cancel');
    expect(sent.containsKey('endsAtMs'), isFalse);
  });

  test('NO usa updateApplicationContext: ahí vive la credencial', () async {
    await arrancar();
    // El contexto de salida es uno solo y se pisa entero. Mandar el cronómetro
    // por ahí borraría la credencial del reloj y lo dejaría sin poder hablar
    // con Firestore.
    verifyNever(() => bridge.updateApplicationContext(any()));
  });

  test('sin reloj emparejado no manda nada', () async {
    when(() => bridge.isPaired).thenAnswer((_) async => false);
    expect(await arrancar(), isFalse);
    verifyNever(() => bridge.sendMessage(any()));
  });

  test('reloj no alcanzable: no intenta, y no rompe', () async {
    when(() => bridge.isReachable).thenAnswer((_) async => false);
    // Con la app del reloj cerrada la orden se pierde, y está bien: el caso
    // real es entrenar con el reloj en la muñeca. El teléfono cuenta igual.
    expect(await arrancar(), isFalse);
    verifyNever(() => bridge.sendMessage(any()));
  });

  test('plataforma sin soporte de reloj: inerte', () async {
    when(() => bridge.isSupported).thenAnswer((_) async => false);
    expect(await arrancar(), isFalse);
    verifyNever(() => bridge.sendMessage(any()));
  });

  test('una falla del puente NO se propaga', () async {
    when(() => bridge.sendMessage(any())).thenThrow(Exception('canal muerto'));
    // Corre desde el player, en el camino caliente: un cronómetro que no llega
    // al reloj no puede romper la pantalla donde el atleta está entrenando.
    expect(await arrancar(), isFalse);
    expect(await service.cancel(), isFalse);
  });
}
