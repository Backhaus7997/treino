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

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
