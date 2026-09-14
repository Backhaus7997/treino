import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
      onDidReceiveNotificationResponse: (response) =>
          _onTap?.call(response.payload),
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
      id: 0,
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
}
