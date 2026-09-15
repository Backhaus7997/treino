import Flutter
import UIKit

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

    // The messenger comes from the plugin registry, NOT from
    // `window.rootViewController as? FlutterViewController`. Under the implicit
    // engine pattern that cast is unreliable at this point, and the snippet
    // found in most Flutter docs silently no-ops here.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "WatchLauncher") {
      watchLauncher = WatchLauncher.register(with: registrar.messenger())
    }
  }
}
