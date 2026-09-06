import Foundation
import MetricKit
#if os(macOS)
import FlutterMacOS
#else
import Flutter
#endif

public class ModuNativeCrashPlugin: NSObject, FlutterPlugin, MXMetricManagerSubscriber {
    private static let shared = ModuNativeCrashPlugin()
    private let queue = DispatchQueue(label: "com.modu.reader.native-crash")
    private var subscribed = false
    private var file: URL? {
        // Own sandbox/support directory only, not the user's DiagnosticReports.
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return root.appendingPathComponent("com.modu.reader/native-crash/apple.json")
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        #if os(macOS)
        let messenger = registrar.messenger
        #else
        let messenger = registrar.messenger()
        #endif
        let channel = FlutterMethodChannel(name: "com.modu.reader/crash_diagnostics", binaryMessenger: messenger)
        registrar.addMethodCallDelegate(shared, channel: channel)
        if !shared.subscribed {
            shared.subscribed = true
            MXMetricManager.shared.add(shared)
            shared.didReceive(MXMetricManager.shared.pastDiagnosticPayloads)
        }
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "read" else { result(FlutterMethodNotImplemented); return }
        queue.async {
            let records = self.readRecords()
            DispatchQueue.main.async {
                result(["source": "apple-metrickit", "records": records])
            }
        }
    }

    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        queue.async {
            var records = self.readRecords()
            for payload in payloads.suffix(8) {
                for crash in (payload.crashDiagnostics ?? []).prefix(3) {
                    let version = crash.applicationVersion
                    let safeVersion = version.range(of: "^[0-9A-Za-z.+-]{1,60}$", options: .regularExpression) != nil ? version : "unknown"
                    let record: [String: Any] = [
                        // MetricKit provides a reporting interval, NOT an exact crash time.
                        "periodStart": Int64(payload.timeStampBegin.timeIntervalSince1970 * 1000),
                        "periodEnd": Int64(payload.timeStampEnd.timeIntervalSince1970 * 1000),
                        "version": safeVersion,
                        "code": crash.exceptionType?.int64Value ?? -1,
                        "signal": crash.signal?.int64Value ?? -1,
                        "frames": NativeCrashSummary.frames(crash.callStackTree.jsonRepresentation())
                    ]
                    // Suppress duplicate past-payload delivery. All values already allowlisted.
                    if !records.contains(where: { NSDictionary(dictionary: $0).isEqual(to: record) }) {
                        records.append(record)
                    }
                }
            }
            records.sort { ($0["periodEnd"] as? Int64 ?? 0) < ($1["periodEnd"] as? Int64 ?? 0) }
            guard let file = self.file,
                  let data = try? JSONSerialization.data(withJSONObject: Array(records.suffix(3))),
                  data.count <= 32_768 else { return }
            do {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: file, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                var excluded = file
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try excluded.setResourceValues(values)
            } catch { /* Diagnostics must not interrupt startup or reading. */ }
        }
    }

    private func readRecords() -> [[String: Any]] {
        guard let file = file,
              let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 32_768,
              let data = try? Data(contentsOf: file),
              let records = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return Array(records.suffix(3))
    }
}
