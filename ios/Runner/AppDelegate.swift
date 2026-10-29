import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ICloudSyncPlugin") {
      ICloudSyncPlugin.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "IOSAudioPlugin") {
      IOSAudioPlugin.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppInfoPlugin") {
      let channel = FlutterMethodChannel(name: "goodgoodstudy/app_info", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "getInfo":
          result([
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            "buildNumber": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
          ])
        case "openLink":
          guard let raw = (call.arguments as? [String: Any])?["url"] as? String,
                let url = URL(string: raw), url.scheme == "https", url.host == "github.com",
                url.user == nil, url.password == nil, url.port == nil,
                url.query == nil, url.fragment == nil,
                ["/moonsoo531/GoodGoodStudy", "/moonsoo531/GoodGoodStudy/blob/main/LICENSE",
                 "/moonsoo531/GoodGoodStudy/blob/main/THIRD_PARTY_NOTICES.md",
                 "/moonsoo531/GoodGoodStudy/blob/main/docs/privacy-policy.md",
                 "/moonsoo531/GoodGoodStudy/blob/main/docs/study-package-v1.md",
                 "/moonsoo531/GoodGoodStudy/blob/main/docs/quiz-package-v1.md"].contains(url.path) else {
            result(false)
            return
          }
          UIApplication.shared.open(url, options: [:]) { result($0) }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
