import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    ExternalBookFiles.shared.receive(filenames.map { URL(fileURLWithPath: $0) })
    sender.reply(toOpenOrPrint: .success)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
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

final class LinkedBookFiles {
  static let shared = LinkedBookFiles()
  private var channel: FlutterMethodChannel?
  private var selected = [String: URL]()
  private var selectionRoots = [URL]()
  private var linkedRoots = [String: URL]()
  private var records: [String: [String: Any]] {
    get { UserDefaults.standard.dictionary(forKey: "moduLinkedBooksV1") as? [String: [String: Any]] ?? [:] }
    set { UserDefaults.standard.set(newValue, forKey: "moduLinkedBooksV1") }
  }
  func register(_ messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "com.modu.reader/book_folder", binaryMessenger: messenger)
    channel?.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      let args = call.arguments as? [String: Any] ?? [:]
      do {
        switch call.method {
        case "pick":
          self.releaseSelection()
          let files = args["files"] as? Bool ?? false
          let extensions = Set(args["extensions"] as? [String] ?? [])
          let panel = NSOpenPanel()
          panel.canChooseFiles = files; panel.canChooseDirectories = !files
          panel.allowsMultipleSelection = files
          panel.begin { response in
            guard response == .OK else { result(nil); return }
            var output = [[String: String]]()
            for root in panel.urls {
              if root.startAccessingSecurityScopedResource() { self.selectionRoots.append(root) }
              let urls = files ? [root] : (FileManager.default.enumerator(at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles])?.allObjects as? [URL] ?? [])
              for url in urls where extensions.contains(url.pathExtension.lowercased()) {
                guard let v = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                      v.isRegularFile == true, v.isSymbolicLink != true else { continue }
                let id = UUID().uuidString
                self.selected[id] = url
                output.append(["id": id, "name": url.lastPathComponent, "label": url.lastPathComponent])
              }
            }
            result(output)
          }
        case "link":
          guard let id = args["id"] as? String, let url = selected[id] else { throw CocoaError(.fileReadUnknown) }
          let root = selectionRoots.first(where: { url == $0 || url.path.hasPrefix($0.path + "/") }) ?? url
          let data = try root.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil, relativeTo: nil)
          let key = "file/linked-\(UUID().uuidString).\(url.pathExtension.lowercased())"
          let relative = root == url ? "" : String(url.path.dropFirst(root.path.count + 1))
          let record: [String: Any] = ["bookmark": data, "relative": relative]
          let path = try open(key, record)
          var saved = records; saved[key] = record; records = saved
          result(["key": key, "path": path])
        case "restoreLinks":
          var paths = [String: String]()
          for (key, record) in records { if let path = try? open(key, record) { paths[key] = path } }
          result(paths)
        case "forgetLink":
          if let key = args["key"] as? String {
            if let root = linkedRoots.removeValue(forKey: key) { root.stopAccessingSecurityScopedResource() }
            var saved = records; saved.removeValue(forKey: key); records = saved
          }
          result(nil)
        case "release": releaseSelection(); result(nil)
        default: result(FlutterMethodNotImplemented)
        }
      } catch { result(FlutterError(code: "LINK_FAILED", message: "Unable to retain original book access", details: nil)) }
    }
  }
  private func releaseSelection() {
    selectionRoots.forEach { $0.stopAccessingSecurityScopedResource() }
    selectionRoots.removeAll(); selected.removeAll()
  }
  private func open(_ key: String, _ record: [String: Any]) throws -> String {
    guard key.hasPrefix("file/linked-"), let data = record["bookmark"] as? Data,
      let relative = record["relative"] as? String,
      !relative.hasPrefix("/"), !relative.split(separator: "/").contains("..") else { throw CocoaError(.fileReadCorruptFile) }
    var stale = false
    let root = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
      relativeTo: nil, bookmarkDataIsStale: &stale)
    guard root.startAccessingSecurityScopedResource() else { throw CocoaError(.fileReadNoPermission) }
    let target = relative.isEmpty ? root : root.appendingPathComponent(relative)
    do {
      if !relative.isEmpty && !target.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/") {
        throw CocoaError(.fileReadNoPermission)
      }
      guard try target.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true,
        FileManager.default.isReadableFile(atPath: target.path) else { throw CocoaError(.fileReadNoPermission) }
      if stale {
        var saved = records
        saved[key] = ["bookmark": try root.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
          includingResourceValuesForKeys: nil, relativeTo: nil), "relative": relative]
        records = saved
      }
      if let old = linkedRoots.updateValue(root, forKey: key) { old.stopAccessingSecurityScopedResource() }
      return target.path
    } catch { root.stopAccessingSecurityScopedResource(); throw error }
  }
}
