import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // firebase_messaging relies on UIApplicationDelegate swizzling to receive
    // didRegisterForRemoteNotificationsWithDeviceToken, but the implicit
    // engine pattern registers plugins after didFinishLaunching, so the
    // swizzle misses the initial registration. Call register explicitly here
    // so iOS starts the APNS provisioning flow; firebase_messaging's
    // delegate will then receive the token once iOS calls back.
    application.registerForRemoteNotifications()
    // Se guardan para reemitir la notificación de arranque una vez que los
    // plugins estén registrados — ver `didInitializeImplicitFlutterEngine`.
    launchOptionsGuardadas = launchOptions
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Held strongly: the method channel's handler dies with it, and a released
  /// launcher would make the watch silently stop opening.
  private var watchLauncher: WatchLauncher?

  /// Held strongly, y esto NO es opcional: `firebase_messaging` se guarda el
  /// delegate original en una referencia **`__weak`**
  /// (`FLTFirebaseMessagingPlugin.m:45`). Si lo soltamos se libera, FCM deja de
  /// reenviarle, y vuelve a decidir la presentación él mismo con sus opciones
  /// globales — o sea, dos banners otra vez, y en silencio.
  private let presentacionEnPrimerPlano = PresentacionEnPrimerPlano()

  /// `launchOptions` de `didFinishLaunching`, guardado para poder reemitir la
  /// notificación de arranque cuando los plugins ya estén registrados.
  ///
  /// Se guarda el diccionario y no sólo un flag porque `firebase_messaging` lee
  /// de ahí `UIApplicationLaunchOptionsRemoteNotificationKey` — es como sabe
  /// que la app la abrió una notificación (`getInitialMessage`). Reemitir sin
  /// el userInfo original rompería el arranque en frío desde una notificación.
  private var launchOptionsGuardadas: [UIApplication.LaunchOptionsKey: Any]?

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Tomar el delegate de `UNUserNotificationCenter` ANTES de la reemisión de
    // abajo, que es donde `firebase_messaging` decide si se lo queda.
    //
    // ## Por qué hace falta un delegate propio
    //
    // Con la app en primer plano quien decide qué se dibuja es el delegate del
    // centro de notificaciones, y hasta acá ese puesto quedaba **vacante**:
    //
    // - `flutter_local_notifications` NUNCA se asigna como delegate en iOS;
    //   sólo hace `addApplicationDelegate` (`FlutterLocalNotificationsPlugin.m`
    //   :145-159). Por eso su `willPresentNotification` —que presenta las suyas
    //   y se retira con las ajenas— es hoy código muerto.
    // - `FlutterAppDelegate` tampoco se asigna: implementa los métodos y los
    //   reenvía a todos los plugins, pero nadie cablea la entrada de esa cadena.
    //
    // Con el puesto vacante, FCM se lo queda entero (`shouldReplaceDelegate =
    // YES` con `_original = nil`) y termina decidiendo la presentación de TODA
    // notificación con un único interruptor global — incluida la local que
    // dibuja la app. De ahí salían los dos banners: el remoto y el local, sin
    // forma de pedir uno solo.
    //
    // Ocupándolo nosotros, FCM nos captura como `_originalNotificationCenter
    // Delegate` y nos **cede la decisión por notificación**
    // (`FLTFirebaseMessagingPlugin.m:336-344`). Ahí ya podemos callar la remota
    // y dejar pasar la local.
    //
    // `PresentacionEnPrimerPlano` es deliberadamente un `NSObject` pelado: si
    // conformara `FlutterAppLifeCycleProvider`, FCM lo detectaría y NO se
    // quedaría con el delegate (`FLTFirebaseMessagingPlugin.m:271-274`),
    // dejándonos como delegate único y sin nadie que dispare `onMessage`.
    //
    // No sirve reordenar `GeneratedPluginRegistrant`: como
    // `flutter_local_notifications` nunca compite por el puesto, el orden de
    // registro no cambia nada.
    UNUserNotificationCenter.current().delegate = presentacionEnPrimerPlano

    // Reemitir `UIApplicationDidFinishLaunchingNotification` DESPUÉS de
    // registrar los plugins.
    //
    // ## Por qué, y qué rompía
    //
    // `FLTFirebaseMessagingPlugin` hace TODO su armado dentro de
    // `application_onDidFinishLaunchingNotification:` — ahí adentro están
    // `notificationCenter.delegate`, `addApplicationDelegate` y
    // `registerForRemoteNotifications`. Y se suscribe a esa notificación en su
    // `init`, o sea al registrarse.
    //
    // Con el patrón de engine implícito los plugins se registran DESPUÉS de
    // `didFinishLaunching`, así que ese observer llega tarde, la notificación
    // ya pasó, y el método **nunca corre**. Consecuencia medida en un iPhone 16
    // el 2026-09-14: el delegate de `UNUserNotificationCenter` nunca se
    // instala, `willPresentNotification` nunca llega al plugin, y
    // `FirebaseMessaging.onMessage` **no dispara jamás** con la app en primer
    // plano. En background funciona porque ahí la dibuja el SDK nativo sin
    // pasar por Dart.
    //
    // El `registerForRemoteNotifications()` explícito de arriba ya era un
    // parche para OTRO síntoma del mismo método muerto. Esto lo cubre entero.
    //
    // Reemitir es seguro: con este patrón NINGÚN plugin alcanzó a recibir la
    // original, así que nadie la procesa dos veces.
    NotificationCenter.default.post(
      name: UIApplication.didFinishLaunchingNotification,
      object: nil,
      userInfo: launchOptionsGuardadas.map { opciones in
        Dictionary(uniqueKeysWithValues: opciones.map { ($0.key.rawValue, $0.value) })
      }
    )

    // Comprobar acá mismo que el mecanismo quedó armado, en vez de enterarnos
    // recién cuando llegue un push.
    //
    // Si FCM se instaló bien, el centro YA NO apunta a nuestro shim: apunta a
    // FCM, y nosotros quedamos colgados de su `_originalNotificationCenter
    // Delegate`, que es exactamente donde queremos estar. Que el centro siga
    // apuntándonos significa que el plugin no corrió —reemisión rota, plugin
    // cambiado— y que la remota va a mostrarse igual.
    let loTomoFcm = UNUserNotificationCenter.current().delegate !== presentacionEnPrimerPlano
    NSLog(
      loTomoFcm
        ? "[fcm] delegate armado: FCM se quedó con el centro y nos cede la decisión"
        : "[fcm] delegate NO armado: FCM no se instaló, la remota se va a mostrar igual"
    )

    // The messenger comes from the plugin registry, NOT from
    // `window.rootViewController as? FlutterViewController`. Under the implicit
    // engine pattern that cast is unreliable at this point, and the snippet
    // found in most Flutter docs silently no-ops here.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "WatchLauncher") {
      watchLauncher = WatchLauncher.register(with: registrar.messenger())
    }
  }
}

/// Decide, **por notificación**, qué se dibuja con la app en primer plano.
///
/// Existe porque el interruptor de `firebase_messaging`
/// (`setForegroundNotificationPresentationOptions`) es uno solo, global y
/// binario: prendido muestra la remota Y la local —dos banners por mensaje—, y
/// apagado no muestra ninguna de las dos. Acá separamos los dos casos:
///
/// - **La remota de FCM se calla.** No se pierde nada: su llegada ya disparó
///   `Messaging#onMessage` en Dart, que aplica `isOwnChatMessage` y la
///   supresión por pantalla, y publica la local si corresponde.
/// - **La local pasa**, con las opciones que eligió Dart.
///
/// Deliberadamente NO conforma `FlutterAppLifeCycleProvider` ni implementa
/// `didReceiveNotificationResponse`: lo primero porque haría que FCM no se
/// quedara con el delegate (ver `AppDelegate`), y lo segundo para que el tap
/// siga resolviéndose exactamente como hoy — si lo implementáramos, FCM nos
/// reenviaría también los taps y habría que reimplementar su ruteo entero.
final class PresentacionEnPrimerPlano: NSObject, UNUserNotificationCenterDelegate {
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let userInfo = notification.request.content.userInfo
    let esRemotaDeFcm = userInfo["gcm.message_id"] != nil

    // Red de seguridad contra el peor final posible: quedarnos MUDOS sin
    // enterarnos.
    //
    // Callar la remota sólo es correcto si FCM se quedó con el delegate —o sea,
    // si estamos acá por su reenvío y `onMessage` corrió en Dart para poder
    // redibujarla—. Si seguimos siendo nosotros el delegate del centro, FCM
    // nunca se instaló (cambió el plugin, se rompió la reemisión de arriba) y
    // nadie la va a redibujar. En ese caso preferimos que se vea de más, aunque
    // vuelvan los dos banners: un banner sobrante se nota, el silencio no.
    let fcmSeQuedoConElDelegate = center.delegate !== self

    if esRemotaDeFcm && fcmSeQuedoConElDelegate {
      NSLog("[fcm] remota callada: la redibuja Dart si corresponde")
      completionHandler([])
      return
    }

    if esRemotaDeFcm {
      NSLog("[fcm] remota MOSTRADA: FCM no se quedó con el delegate — revisar la reemisión")
    }

    let opciones = opcionesDe(userInfo)

    // Loguear también esta rama, y no sólo la remota, es lo que vuelve
    // AUTOSUFICIENTE al log nativo: una `remota callada` seguida de una `local
    // presentada` es el caso que se ve; una `remota callada` SIN local atrás es
    // el caso suprimido. Sin esta línea, "no apareció nada" y "el push nunca
    // llegó" se leen igual — que es justo el par que hay que poder separar.
    // (Los `debugPrint` de Dart no salen por el console de `devicectl`.)
    NSLog(
      "[fcm] local presentada (banner=\(opciones.contains(.banner)) "
        + "sonido=\(opciones.contains(.sound)) badge=\(opciones.contains(.badge)))"
    )

    completionHandler(opciones)
  }

  /// Opciones de presentación para una notificación que no es la remota de FCM.
  ///
  /// `flutter_local_notifications` resuelve estos flags en Dart y los escribe
  /// en el `userInfo` (`FlutterLocalNotificationsPlugin.m:86-90`). Los leemos de
  /// ahí en vez de fijarlos acá para que `DarwinNotificationDetails` siga siendo
  /// la única fuente de verdad: si mañana alguien apaga el sonido desde Dart,
  /// esto lo respeta solo.
  private func opcionesDe(_ userInfo: [AnyHashable: Any]) -> UNNotificationPresentationOptions {
    // Mismo criterio que `isAFlutterLocalNotification`
    // (`FlutterLocalNotificationsPlugin.m:1010-1014`). Si no es una local del
    // plugin es algo que no conocemos, y vale la misma regla de arriba:
    // mostrarla de más antes que comerse un aviso en silencio.
    guard userInfo["presentAlert"] != nil else {
      return [.banner, .list, .sound, .badge]
    }

    func prendido(_ clave: String) -> Bool {
      (userInfo[clave] as? NSNumber)?.boolValue ?? false
    }

    var opciones: UNNotificationPresentationOptions = []
    if prendido("presentBanner") { opciones.insert(.banner) }
    if prendido("presentList") { opciones.insert(.list) }
    if prendido("presentSound") { opciones.insert(.sound) }
    if prendido("presentBadge") { opciones.insert(.badge) }
    return opciones
  }
}
