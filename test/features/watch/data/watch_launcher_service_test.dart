import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/watch/data/watch_bridge.dart';
import 'package:treino/features/watch/data/watch_launcher_service.dart';

class _MockBridge extends Mock implements WatchBridge {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockBridge bridge;
  late MethodChannel channel;
  late List<MethodCall> llamadas;
  Object? aTirar;
  bool? respuesta;

  setUp(() {
    bridge = _MockBridge();
    channel = const MethodChannel(WatchLauncherService.channelName);
    llamadas = <MethodCall>[];
    aTirar = null;
    respuesta = true;

    when(() => bridge.isSupported).thenAnswer((_) async => true);
    when(() => bridge.isPaired).thenAnswer((_) async => true);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      llamadas.add(call);
      if (aTirar != null) throw aTirar!;
      return respuesta;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  WatchLauncherService build() =>
      WatchLauncherService(bridge: bridge, channel: channel);

  test('con reloj emparejado cruza el canal nativo', () async {
    expect(await build().launchWorkout(), isTrue);
    expect(llamadas.single.method, WatchLauncherService.launchMethod);
  });

  test('sin reloj emparejado NO cruza el canal', () async {
    when(() => bridge.isPaired).thenAnswer((_) async => false);

    expect(await build().launchWorkout(), isFalse);
    expect(llamadas, isEmpty);
  });

  test('en una plataforma sin relojes NO cruza el canal', () async {
    when(() => bridge.isSupported).thenAnswer((_) async => false);

    expect(await build().launchWorkout(), isFalse);
    expect(llamadas, isEmpty);
  });

  // El corazón del contrato: esto es un AGREGADO. Si tira, el entreno del
  // teléfono tiene que arrancar igual. Sin el try/catch del servicio, estos dos
  // se ponen en rojo con la excepción propagando hasta el notifier.
  test('si el canal no está registrado, devuelve false sin tirar', () async {
    aTirar = MissingPluginException('sin canal');

    expect(await build().launchWorkout(), isFalse);
  });

  test('si el lado nativo falla, devuelve false sin tirar', () async {
    aTirar = PlatformException(code: 'health_denied');

    expect(await build().launchWorkout(), isFalse);
  });

  test('un null del lado nativo se lee como false, no como éxito', () async {
    respuesta = null;

    expect(await build().launchWorkout(), isFalse);
  });
}
