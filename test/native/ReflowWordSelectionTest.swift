import Foundation
import NaturalLanguage

// Compile with the ReflowWordSelection enum from MainFlutterWindow.swift.
@main
struct ReflowWordSelectionTest {
  static func main() {
    precondition(ReflowWordSelection.bounds(text: "中国文化", offset: 0) == [0, 2])
    precondition(ReflowWordSelection.bounds(text: "中国文化", offset: 1) == [0, 2])
    precondition(ReflowWordSelection.bounds(text: "Hello reader", offset: 8) == [6, 12])
    precondition(ReflowWordSelection.bounds(text: "😀中国文化", offset: 3) == [2, 4])
    precondition(ReflowWordSelection.bounds(text: "😀", offset: 1) == nil)
    precondition(ReflowWordSelection.bounds(text: "中国。", offset: 2) == nil)
    precondition(ReflowWordSelection.bounds(text: "中国 文化", offset: 2) == nil)
    precondition(ReflowWordSelection.bounds(text: "Hello", offset: 5) == [0, 5])
    precondition(ReflowWordSelection.bounds(text: "", offset: 0) == nil)
    precondition(ReflowWordSelection.bounds(text: "中国", offset: -1) == nil)
    precondition(ReflowWordSelection.bounds(text: "中国", offset: 3) == nil)
    precondition(ReflowWordSelection.bounds(text: String(repeating: "中", count: 65537), offset: 0) == nil)
    print("macOS system word selection: 12 checks passed")
  }
}
