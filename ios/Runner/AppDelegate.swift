import Flutter
import UIKit
import app_links

// app_links 6 uses application callbacks; UIScene delivers URLs to the scene
// instead. Bridge only reading URLs and leave share/file callbacks untouched.
@objc class ModuSceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
                      options connectionOptions: UIScene.ConnectionOptions) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    for context in connectionOptions.urlContexts {
      receiveReadingURL(context.url)
    }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    let otherContexts = Set(URLContexts.filter { !isReadingURL($0.url) })
    if !otherContexts.isEmpty { super.scene(scene, openURLContexts: otherContexts) }
    for context in URLContexts { receiveReadingURL(context.url) }
  }

  private func isReadingURL(_ url: URL) -> Bool {
    return url.scheme == "modu" && url.host == "read"
  }

  private func receiveReadingURL(_ url: URL) {
    if isReadingURL(url) { AppLinks.shared.handleLink(url: url) }
  }
}

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
  }
}
