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
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Held strongly: the method channel's handler dies with it, and a released
  /// launcher would make the watch silently stop opening.
  private var watchLauncher: WatchLauncher?

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // The messenger comes from the plugin registry, NOT from
    // `window.rootViewController as? FlutterViewController`. Under the implicit
    // engine pattern that cast is unreliable at this point, and the snippet
    // found in most Flutter docs silently no-ops here.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "WatchLauncher") {
      watchLauncher = WatchLauncher.register(with: registrar.messenger())
    }
  }
}
