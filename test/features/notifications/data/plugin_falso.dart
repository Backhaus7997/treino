// Un `FlutterLocalNotificationsPlugin` de mentira que ANOTA lo que le piden, para
// los tests del aviso de fin de descanso (#1617).
//
// Lo anotado es lo que cruzaría el canal hacia el sistema: qué se agendó, para
// cuándo, con qué id, canal y modo de alarma, y qué se canceló. Es lo único que
// el test puede mirar sin un aparato, así que el fake no decide nada: contesta
// lo que le configuran y deja el registro.

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:treino/features/notifications/data/local_notifications_service.dart';

class _MockPlugin extends Mock implements FlutterLocalNotificationsPlugin {}

class _MockAndroid extends Mock
    implements AndroidFlutterLocalNotificationsPlugin {}

/// Una llamada a `zonedSchedule`.
typedef Agendado = ({
  int id,
  tz.TZDateTime cuando,
  AndroidScheduleMode modo,
  NotificationDetails detalles,
  String? titulo,
  String? cuerpo,
});

class PluginFalso {
  PluginFalso({
    /// Lo que contesta `canScheduleExactNotifications`.
    this.alarmasExactas = true,

    /// `false` = no hay implementación de Android (iOS): `resolve…` da null.
    bool esAndroid = true,
  }) {
    registerFallbackValue(tz.TZDateTime.utc(2026));
    registerFallbackValue(const NotificationDetails());
    registerFallbackValue(AndroidScheduleMode.exact);
    registerFallbackValue(const InitializationSettings());
    registerFallbackValue(const AndroidNotificationChannel('id', 'nombre'));

    when(() => plugin.initialize(
          settings: any(named: 'settings'),
          onDidReceiveNotificationResponse:
              any(named: 'onDidReceiveNotificationResponse'),
          onDidReceiveBackgroundNotificationResponse:
              any(named: 'onDidReceiveBackgroundNotificationResponse'),
        )).thenAnswer((i) async {
      alTocar = i.namedArguments[#onDidReceiveNotificationResponse]
          as DidReceiveNotificationResponseCallback?;
      return true;
    });

    when(() => plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>())
        .thenReturn(esAndroid ? android : null);
    when(() => android.createNotificationChannel(any()))
        .thenAnswer((_) async {});
    when(() => android.canScheduleExactNotifications())
        .thenAnswer((_) async => alarmasExactas);

    when(() => plugin.zonedSchedule(
          id: any(named: 'id'),
          scheduledDate: any(named: 'scheduledDate'),
          notificationDetails: any(named: 'notificationDetails'),
          androidScheduleMode: any(named: 'androidScheduleMode'),
          title: any(named: 'title'),
          body: any(named: 'body'),
        )).thenAnswer((i) async {
      final a = i.namedArguments;
      final fallo = falloAlAgendar?.call(a[#androidScheduleMode]);
      if (fallo != null) throw fallo;
      eventos.add('agendar:${a[#id]}');
      agendados.add((
        id: a[#id] as int,
        cuando: a[#scheduledDate] as tz.TZDateTime,
        modo: a[#androidScheduleMode] as AndroidScheduleMode,
        detalles: a[#notificationDetails] as NotificationDetails,
        titulo: a[#title] as String?,
        cuerpo: a[#body] as String?,
      ));
    });

    when(() => plugin.cancel(id: any(named: 'id'))).thenAnswer((i) async {
      eventos.add('cancelar:${i.namedArguments[#id]}');
      cancelados.add(i.namedArguments[#id] as int);
    });

    when(() => plugin.show(
          id: any(named: 'id'),
          title: any(named: 'title'),
          body: any(named: 'body'),
          notificationDetails: any(named: 'notificationDetails'),
          payload: any(named: 'payload'),
        )).thenAnswer((i) async {
      mostrados.add(i.namedArguments[#id] as int);
    });
  }

  final plugin = _MockPlugin();
  final android = _MockAndroid();

  /// Se puede cambiar entre llamadas: lo que contesta la consulta de permiso.
  bool alarmasExactas;

  /// Si devuelve algo distinto de null, `zonedSchedule` lo tira. Recibe el modo
  /// pedido, para poder fallar sólo en el exacto.
  Object? Function(Object? modo)? falloAlAgendar;

  /// Todo lo que cruzó hacia el sistema, EN ORDEN (`agendar:1`, `cancelar:1`).
  /// Para probar que una cancelación no la adelanta un agendado en vuelo.
  final eventos = <String>[];
  final agendados = <Agendado>[];
  final cancelados = <int>[];
  final mostrados = <int>[];

  /// El callback que el servicio registró en `initialize` para los taps.
  DidReceiveNotificationResponseCallback? alTocar;

  /// Un servicio YA inicializado sobre este plugin.
  Future<LocalNotificationsService> servicio({
    void Function(String? deepLink)? onTap,
  }) async {
    final s = LocalNotificationsService(plugin: plugin);
    await s.init(onTap: onTap ?? (_) {});
    return s;
  }
}
