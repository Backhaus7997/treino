import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/watch/data/watch_bridge.dart';
import 'package:treino/features/watch/data/watch_credential_service.dart';
import 'package:treino/features/watch/domain/watch_credential_payload.dart';

class _MockFunctions extends Mock implements FirebaseFunctions {}

class _MockCallable extends Mock implements HttpsCallable {}

class _MockResult extends Mock
    implements HttpsCallableResult<Map<String, dynamic>> {}

class _MockBridge extends Mock implements WatchBridge {}

void main() {
  late _MockFunctions functions;
  late _MockCallable callable;
  late _MockBridge bridge;
  late WatchCredentialService service;

  const uid = 'atleta-1';
  const apiKey = 'api-key-de-prueba';
  const projectId = 'treino-dev';

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    functions = _MockFunctions();
    callable = _MockCallable();
    bridge = _MockBridge();
    service = WatchCredentialService(
      functions: functions,
      bridge: bridge,
      apiKey: apiKey,
      projectId: projectId,
    );

    when(() => functions.httpsCallable(any())).thenReturn(callable);
    when(() => bridge.updateApplicationContext(any())).thenAnswer((_) async {});
  });

  void stubMintReturns(String token) {
    final result = _MockResult();
    when(() => result.data).thenReturn(<String, dynamic>{'customToken': token});
    when(() => callable.call<Map<String, dynamic>>(any()))
        .thenAnswer((_) async => result);
  }

  group('sin reloj emparejado', () {
    test('no llama a la Cloud Function: no se mintea credencial al pedo',
        () async {
      when(() => bridge.isSupported).thenAnswer((_) async => true);
      when(() => bridge.isPaired).thenAnswer((_) async => false);
      when(() => bridge.isReachable).thenAnswer((_) async => false);

      final outcome = await service.deliverCredential(uid: uid);

      expect(outcome, WatchCredentialOutcome.noWatchPaired);
      verifyNever(() => functions.httpsCallable(any()));
      verifyNever(() => bridge.updateApplicationContext(any()));
    });

    test('un nodo conectado alcanza aunque isPaired diga que no', () async {
      // El agujero de Android: `isPaired` lista apps companion instaladas en el
      // TELÉFONO, no relojes. Si ninguna está visible da false con el reloj
      // perfectamente conectado, y sin esto la entrega cortaba en
      // `noWatchPaired` — sin error, sin minteo, y la muñeca esperando una
      // credencial que nadie llegó a pedir.
      when(() => bridge.isSupported).thenAnswer((_) async => true);
      when(() => bridge.isPaired).thenAnswer((_) async => false);
      when(() => bridge.isReachable).thenAnswer((_) async => true);
      stubMintReturns('custom-token-abc');

      final outcome = await service.deliverCredential(uid: uid);

      expect(outcome, WatchCredentialOutcome.delivered);
      verify(() => bridge.updateApplicationContext(any())).called(1);
    });

    test('tampoco entrega nada si la plataforma no soporta relojes', () async {
      when(() => bridge.isSupported).thenAnswer((_) async => false);

      final outcome = await service.deliverCredential(uid: uid);

      expect(outcome, WatchCredentialOutcome.notSupported);
      verifyNever(() => functions.httpsCallable(any()));
    });
  });

  group('con reloj emparejado', () {
    setUp(() {
      when(() => bridge.isSupported).thenAnswer((_) async => true);
      when(() => bridge.isPaired).thenAnswer((_) async => true);
    });

    test('no pregunta por alcanzabilidad si ya sabe que hay reloj', () async {
      // El camino barato y el común. Preguntar de más no rompe nada, pero
      // `connectedNodes` es un viaje por MethodChannel y no hace falta.
      stubMintReturns('custom-token-abc');

      await service.deliverCredential(uid: uid);

      verifyNever(() => bridge.isReachable);
    });

    test('mintea y entrega el payload completo al reloj', () async {
      stubMintReturns('custom-token-abc');

      final outcome = await service.deliverCredential(uid: uid);

      expect(outcome, WatchCredentialOutcome.delivered);
      verify(() => functions.httpsCallable('mintWatchCredential')).called(1);

      final captured = verify(
        () => bridge.updateApplicationContext(captureAny()),
      ).captured.single as Map<String, dynamic>;

      final payload = WatchCredentialPayload.fromJson(captured);
      expect(payload.customToken, 'custom-token-abc');
      expect(payload.uid, uid);
      // El reloj habla HTTP directo contra Firebase, sin SDK: sin apiKey ni
      // projectId no puede canjear el token ni renovar despues.
      expect(payload.apiKey, apiKey);
      expect(payload.projectId, projectId);
    });

    test('no le manda datos al reloj a la Cloud Function', () async {
      stubMintReturns('custom-token-abc');

      await service.deliverCredential(uid: uid);

      final sent = verify(
        () => callable.call<Map<String, dynamic>>(captureAny()),
      ).captured.single;
      // La CF mintea SOLO para request.auth.uid y no acepta uid por
      // parametro. Mandarle uno seria sugerir que se puede elegir a quien
      // mintearle, que es exactamente el agujero que la CF evita.
      expect(sent, isNot(contains('uid')));
    });

    test('si la Cloud Function falla, no se entrega nada al reloj', () async {
      when(() => callable.call<Map<String, dynamic>>(any())).thenThrow(
        FirebaseFunctionsException(code: 'unauthenticated', message: 'nope'),
      );

      final outcome = await service.deliverCredential(uid: uid);

      expect(outcome, WatchCredentialOutcome.mintFailed);
      verifyNever(() => bridge.updateApplicationContext(any()));
    });

    test('si la CF devuelve un token vacio, no se entrega nada', () async {
      stubMintReturns('');

      final outcome = await service.deliverCredential(uid: uid);

      expect(outcome, WatchCredentialOutcome.mintFailed);
      verifyNever(() => bridge.updateApplicationContext(any()));
    });

    test('si el envio al reloj falla, lo reporta en vez de tragarselo',
        () async {
      stubMintReturns('custom-token-abc');
      when(() => bridge.updateApplicationContext(any()))
          .thenThrow(Exception('reloj desconectado'));

      final outcome = await service.deliverCredential(uid: uid);

      expect(outcome, WatchCredentialOutcome.deliveryFailed);
    });
  });

  group('WatchCredentialPayload', () {
    test('sobrevive el viaje de ida y vuelta por el bridge', () {
      const original = WatchCredentialPayload(
        customToken: 'tok',
        uid: 'u1',
        apiKey: 'k',
        projectId: 'p',
      );

      expect(WatchCredentialPayload.fromJson(original.toJson()), original);
    });

    test('el host de emulador viaja cuando esta, y se omite cuando no', () {
      const conEmulador = WatchCredentialPayload(
        customToken: 'tok',
        uid: 'u1',
        apiKey: 'k',
        projectId: 'p',
        authEmulatorHost: 'http://localhost:9099',
      );
      expect(
        WatchCredentialPayload.fromJson(conEmulador.toJson()).authEmulatorHost,
        'http://localhost:9099',
      );

      const sinEmulador = WatchCredentialPayload(
        customToken: 'tok',
        uid: 'u1',
        apiKey: 'k',
        projectId: 'p',
      );
      // Se OMITE la clave, no se manda null: el lado Swift trata ausente y
      // vacío igual, pero un JSON sin ruido es un contrato mas claro.
      expect(sinEmulador.toJson().containsKey('authEmulatorHost'), isFalse);
    });

    test('un payload sin customToken se rechaza', () {
      expect(
        () => WatchCredentialPayload.fromJson(const {'uid': 'u1'}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('clearCredential — cerrar sesión', () {
    // Esto NO existía. El listener de auth era `if (user == null) return;` sin
    // rama else, y `CredentialStore.delete()` del lado Swift tenía cero
    // llamadores. O sea que cerrar sesión en el teléfono no hacía absolutamente
    // nada en el reloj: seguía con un refresh token válido y podía leer y
    // escribir Firestore como el atleta anterior, indefinidamente y sin
    // teléfono de por medio.

    setUp(() {
      when(() => bridge.isSupported).thenAnswer((_) async => true);
      when(() => bridge.isPaired).thenAnswer((_) async => true);
    });

    test('PISA la credencial en el contexto, que es lo que la borra', () async {
      expect(await service.clearCredential(), isTrue);

      final ctx = verify(() => bridge.updateApplicationContext(captureAny()))
          .captured
          .single as Map<String, dynamic>;
      expect(ctx['kind'], 'watchSignedOut');
      // El contexto de salida es UNO SOLO y se pisa entero: que no quede ni un
      // campo de la credencial es lo que hace que el reloj no pueda releerla.
      expect(ctx.containsKey('customToken'), isFalse);
      expect(ctx.containsKey('refreshToken'), isFalse);
      expect(ctx.containsKey('uid'), isFalse);
      expect(ctx.keys, hasLength(1));
    });

    test('NO manda una credencial vacía', () async {
      // Un `WatchCredentialPayload` con el customToken en blanco no serviría:
      // el lado Swift valida con `nonEmpty`, el init falla entero y el contexto
      // se descarta en silencio. El teléfono creería que avisó.
      await service.clearCredential();

      final ctx = verify(() => bridge.updateApplicationContext(captureAny()))
          .captured
          .single as Map<String, dynamic>;
      expect(ctx['kind'], isNot(WatchCredentialPayload.kind));
    });

    test(
        'va por CONTEXTO y no por mensaje: tiene que llegar con la app cerrada',
        () async {
      await service.clearCredential();
      // `sendMessage` exige alcanzabilidad AHORA, y "el reloj está en un cajón"
      // es justo el caso que hay que cubrir: cerrar sesión tiene que
      // desloguearlo igual, aunque sea al próximo lanzamiento.
      verifyNever(() => bridge.sendMessage(any()));
    });

    test('sin reloj emparejado no hace nada', () async {
      when(() => bridge.isPaired).thenAnswer((_) async => false);
      expect(await service.clearCredential(), isFalse);
      verifyNever(() => bridge.updateApplicationContext(any()));
    });

    test('una falla del puente NO se propaga', () async {
      // Corre en el camino de logout: no puede tumbar el cierre de sesión.
      when(() => bridge.updateApplicationContext(any()))
          .thenThrow(Exception('canal muerto'));
      expect(await service.clearCredential(), isFalse);
    });
  });
}
