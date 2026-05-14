import Flutter
import flutter_downloader
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Required by `flutter_downloader` so that the background URLSession
    // can resume Flutter plugin registration from a background launch and
    // dispatch progress events back to the Dart side.
    FlutterDownloaderPlugin.setPluginRegistrantCallback(registerPlugins)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

/// Registers plugins for the background isolate that `flutter_downloader`
/// spins up when iOS resumes a finished URLSession after the app has been
/// suspended. Must be a top-level function with this exact signature.
private func registerPlugins(_ registry: FlutterPluginRegistry) {
  if !registry.hasPlugin("FlutterDownloaderPlugin") {
    FlutterDownloaderPlugin.register(
      with: registry.registrar(forPlugin: "FlutterDownloaderPlugin")!)
  }
}
