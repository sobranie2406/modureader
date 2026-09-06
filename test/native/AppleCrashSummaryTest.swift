import Foundation

@main
struct AppleCrashSummaryTest {
    static func main() throws {
        let privateFrame: [String: Any] = [
            "binaryName": "/Users/SECRET/book", "address": 123456789,
            "offsetIntoBinaryTextSegment": 16, "binaryUUID": "SECRET_KEY",
            "function": "SECRET", "registers": "SECRET"
        ]
        let frame: [String: Any] = [
            "binaryName": "onnxruntime", "offsetIntoBinaryTextSegment": 12,
            "binaryUUID": "AABBCCDD-1122-3344-5566-77889900AABB",
            "subFrames": [privateFrame]
        ]
        let data = try JSONSerialization.data(withJSONObject: ["callStackTree": [
            "callStacks": [
                ["threadAttributed": false, "callStackRootFrames": [privateFrame]],
                ["threadAttributed": true, "callStackRootFrames": [frame]]
            ]
        ]])
        let result = NativeCrashSummary.frames(data)
        precondition(result.count == 2)
        precondition(result[0]["module"] as? String == "onnxruntime")
        precondition(result[1]["module"] as? String == "omitted")
        let serialized = String(data: try JSONSerialization.data(withJSONObject: result), encoding: .utf8)!
        precondition(!serialized.contains("SECRET") && !serialized.contains("123456789"))
        precondition(NativeCrashSummary.frames(Data("bad PRIVATE".utf8)).isEmpty)
        precondition(NativeCrashSummary.frames(Data(repeating: 32, count: 1_048_577)).isEmpty)
        let many = try JSONSerialization.data(withJSONObject: ["callStackTree": [
            "callStacks": [["threadAttributed": true,
                            "callStackRootFrames": Array(repeating: frame, count: 100)]]]
        ])
        precondition(NativeCrashSummary.frames(many).count == 32)
        print("Apple native summary: privacy, fault-thread selection, malformed/oversized data and 32-frame limit passed")
    }
}
