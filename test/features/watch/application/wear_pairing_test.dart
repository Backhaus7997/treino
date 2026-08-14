import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/watch/application/wear_pairing_providers.dart';
import 'package:treino/features/watch/data/wear_credential_exchanger.dart';
import 'package:treino/features/watch/domain/wear_credential.dart';
import 'package:treino/features/watch/presentation/wear/wear_view_models.dart';

class _MockExchanger extends Mock implements WearCredentialExchanger {}

void main() {
  late _MockExchanger exchanger;
  late StreamController<String?> uids;
  late StreamController<WearCredential> credenciales;

  setUp(() {
    exchanger = _MockExchanger();
    uids = StreamController<String?>.broadcast();
    credenciales = StreamController<WearCredential>.broadcast();

    when(() => exchanger.uidChanges).thenAnswer((_) => uids.stream);
    when(() => exchanger.exchange(any())).thenAnswer((_) async {});
  });

  tearDown(() {
    uids.close();
    credenciales.close();
  });

  /// Crea el contenedor y deja el notifier SUSCRITO.
  ///
  /// El `listen` vacío no es ceremonia: sin alguien escuchando, Riverpod no
  /// mantiene vivo el notifier y sus propios `ref.listen` nunca se enganchan.
  ProviderContainer contenedor() {
    final container = ProviderContainer(
      overrides: [
        wearCredentialExchangerProvider.overrideWithValue(exchanger),
        wearCredentialSourceProvider.overrideWith((ref) => credenciales.stream),
      ],
    );
    addTearDown(container.dispose);
    container.listen(wearPairingProvider, (_, __) {});
    return container;
  }

  group('estado inicial', () {
    test('sin sesión y sin credencial, espera al teléfono', () {
      when(() => exchanger.currentUid).thenReturn(null);

      expect(
        contenedor().read(wearPairingProvider),
        WearPairingState.waitingForPairing,
      );
    });

    test('con sesión de un arranque anterior arranca listo, sin canjear nada',
        () {
      // Firebase persiste la sesión entre arranques. Si acá se canjeara igual,
      // el reloj parpadearía "abrí la app en el teléfono" en cada arranque.
      when(() => exchanger.currentUid).thenReturn('atleta-1');

      expect(contenedor().read(wearPairingProvider), WearPairingState.ready);
      verifyNever(() => exchanger.exchange(any()));
    });
  });

  group('llega una credencial', () {
    test('la de otro atleta se canjea', () async {
      when(() => exchanger.currentUid).thenReturn(null);
      final container = contenedor();

      credenciales.add(
        const WearCredential(customToken: 'tok-nuevo', uid: 'atleta-2'),
      );
      await pumpEventQueue();

      verify(() => exchanger.exchange('tok-nuevo')).called(1);
      expect(container.read(wearPairingProvider), WearPairingState.exchanging);
    });

    test('la del atleta que YA tiene sesión no se canjea', () async {
      // Éste es el caso caro: el DataItem que transporta el token persiste para
      // siempre, pero el customToken dura una hora. Canjear el payload viejo en
      // cada arranque daría `failed` con una sesión perfectamente válida.
      when(() => exchanger.currentUid).thenReturn('atleta-1');
      final container = contenedor();

      credenciales.add(
        const WearCredential(customToken: 'tok-de-ayer', uid: 'atleta-1'),
      );
      await pumpEventQueue();

      verifyNever(() => exchanger.exchange(any()));
      expect(container.read(wearPairingProvider), WearPairingState.ready);
    });

    test('si el canje se rechaza, lo muestra en vez de tragárselo', () async {
      when(() => exchanger.currentUid).thenReturn(null);
      when(() => exchanger.exchange(any()))
          .thenThrow(Exception('token vencido'));
      final container = contenedor();

      credenciales.add(
        const WearCredential(customToken: 'tok-vencido', uid: 'atleta-2'),
      );
      await pumpEventQueue();

      expect(container.read(wearPairingProvider), WearPairingState.failed);
    });
  });

  group('un solo escritor para ready', () {
    test('el canje exitoso NO se declara listo solo: espera a Firebase',
        () async {
      // El invariante que vuelve idempotente el camino (HANDOFF §4.5). Si el
      // retorno del canje escribiera `ready`, habría dos escritores y el orden
      // de llegada pasaría a importar.
      when(() => exchanger.currentUid).thenReturn(null);
      final container = contenedor();

      credenciales.add(
        const WearCredential(customToken: 'tok', uid: 'atleta-2'),
      );
      await pumpEventQueue();

      // El canje ya volvió bien, pero Firebase todavía no confirmó.
      verify(() => exchanger.exchange('tok')).called(1);
      expect(container.read(wearPairingProvider), WearPairingState.exchanging);

      when(() => exchanger.currentUid).thenReturn('atleta-2');
      uids.add('atleta-2');
      await pumpEventQueue();

      expect(container.read(wearPairingProvider), WearPairingState.ready);
    });

    test('un uid que llega sin credencial de por medio también alcanza',
        () async {
      // Cubre el arranque en frío en el que Firebase restaura la sesión de
      // forma asíncrona, después de que el notifier ya se construyó.
      when(() => exchanger.currentUid).thenReturn(null);
      final container = contenedor();
      expect(
        container.read(wearPairingProvider),
        WearPairingState.waitingForPairing,
      );

      uids.add('atleta-1');
      await pumpEventQueue();

      expect(container.read(wearPairingProvider), WearPairingState.ready);
    });
  });

  group('se cierra la sesión', () {
    test('vuelve a esperar al teléfono', () async {
      when(() => exchanger.currentUid).thenReturn('atleta-1');
      final container = contenedor();
      expect(container.read(wearPairingProvider), WearPairingState.ready);

      when(() => exchanger.currentUid).thenReturn(null);
      uids.add(null);
      await pumpEventQueue();

      expect(
        container.read(wearPairingProvider),
        WearPairingState.waitingForPairing,
      );
    });

    test('un null que llega en medio de un canje NO lo pisa', () async {
      // `signInWithCustomToken` emite un null intermedio en algunas versiones
      // del SDK. Pisar `exchanging` con eso haría parpadear la pantalla de
      // espera justo cuando el canje va bien.
      when(() => exchanger.currentUid).thenReturn(null);
      final enVuelo = Completer<void>();
      when(() => exchanger.exchange(any())).thenAnswer((_) => enVuelo.future);
      final container = contenedor();

      credenciales.add(
        const WearCredential(customToken: 'tok', uid: 'atleta-2'),
      );
      await pumpEventQueue();
      expect(container.read(wearPairingProvider), WearPairingState.exchanging);

      uids.add(null);
      await pumpEventQueue();

      expect(container.read(wearPairingProvider), WearPairingState.exchanging);

      enVuelo.complete();
      await pumpEventQueue();
    });
  });
}
