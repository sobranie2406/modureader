import Flutter
import UIKit
import app_links
import UniformTypeIdentifiers

// app_links 6 uses application callbacks; UIScene delivers URLs to the scene
// instead. Route books to the import inbox, retaining their security scope.
@objc class ModuSceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
                      options connectionOptions: UIScene.ConnectionOptions) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    ExternalBookFiles.shared.receive(connectionOptions.urlContexts.map { $0.url })
    for context in connectionOptions.urlContexts {
      receiveReadingURL(context.url)
    }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    let otherContexts = Set(URLContexts.filter { !isReadingURL($0.url) && !$0.url.isFileURL })
    if !otherContexts.isEmpty { super.scene(scene, openURLContexts: otherContexts) }
    ExternalBookFiles.shared.receive(URLContexts.map { $0.url })
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
    if let url = launchOptions?[.url] as? URL, url.isFileURL {
      ExternalBookFiles.shared.receive([url])
      var otherOptions = launchOptions
      otherOptions?.removeValue(forKey: .url)
      return super.application(application, didFinishLaunchingWithOptions: otherOptions)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(_ app: UIApplication, open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
    if url.isFileURL {
      ExternalBookFiles.shared.receive([url])
      return true
    }
    return super.application(app, open: url, options: options)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ExternalBookFiles") {
      ExternalBookFiles.shared.register(registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ReaderVolumeKeysPlugin") {
      ReaderVolumeKeysPlugin.register(with: registrar)
    }
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
  private var pickingFiles = false
  private var linkedScopes = [String: URL]()
  private var scopeUsers = [URL: Int]()
  private let bookmarkKey = "moduLinkedBooksV1"
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
      pickingFiles = args["files"] as? Bool ?? false
      let picker = UIDocumentPickerViewController(
        forOpeningContentTypes: pickingFiles ? [.item] : [.folder], asCopy: false)
      picker.allowsMultipleSelection = pickingFiles
      picker.delegate = self
      presenter.present(picker, animated: true)
    case "link":
      worker.async {
        do {
          guard let id = args["id"] as? String, let source = self.entries[id],
                ["epub", "pdf", "mobi", "azw3", "fb2"].contains(source.pathExtension.lowercased()) else {
            throw CocoaError(.fileReadUnknown)
          }
          let key = "file/ios-linked-\(UUID().uuidString).\(source.pathExtension.lowercased())"
          // Persist the selected scope (folder or file), not an unrestricted path.
          let scope = self.pickingFiles ? source : (self.root ?? source)
          let bookmark = try scope.bookmarkData(options: .minimalBookmark,
            includingResourceValuesForKeys: nil, relativeTo: nil)
          let relative = self.pickingFiles ? "" : String(source.path.dropFirst(scope.path.count + 1))
          var records = UserDefaults.standard.dictionary(forKey: self.bookmarkKey) ?? [:]
          records[key] = ["bookmark": bookmark, "relative": relative]
          let path = try self.openLink(key, record: records[key])
          UserDefaults.standard.set(records, forKey: self.bookmarkKey)
          DispatchQueue.main.async { result(["key": key, "path": path]) }
        } catch {
          DispatchQueue.main.async { result(FlutterError(code: "LINK_FAILED", message: "Unable to retain original book access", details: nil)) }
        }
      }
    case "restoreLinks":
      worker.async {
        let records = UserDefaults.standard.dictionary(forKey: self.bookmarkKey) ?? [:]
        var paths = [String: String]()
        for (key, record) in records {
          // One missing/revoked provider must not block the rest of the shelf.
          if let path = try? self.openLink(key, record: record) { paths[key] = path }
        }
        DispatchQueue.main.async { result(paths) }
      }
    case "forgetLink":
      worker.async {
        if let key = args["key"] as? String {
          if let scope = self.linkedScopes.removeValue(forKey: key) { self.releaseScope(scope) }
          var records = UserDefaults.standard.dictionary(forKey: self.bookmarkKey) ?? [:]
          records.removeValue(forKey: key)
          UserDefaults.standard.set(records, forKey: self.bookmarkKey)
        }
        DispatchQueue.main.async { result(nil) }
      }
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
        for url in self.pickedFileScopes { url.stopAccessingSecurityScopedResource() }
        self.pickedFileScopes.removeAll()
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
    if pickingFiles {
      worker.async {
        var found = [[String: String]]()
        for url in urls where self.extensions.contains(url.pathExtension.lowercased()) {
          if url.startAccessingSecurityScopedResource() { self.pickedFileScopes.append(url) }
          let id = String(found.count)
          self.entries[id] = url
          found.append(["id": id, "name": url.lastPathComponent, "label": url.lastPathComponent])
        }
        DispatchQueue.main.async { result(found) }
      }
      return
    }
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

  private var pickedFileScopes = [URL]()

  private func acquireScope(_ url: URL) -> Bool {
    if let count = scopeUsers[url] { scopeUsers[url] = count + 1; return true }
    guard url.startAccessingSecurityScopedResource() else { return false }
    scopeUsers[url] = 1
    return true
  }

  private func releaseScope(_ url: URL) {
    guard let count = scopeUsers[url] else { return }
    if count > 1 { scopeUsers[url] = count - 1 }
    else {
      scopeUsers.removeValue(forKey: url)
      url.stopAccessingSecurityScopedResource()
    }
  }

  private func openLink(_ key: String, record: Any?) throws -> String {
    guard key.hasPrefix("file/ios-linked-"),
          let record = record as? [String: Any], let data = record["bookmark"] as? Data,
          let relative = record["relative"] as? String,
          !relative.hasPrefix("/"), !relative.split(separator: "/").contains("..") else {
      throw CocoaError(.fileReadCorruptFile)
    }
    var stale = false
    let scope = try URL(resolvingBookmarkData: data, options: .withoutUI,
      relativeTo: nil, bookmarkDataIsStale: &stale)
    // Books in one authorized folder share its scope instead of exhausting
    // iOS security-scoped resource slots with one access per book.
    let accessed = acquireScope(scope)
    do {
      let source = relative.isEmpty ? scope : scope.appendingPathComponent(relative)
      if !relative.isEmpty && !source.resolvingSymlinksInPath().path.hasPrefix(
          scope.resolvingSymlinksInPath().path + "/") {
        throw CocoaError(.fileReadNoPermission)
      }
      let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
      guard values.isRegularFile == true, values.isSymbolicLink != true,
            FileManager.default.isReadableFile(atPath: source.path) else {
        throw CocoaError(.fileReadNoPermission)
      }
      if stale {
        let renewed = try scope.bookmarkData(options: .minimalBookmark,
          includingResourceValuesForKeys: nil, relativeTo: nil)
        var records = UserDefaults.standard.dictionary(forKey: bookmarkKey) ?? [:]
        records[key] = ["bookmark": renewed, "relative": relative]
        UserDefaults.standard.set(records, forKey: bookmarkKey)
      }
      if let old = linkedScopes.removeValue(forKey: key) { releaseScope(old) }
      if accessed { linkedScopes[key] = scope }
      return source.path
    } catch {
      if accessed { releaseScope(scope) }
      throw error
    }
  }
}

/// Copy while the OS-granted scope is alive; Flutter only receives private files.
final class ExternalBookFiles {
  static let shared = ExternalBookFiles()
  private var channel: FlutterMethodChannel?
  private var ready = false
  private var pending = [String]()
  private var failed = false
  private let worker = DispatchQueue(label: "com.modu.reader.external-files")
  private let extensions: Set<String> = ["epub", "mobi", "azw3", "fb2", "txt", "pdf", "md", "markdown", "umd"]

  func register(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "com.modu.reader/external_files", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self, call.method == "ready" else {
        result(FlutterMethodNotImplemented); return
      }
      self.ready = true
      result(self.pending)
      self.pending.removeAll()
      if self.failed {
        self.failed = false
        channel.invokeMethod("error", arguments: "Unable to read the shared document. Check file access and retry.")
      }
    }
  }

  func receive(_ urls: [URL]) {
    for url in Set(urls) where url.isFileURL && extensions.contains(url.pathExtension.lowercased()) {
      let scoped = url.startAccessingSecurityScopedResource()
      worker.async {
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("modu-open-\(UUID().uuidString)")
        do {
          try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
          let target = folder.appendingPathComponent(url.lastPathComponent)
          var coordinationError: NSError?
          var copyError: Error?
          NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { source in
            do {
              guard try source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                throw CocoaError(.fileReadUnsupportedScheme)
              }
              try FileManager.default.copyItem(at: source, to: target)
            } catch { copyError = error }
          }
          if let error = coordinationError { throw error }
          if let error = copyError { throw error }
          guard FileManager.default.fileExists(atPath: target.path) else { throw CocoaError(.fileReadUnknown) }
          DispatchQueue.main.async {
            if self.ready { self.channel?.invokeMethod("files", arguments: [target.path]) }
            else { self.pending.append(target.path) }
          }
        } catch {
          try? FileManager.default.removeItem(at: folder)
          DispatchQueue.main.async {
            if self.ready {
              self.channel?.invokeMethod("error", arguments: "Unable to read the shared document. Check file access and retry.")
            } else { self.failed = true }
          }
        }
      }
    }
  }
}
