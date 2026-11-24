import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Optional Google Maps key from ios/Flutter/Secrets.xcconfig via Info.plist.
  private var mapsKey: String {
    let raw = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String ?? ""
    let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    // An unset build variable comes through literally or empty.
    return key.hasPrefix("$(") ? "" : key
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if !mapsKey.isEmpty {
      GMSServices.provideAPIKey(mapsKey)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "flock/config",
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
    let hasKey = !mapsKey.isEmpty
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "hasGoogleMapsKey": result(hasKey)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
}
