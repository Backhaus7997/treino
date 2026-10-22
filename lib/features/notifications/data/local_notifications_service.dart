import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// Id del canal de Android por el que salen TODAS las notificaciones de TREINO.
///
/// **Tiene que ser el mismo string en tres lugares**, y si se desincronizan el
/// síntoma es silencioso y feo: el usuario termina con DOS entradas de
/// configuración para la misma app, y silenciar una no silencia la otra.
///
/// 1. Acá, que es el canal que se crea y por el que salen las locales (app en
///    primer plano).
/// 2. `android/app/src/main/AndroidManifest.xml`, en el meta-data
///    `com.google.firebase.messaging.default_notification_channel_id` — por ahí
///    salen las de BACKGROUND, que las dibuja el SDK de FCM sin pasar por Dart.
/// 3. `functions/src/notifications/send-fcm.ts`, si algún día el payload
///    empieza a mandar `android.notification.channelId` explícito. Hoy no lo
///    manda, y por eso el meta-data del punto 2 es el que decide.
///
/// Lo fija `test/features/notifications/data/canal_unico_test.dart`, que lee el
/// manifest y compara contra esta constante.
const kCanalDeAvisos = 'treino_avisos';

/// Nombre visible del canal en Ajustes → Apps → TREINO → Notificaciones.
///
/// Sin i18n a propósito: el canal se crea en `init()`, antes de que exista un
/// `BuildContext` del que sacar `AppL10n`, y Android congela el nombre en la
/// primera creación —cambiarlo después NO renombra el canal existente en los
/// dispositivos que ya lo tienen—. Un nombre estable en es-AR, que es el
/// locale primario de la app, es menos malo que uno que depende de cuándo se
/// creó.
const kNombreDelCanal = 'Avisos de TREINO';

/// Id de la notificación que dibuja [LocalNotificationsService.show].
///
/// Fijo a propósito: una nueva REEMPLAZA a la anterior en vez de apilar. Se
/// nombra para que los ids de las otras notificaciones locales no choquen con
/// él: reusar el 0 pisaría un aviso entrante que el usuario todavía no leyó.
const kIdAvisoEntrante = 0;

/// Id de la notificación AGENDADA que avisa que terminó el descanso (#1617).
///
/// Propio y distinto de [kIdAvisoEntrante]: agendar/cancelar el aviso del
/// descanso no puede tocar un mensaje entrante, y al revés. Es también la
/// clave para el tap: ver [LocalNotificationsService.agendar].
const kIdFinDeDescanso = 1;

/// Notificaciones cuyo tap sólo trae la app al frente, sin navegar a ningún
/// lado.
///
/// `goDeepLink` manda a `/coach` cuando el payload viene vacío, y una
/// notificación agendada no lleva payload. Para el aviso de fin de descanso eso
/// sería sacar al atleta del player en plena sesión justo cuando vuelve a la
/// serie.
const _idsQueSoloAbrenLaApp = {kIdFinDeDescanso};

/// Muestra notificaciones del SISTEMA operativo con la app en primer plano.
///
/// ## Por qué existe, si ya está FCM
///
/// FCM **no dibuja** la notificación cuando la app está en foreground. En
/// background la dibuja el SDK nativo; en foreground te entrega el mensaje y se
/// desentiende. Hasta ahora eso se resolvía con un SnackBar in-app
/// (ADR-PN-010), que es justo lo que el E2E marcó como insuficiente: el
/// teléfono no suena.
///
/// ## Por qué no alcanzaba la llamada de iOS
///
/// `setForegroundNotificationPresentationOptions` es un interruptor GLOBAL y
/// BINARIO: su propio dartdoc dice que con todo en `false` "a notification will
/// not be displayed in the foreground, however you will still receive events".
/// O muestra todas o ninguna. Como el requisito incluye NO avisar si ya estás
/// mirando esa pantalla, no hay forma de hacerlo con esa llamada — la
/// notificación la tiene que dibujar la app. De ahí esta clase, y de ahí que se
/// haya revertido la restricción "NO flutter_local_notifications" del §9 del
/// design original.
///
/// Por eso mismo **esa llamada no se hace en ningún lado**: dejarla en `true`
/// sumaría el banner del sistema ENCIMA de esta notificación local, y el
/// usuario vería cada mensaje dos veces.
class LocalNotificationsService {
  LocalNotificationsService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// Se dispara cuando el usuario toca una notificación LOCAL (las de primer
  /// plano). Las de background no pasan por acá: ésas las maneja
  /// `onMessageOpenedApp` del lado de FCM.
  void Function(String? deepLink)? _onTap;

  bool _inicializado = false;

  /// Si [init] terminó bien. Mientras sea false, [show] devuelve false y el
  /// llamador tiene que mostrar otra cosa — nunca quedarse callado.
  bool get listo => _inicializado;

  /// Crea el canal de Android y deja el plugin listo para mostrar.
  ///
  /// Idempotente: llamarlo dos veces no duplica el canal ni pisa el callback
  /// con uno muerto. Android ignora un `createNotificationChannel` con un id
  /// que ya existe.
  ///
  /// **No tira nunca.** Ver el `catch`.
  Future<void> init({required void Function(String? deepLink) onTap}) async {
    _onTap = onTap;
    if (_inicializado) return;
    try {
      await _init();
      _inicializado = true;
      debugPrint('[local-notif] init OK — canal $kCanalDeAvisos');
    } catch (e, st) {
      // NO se relanza. El llamador la invoca sin await —no puede bloquear el
      // arranque de la app por el canal de avisos— y una excepción en un
      // future sin dueño no la ve nadie. Se deja `_inicializado` en false, que
      // es lo que hace que `show` devuelva false y el handler caiga al
      // SnackBar. Un aviso feo es infinitamente mejor que ninguno.
      debugPrint('[local-notif] init FALLÓ — $e\n$st');
    }
  }

  Future<void> _init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');

    // Los tres `false`: el permiso NO se pide acá. Lo pide `PermissionGate` por
    // FCM, y pedirlo dos veces por dos caminos distintos le muestra al usuario
    // dos diálogos para lo mismo — o peor, quema el único intento que iOS da.
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: darwin),
      onDidReceiveNotificationResponse: (response) {
        if (_soloAbreLaApp(response.id)) return;
        _onTap?.call(response.payload);
      },
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            kCanalDeAvisos,
            kNombreDelCanal,
            importance: Importance.high,
          ),
        );
  }

  /// El deep link de la notificación LOCAL que ABRIÓ la app, o null.
  ///
  /// Es el equivalente local de `FirebaseMessaging.getInitialMessage()`, y
  /// tapa el mismo agujero que aquél tapa del lado de FCM.
  ///
  /// El callback de [init] —`onDidReceiveNotificationResponse`— sólo se dispara
  /// con la app VIVA. Si el usuario toca un aviso local con la app cerrada, el
  /// sistema la ARRANCA y ese callback no corre nunca: el tap se pierde y el
  /// usuario aterriza en la pantalla de inicio en vez de donde el aviso
  /// prometía. Y no es un caso raro — es el más común, porque una notificación
  /// se toca justamente cuando no estabas usando la app.
  ///
  /// Se volvió más caro desde el #1150: los deep links ahora llevan a UNA
  /// sesión concreta y no a la ficha genérica del alumno, así que perderlo ya
  /// no es aterrizar cerca, es aterrizar en otro lado.
  ///
  /// **Se consume después de que el router esté montado**, igual que su gemelo
  /// de FCM: navegar antes del primer frame no tiene a dónde.
  ///
  /// Nunca tira: un fallo del canal nativo devuelve null y el arranque sigue
  /// normal, que es exactamente lo que pasaba antes de que este método
  /// existiera.
  Future<String?> deepLinkDeArranque() async {
    try {
      final detalles = await _plugin.getNotificationAppLaunchDetails();
      if (detalles == null || !detalles.didNotificationLaunchApp) return null;
      // Un arranque en frío por el aviso de fin de descanso es un arranque
      // normal: no hay destino al que llevar al usuario.
      if (_soloAbreLaApp(detalles.notificationResponse?.id)) return null;
      final payload = detalles.notificationResponse?.payload;
      debugPrint('[local-notif] arrancó por notificación — deepLink=$payload');
      return payload;
    } catch (e) {
      debugPrint('[local-notif] getNotificationAppLaunchDetails FALLÓ — $e');
      return null;
    }
  }

  /// Dibuja la notificación. [deepLink] viaja como payload y vuelve en el tap.
  ///
  /// Devuelve `true` si se dibujó, `false` si NO se pudo.
  ///
  /// El bool no es cosmético: es el contrato con el llamador. Un `false` le
  /// dice "mostrá vos otra cosa", y sin él una falla del plugin se comía el
  /// aviso en silencio — el usuario nunca se enteraba de que le habían
  /// escrito, y en el log tampoco había nada porque `init` corre sin await.
  Future<bool> show({
    required String title,
    required String body,
    String? deepLink,
  }) async {
    if (!_inicializado) {
      debugPrint('[local-notif] show() con init fallido o pendiente — '
          'el llamador tiene que mostrar otra cosa');
      return false;
    }
    try {
      await _mostrar(title: title, body: body, deepLink: deepLink);
      debugPrint('[local-notif] mostrada — "$title"');
      return true;
    } catch (e) {
      debugPrint('[local-notif] show() FALLÓ — $e');
      return false;
    }
  }

  /// El id es fijo a propósito: una notificación nueva REEMPLAZA a la anterior
  /// en vez de apilar. Con id incremental, diez mensajes seguidos de un alumno
  /// dejan diez entradas en la bandeja y el usuario las borra todas de un
  /// manotazo, que es la forma más rápida de que deje de mirarlas.
  Future<void> _mostrar({
    required String title,
    required String body,
    String? deepLink,
  }) async {
    await _plugin.show(
      id: kIdAvisoEntrante,
      title: title.isEmpty ? null : title,
      body: body.isEmpty ? null : body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          kCanalDeAvisos,
          kNombreDelCanal,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: deepLink,
    );
  }

  /// Agenda UNA notificación para el instante [cuando] (#1617). La dispara el
  /// sistema operativo, no Dart: sale con la app en segundo plano o la pantalla
  /// bloqueada, que es justo cuando `show` no sirve.
  ///
  /// Devuelve `true` si quedó agendada y `false` si NO se pudo (servicio sin
  /// inicializar, [cuando] ya pasó o falla del plugin). Igual que [show], no
  /// tira nunca: el llamador decide qué hacer con el `false`.
  ///
  /// Con el mismo [id] reemplaza a la anterior, así que reagendar (el «+15 s»)
  /// no deja dos avisos.
  ///
  /// ## Instante, no hora local
  ///
  /// Se agenda con `TZDateTime.from(cuando, tz.UTC)`: es el MISMO instante, sólo
  /// escrito en UTC. Así no depende del nombre de la zona del aparato (ni de
  /// que la base de zonas esté inicializada). El plugin manda la fecha a la
  /// plataforma con precisión de segundo y la trunca: el aviso puede salir hasta
  /// 999 ms antes de [cuando].
  ///
  /// ## Android: exacta si se puede, inexacta si no
  ///
  /// Con `SCHEDULE_EXACT_ALARM` concedido (`canScheduleExactNotifications`) va
  /// `exactAllowWhileIdle`. Si no, `inexactAllowWhileIdle`: NO se le pide el
  /// permiso al usuario y NO se declara `USE_EXACT_ALARM` (el README del plugin
  /// avisa que las tiendas pueden auditarlo). El costo es real: sin el permiso
  /// el sistema puede demorar la alarma, y desde Android 14 viene denegado por
  /// defecto.
  ///
  /// Pedir una alarma exacta sin el permiso hace que el plugin tire
  /// `exact_alarms_not_permitted`. Pasa sólo si el permiso se revoca entre la
  /// consulta y el agendado, y en ese caso se cae a la inexacta en vez de
  /// quedarse sin aviso.
  ///
  /// ## El tap
  ///
  /// No lleva payload y [kIdFinDeDescanso] está en [_idsQueSoloAbrenLaApp]: tocar
  /// el aviso trae la app al frente y nada más.
  Future<bool> agendar({
    required int id,
    required DateTime cuando,
    required String title,
    required String body,
  }) async {
    if (!_inicializado) {
      debugPrint('[local-notif] agendar() con init fallido o pendiente — '
          'no se agenda');
      return false;
    }
    if (!cuando.isAfter(clock.now())) {
      debugPrint('[local-notif] agendar() para un instante que ya pasó');
      return false;
    }
    try {
      final exacta = await _puedeAgendarExacta();
      try {
        await _agendar(
          id: id,
          cuando: cuando,
          title: title,
          body: body,
          modo: exacta
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
        );
      } on PlatformException catch (e) {
        if (!exacta || e.code != 'exact_alarms_not_permitted') rethrow;
        await _agendar(
          id: id,
          cuando: cuando,
          title: title,
          body: body,
          modo: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
      debugPrint('[local-notif] agendada id=$id para $cuando');
      return true;
    } catch (e) {
      debugPrint('[local-notif] agendar() FALLÓ — $e');
      return false;
    }
  }

  /// Saca la notificación [id]: la agendada que todavía no salió y también la
  /// que ya se mostró y sigue en la bandeja. Nunca tira.
  Future<void> cancelar(int id) async {
    if (!_inicializado) return;
    try {
      await _plugin.cancel(id: id);
    } catch (e) {
      debugPrint('[local-notif] cancelar($id) FALLÓ — $e');
    }
  }

  /// `canScheduleExactNotifications` sólo existe en Android: en iOS no hay
  /// implementación que resolver y el modo se ignora. Ante un fallo de la
  /// consulta se asume que NO se puede: la inexacta siempre es válida.
  Future<bool> _puedeAgendarExacta() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.canScheduleExactNotifications() ?? false;
    } catch (e) {
      debugPrint('[local-notif] canScheduleExactNotifications FALLÓ — $e');
      return false;
    }
  }

  Future<void> _agendar({
    required int id,
    required DateTime cuando,
    required String title,
    required String body,
    required AndroidScheduleMode modo,
  }) {
    return _plugin.zonedSchedule(
      id: id,
      title: title.isEmpty ? null : title,
      body: body.isEmpty ? null : body,
      scheduledDate: tz.TZDateTime.from(cuando, tz.UTC),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          kCanalDeAvisos,
          kNombreDelCanal,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: modo,
    );
  }

  static bool _soloAbreLaApp(int? id) =>
      id != null && _idsQueSoloAbrenLaApp.contains(id);
}
