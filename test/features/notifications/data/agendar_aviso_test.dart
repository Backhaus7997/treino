// El aviso de fin de descanso con la app en segundo plano (#1617), del lado del
// servicio: cómo se agenda una notificación en el sistema.
//
// Lo que se mira es lo que cruzaría el canal: id, canal, instante, modo de
// alarma. Que el aviso suene de verdad en un aparato no se puede probar acá.

import 'package:clock/clock.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:treino/features/notifications/data/local_notifications_service.dart';

import 'plugin_falso.dart';

NotificationResponse _toque({int? id, String? payload}) => NotificationResponse(
      notificationResponseType: NotificationResponseType.selectedNotification,
      id: id,
      payload: payload,
    );

void main() {
  final fin = clock.now().add(const Duration(seconds: 90));

  group('agendar', () {
    test('agenda con el id propio y por el canal único', () async {
      final falso = PluginFalso();
      final servicio = await falso.servicio();

      final ok = await servicio.agendar(
        id: kIdFinDeDescanso,
        cuando: fin,
        title: 'Terminó el descanso',
        body: 'Volvé a la serie',
      );

      expect(ok, isTrue);
      expect(falso.agendados, hasLength(1));
      final a = falso.agendados.single;
      expect(a.id, kIdFinDeDescanso);
      expect(a.titulo, 'Terminó el descanso');
      expect(a.cuerpo, 'Volvé a la serie');
      expect(a.detalles.android!.channelId, kCanalDeAvisos);
    });

    test('el id del descanso NO es el del aviso entrante', () async {
      // Si fueran el mismo, agendar o cancelar el descanso pisaría un mensaje
      // entrante que el usuario todavía no leyó, y al revés.
      expect(kIdFinDeDescanso, isNot(kIdAvisoEntrante));

      final falso = PluginFalso();
      final servicio = await falso.servicio();
      await servicio.show(title: 't', body: 'b');
      expect(falso.mostrados, [kIdAvisoEntrante],
          reason: '`show` sigue saliendo por el id de los avisos entrantes');
    });

    test('agenda el MISMO instante, escrito en UTC', () async {
      final falso = PluginFalso();
      final servicio = await falso.servicio();

      await servicio.agendar(
        id: kIdFinDeDescanso,
        cuando: fin,
        title: 't',
        body: 'b',
      );

      final cuando = falso.agendados.single.cuando;
      expect(cuando.location, tz.UTC,
          reason: 'sin depender de la zona del aparato');
      expect(cuando.isAtSameMomentAs(fin), isTrue);
    });

    test('con alarmas exactas permitidas va en modo exacto', () async {
      final falso = PluginFalso(alarmasExactas: true);
      final servicio = await falso.servicio();

      await servicio.agendar(
          id: kIdFinDeDescanso, cuando: fin, title: 't', body: 'b');

      expect(
          falso.agendados.single.modo, AndroidScheduleMode.exactAllowWhileIdle);
    });

    // El control negativo del de arriba: un servicio que pidiera SIEMPRE exacto
    // pasaría aquel test igual y en Android 14 tiraría
    // `exact_alarms_not_permitted` en cada descanso, o sea, sin aviso.
    test('sin permiso de alarmas exactas va en modo inexacto', () async {
      final falso = PluginFalso(alarmasExactas: false);
      final servicio = await falso.servicio();

      await servicio.agendar(
          id: kIdFinDeDescanso, cuando: fin, title: 't', body: 'b');

      expect(falso.agendados.single.modo,
          AndroidScheduleMode.inexactAllowWhileIdle);
    });

    test('en iOS (sin implementación de Android) agenda igual', () async {
      final falso = PluginFalso(esAndroid: false);
      final servicio = await falso.servicio();

      final ok = await servicio.agendar(
          id: kIdFinDeDescanso, cuando: fin, title: 't', body: 'b');

      expect(ok, isTrue);
      expect(falso.agendados, hasLength(1));
    });

    test(
        'si el permiso se revoca entre la consulta y el agendado, cae a la '
        'inexacta en vez de quedarse sin aviso', () async {
      final falso = PluginFalso(alarmasExactas: true)
        ..falloAlAgendar = (modo) =>
            modo == AndroidScheduleMode.exactAllowWhileIdle
                ? PlatformException(code: 'exact_alarms_not_permitted')
                : null;
      final servicio = await falso.servicio();

      final ok = await servicio.agendar(
          id: kIdFinDeDescanso, cuando: fin, title: 't', body: 'b');

      expect(ok, isTrue);
      expect(falso.agendados, hasLength(1));
      expect(falso.agendados.single.modo,
          AndroidScheduleMode.inexactAllowWhileIdle);
    });

    // Control negativo: el reintento es SÓLO para ese código. Reintentar ante
    // cualquier error enmascararía un fallo real del plugin.
    test('ante otro error no reintenta', () async {
      final falso = PluginFalso(alarmasExactas: true)
        ..falloAlAgendar = (modo) =>
            modo == AndroidScheduleMode.exactAllowWhileIdle
                ? PlatformException(code: 'otro')
                : null;
      final servicio = await falso.servicio();

      final ok = await servicio.agendar(
          id: kIdFinDeDescanso, cuando: fin, title: 't', body: 'b');

      expect(ok, isFalse);
      expect(falso.agendados, isEmpty);
    });

    test('un fallo del plugin devuelve false y no propaga', () async {
      final falso = PluginFalso()..falloAlAgendar = (_) => Exception('canal');
      final servicio = await falso.servicio();

      expect(
        await servicio.agendar(
            id: kIdFinDeDescanso, cuando: fin, title: 't', body: 'b'),
        isFalse,
      );
    });

    test('sin init no agenda (y no toca el plugin)', () async {
      final falso = PluginFalso();
      final servicio = LocalNotificationsService(plugin: falso.plugin);

      expect(
        await servicio.agendar(
            id: kIdFinDeDescanso, cuando: fin, title: 't', body: 'b'),
        isFalse,
      );
      expect(falso.agendados, isEmpty);
    });

    test('un instante que ya pasó no se agenda', () async {
      // El plugin tira ArgumentError ante una fecha pasada; mejor no llegar.
      final falso = PluginFalso();
      final servicio = await falso.servicio();

      expect(
        await servicio.agendar(
          id: kIdFinDeDescanso,
          cuando: clock.now().subtract(const Duration(seconds: 1)),
          title: 't',
          body: 'b',
        ),
        isFalse,
      );
      expect(falso.agendados, isEmpty);
    });
  });

  // La cuenta regresiva en vivo (#1617): el número exacto cuando el aviso final
  // puede llegar tarde. La dibuja el sistema con un cronómetro; la app sólo la
  // publica con los flags correctos.
  group('mostrarCuentaRegresiva', () {
    final ahora = DateTime(2026, 10, 22, 10, 40);
    final hasta = ahora.add(const Duration(seconds: 90));

    Future<T> enReloj<T>(Future<T> Function() cuerpo) =>
        withClock(Clock.fixed(ahora), cuerpo);

    test('publica YA, con el cronómetro bajando hasta el fin', () async {
      await enReloj(() async {
        final falso = PluginFalso();
        final servicio = await falso.servicio();

        final ok = await servicio.mostrarCuentaRegresiva(
          id: kIdCuentaDeDescanso,
          hasta: hasta,
          title: 'Descanso',
          body: 'Volvé a la serie cuando llegue a cero',
        );

        expect(ok, isTrue);
        expect(falso.publicadas, hasLength(1));
        final p = falso.publicadas.single;
        expect(p.id, kIdCuentaDeDescanso);
        expect(p.titulo, 'Descanso');
        expect(p.cuerpo, 'Volvé a la serie cuando llegue a cero');
        final a = p.detalles.android!;
        expect(a.channelId, kCanalDeAvisos);
        expect(a.usesChronometer, isTrue);
        expect(a.chronometerCountDown, isTrue);
        expect(a.showWhen, isTrue);
        expect(a.when, hasta.millisecondsSinceEpoch);
        expect(a.ongoing, isTrue);
        expect(a.onlyAlertOnce, isTrue);
        expect(a.silent, isTrue);
        expect(a.playSound, isFalse);
        expect(a.enableVibration, isFalse);
        expect(a.timeoutAfter, 90000,
            reason: 'el sistema la saca exactamente al llegar a cero');
      });
    });

    test('el id de la cuenta no pisa al aviso final ni al entrante', () {
      expect({kIdCuentaDeDescanso, kIdFinDeDescanso, kIdAvisoEntrante},
          hasLength(3));
    });

    test('republicar con el mismo id: el `when` y el timeout nuevos', () async {
      await enReloj(() async {
        final falso = PluginFalso();
        final servicio = await falso.servicio();
        await servicio.mostrarCuentaRegresiva(
            id: kIdCuentaDeDescanso, hasta: hasta, title: 't', body: 'b');

        final masQuince = hasta.add(const Duration(seconds: 15));
        await servicio.mostrarCuentaRegresiva(
            id: kIdCuentaDeDescanso, hasta: masQuince, title: 't', body: 'b');

        expect(falso.publicadas.map((p) => p.id), [
          kIdCuentaDeDescanso,
          kIdCuentaDeDescanso,
        ]);
        final nueva = falso.publicadas.last.detalles.android!;
        expect(nueva.when, masQuince.millisecondsSinceEpoch);
        expect(nueva.timeoutAfter, 105000);
      });
    });

    // Con el fin ya pasado un cronómetro bajando se vería en negativo.
    test('no publica si el fin ya pasó (ni si es justo ahora)', () async {
      await enReloj(() async {
        final falso = PluginFalso();
        final servicio = await falso.servicio();

        for (final h in [ahora, ahora.subtract(const Duration(seconds: 5))]) {
          expect(
            await servicio.mostrarCuentaRegresiva(
                id: kIdCuentaDeDescanso, hasta: h, title: 't', body: 'b'),
            isFalse,
          );
        }
        expect(falso.publicadas, isEmpty);
      });
    });

    // En iOS no hay cronómetro en las notificaciones, y un `show` ahí dibujaría
    // un banner con sonido ya mismo. El aviso agendado es puntual por su cuenta.
    test('en iOS no publica nada', () async {
      await enReloj(() async {
        final falso = PluginFalso(esAndroid: false);
        final servicio = await falso.servicio();

        expect(
          await servicio.mostrarCuentaRegresiva(
              id: kIdCuentaDeDescanso, hasta: hasta, title: 't', body: 'b'),
          isFalse,
        );
        expect(falso.publicadas, isEmpty);
      });
    });

    test('sin init no publica, y un fallo del plugin no propaga', () async {
      await enReloj(() async {
        final falso = PluginFalso();
        expect(
          await LocalNotificationsService(plugin: falso.plugin)
              .mostrarCuentaRegresiva(
                  id: kIdCuentaDeDescanso, hasta: hasta, title: 't', body: 'b'),
          isFalse,
        );
        expect(falso.publicadas, isEmpty);

        falso.falloAlMostrar = Exception('canal');
        final servicio = await falso.servicio();
        expect(
          await servicio.mostrarCuentaRegresiva(
              id: kIdCuentaDeDescanso, hasta: hasta, title: 't', body: 'b'),
          isFalse,
        );
      });
    });
  });

  group('cancelar', () {
    test('cancela por id, la agendada y la que ya se mostró', () async {
      final falso = PluginFalso();
      final servicio = await falso.servicio();

      await servicio.cancelar(kIdFinDeDescanso);

      expect(falso.cancelados, [kIdFinDeDescanso]);
    });

    test('sin init no hace nada, y un fallo del plugin no propaga', () async {
      final falso = PluginFalso();
      await LocalNotificationsService(plugin: falso.plugin)
          .cancelar(kIdFinDeDescanso);
      expect(falso.cancelados, isEmpty);

      when(() => falso.plugin.cancel(id: any(named: 'id')))
          .thenThrow(Exception('canal'));
      final servicio = await falso.servicio();
      await servicio.cancelar(kIdFinDeDescanso); // no tira
    });
  });

  // `goDeepLink` manda a `/coach` cuando el payload viene vacío, y una
  // notificación agendada no lleva payload. Sin esto, tocar «Terminó el
  // descanso» sacaba al atleta del player en plena sesión.
  group('el tap del aviso de fin de descanso', () {
    test('NO navega: sólo trae la app al frente', () async {
      final falso = PluginFalso();
      final taps = <String?>[];
      await falso.servicio(onTap: taps.add);

      falso.alTocar!(_toque(id: kIdFinDeDescanso, payload: ''));

      expect(taps, isEmpty);
    });

    // Control negativo: un filtro que descartara TODOS los taps pasaría el test
    // de arriba y dejaría mudas las notificaciones de chat.
    test('lo mismo con la cuenta regresiva', () async {
      final falso = PluginFalso();
      final taps = <String?>[];
      final servicio = await falso.servicio(onTap: taps.add);

      falso.alTocar!(_toque(id: kIdCuentaDeDescanso, payload: ''));
      expect(taps, isEmpty);

      when(() => falso.plugin.getNotificationAppLaunchDetails()).thenAnswer(
        (_) async => NotificationAppLaunchDetails(
          true,
          notificationResponse: _toque(id: kIdCuentaDeDescanso, payload: ''),
        ),
      );
      expect(await servicio.deepLinkDeArranque(), isNull);
    });

    test('el tap de otra notificación sigue navegando', () async {
      final falso = PluginFalso();
      final taps = <String?>[];
      await falso.servicio(onTap: taps.add);

      falso.alTocar!(_toque(id: kIdAvisoEntrante, payload: '/chat/c1'));

      expect(taps, ['/chat/c1']);
    });

    test('un arranque en frío por ese aviso es un arranque normal', () async {
      final falso = PluginFalso();
      final servicio = await falso.servicio();
      when(() => falso.plugin.getNotificationAppLaunchDetails()).thenAnswer(
        (_) async => NotificationAppLaunchDetails(
          true,
          notificationResponse: _toque(id: kIdFinDeDescanso, payload: ''),
        ),
      );

      expect(await servicio.deepLinkDeArranque(), isNull);
    });

    test('un arranque en frío por otra notificación conserva su destino',
        () async {
      final falso = PluginFalso();
      final servicio = await falso.servicio();
      when(() => falso.plugin.getNotificationAppLaunchDetails()).thenAnswer(
        (_) async => NotificationAppLaunchDetails(
          true,
          notificationResponse:
              _toque(id: kIdAvisoEntrante, payload: '/chat/c1'),
        ),
      );

      expect(await servicio.deepLinkDeArranque(), '/chat/c1');
    });
  });
}
