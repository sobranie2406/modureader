import Flutter
import UIKit
import app_links
import UniformTypeIdentifiers

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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BookFolderPlugin") {
      BookFolderPlugin.register(with: registrar)
    }
  }
}

/// Retains scoped access until selection and copying have completed.
final class BookFolderPlugin: NSObject, FlutterPlugin, UIDocumentPickerDelegate {
  private var registrar: FlutterPluginRegistrar?
  private var pending: FlutterResult?
  private var root: URL?
  private var scoped = false
  private var extensions = Set<String>()
  private var entries = [String: URL]()
  private let worker = DispatchQueue(label: "com.modu.reader.book-folder")

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = BookFolderPlugin()
    instance.registrar = registrar
    registrar.addMethodCallDelegate(instance, channel: FlutterMethodChannel(
      name: "com.modu.reader/book_folder", binaryMessenger: registrar.messenger()))
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "pick":
      guard pending == nil, var presenter = registrar?.viewController else {
        result(FlutterError(code: "UNAVAILABLE", message: "Folder picker unavailable", details: nil)); return
      }
      while let presented = presenter.presentedViewController { presenter = presented }
      pending = result
      extensions = Set(args["extensions"] as? [String] ?? [])
      let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
      picker.delegate = self
      presenter.present(picker, animated: true)
    case "copy":
      let ids = args["ids"] as? [String] ?? []
      worker.async {
        let session = FileManager.default.temporaryDirectory.appendingPathComponent("book-folder-\(UUID().uuidString)")
        do {
          var paths = [String]()
          for (index, id) in ids.enumerated() {
            guard let source = self.entries[id] else { throw CocoaError(.fileReadUnknown) }
            let dir = session.appendingPathComponent(String(index))
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let target = dir.appendingPathComponent(source.lastPathComponent)
            var coordinationError: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { url in
              do { try FileManager.default.copyItem(at: url, to: target) }
              catch { copyError = error }
            }
            if let error = coordinationError { throw error }
            if let error = copyError { throw error }
            paths.append(target.path)
          }
          DispatchQueue.main.async { result(paths) }
        } catch {
          try? FileManager.default.removeItem(at: session)
          DispatchQueue.main.async { result(FlutterError(code: "READ_FAILED", message: "Unable to copy selected books", details: nil)) }
        }
      }
    case "release":
      worker.async {
        self.entries.removeAll()
        if self.scoped { self.root?.stopAccessingSecurityScopedResource() }
        self.root = nil
        self.scoped = false
        DispatchQueue.main.async { result(nil) }
      }
    default: result(FlutterMethodNotImplemented)
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pending?(nil)
    pending = nil
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let result = pending, let folder = urls.first else { return }
    pending = nil
    root = folder
    scoped = folder.startAccessingSecurityScopedResource()
    worker.async {
      do {
        var found = [[String: String]]()
        func visit(_ directory: URL, prefix: String) throws {
          let children = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
          for child in children {
            let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { continue }
            let name = child.lastPathComponent
            let label = prefix.isEmpty ? name : "\(prefix)/\(name)"
            if values.isDirectory == true { try visit(child, prefix: label) }
            else if values.isRegularFile == true && self.extensions.contains(child.pathExtension.lowercased()) {
              let id = String(found.count)
              self.entries[id] = child
              found.append(["id": id, "name": name, "label": label])
            }
          }
        }
        try visit(folder, prefix: "")
        let sorted = found.sorted { ($0["label"] ?? "").localizedStandardCompare($1["label"] ?? "") == .orderedAscending }
        DispatchQueue.main.async { result(sorted) }
      } catch {
        DispatchQueue.main.async { result(FlutterError(code: "READ_FAILED", message: "Unable to read selected folder", details: nil)) }
      }
    }
  }
}
