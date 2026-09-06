import Foundation

/// Pure allowlist boundary. No exception reasons, registers, memory, paths,
/// device IDs, signposts, or arbitrary symbol names ever enter the local file.
enum NativeCrashSummary {
    static let libraries: Set<String> = [
        "Modu", "Runner", "App", "Flutter", "FlutterMacOS", "onnxruntime",
        "flutter_onnxruntime", "libonnxruntime.dylib", "tokenizers_ffi",
        "libtokenizers_ffi.dylib", "libsystem_kernel.dylib",
        "libsystem_pthread.dylib", "libsystem_c.dylib", "libsystem_malloc.dylib",
        "libc++abi.dylib", "libc++.1.dylib", "libobjc.A.dylib", "libdyld.dylib",
        "dyld", "Foundation", "CoreFoundation", "AppKit", "UIKitCore"
    ]

    static func frames(_ data: Data) -> [[String: Any]] {
        guard data.count <= 1_048_576,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tree = root["callStackTree"] as? [String: Any],
              let stacks = tree["callStacks"] as? [[String: Any]] else { return [] }
        var result: [[String: Any]] = []
        // Only the attributed (faulting) stack. Never substitute an unrelated thread.
        for stack in stacks.prefix(256) where (stack["threadAttributed"] as? Bool) == true {
            var pending = Array((stack["callStackRootFrames"] as? [[String: Any]] ?? []).prefix(32).reversed())
            var visited = 0
            while let frame = pending.popLast(), result.count < 32, visited < 128 {
                visited += 1
                let name = frame["binaryName"] as? String ?? ""
                let offset = frame["offsetIntoBinaryTextSegment"] as? NSNumber
                if let offset = offset, offset.int64Value >= 0 {
                    let uuid = frame["binaryUUID"] as? String ?? ""
                    let validID = uuid.range(of: "^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$", options: .regularExpression) != nil
                    result.append([
                        "module": libraries.contains(name) ? name : "omitted",
                        "offset": offset.int64Value,
                        "buildId": validID ? uuid : "unknown"
                    ])
                }
                pending.append(contentsOf: (frame["subFrames"] as? [[String: Any]] ?? []).prefix(32).reversed())
            }
            if result.count >= 32 { break }
        }
        return result
    }
}
