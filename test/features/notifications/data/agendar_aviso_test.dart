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
