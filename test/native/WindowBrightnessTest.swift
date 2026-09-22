import Cocoa

private final class InputView: NSView {
  override var acceptsFirstResponder: Bool { true }
  var keys = 0
  override func keyDown(with event: NSEvent) { keys += 1 }
}

@main
struct WindowBrightnessTest {
  static func main() {
    _ = NSApplication.shared
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    let content = InputView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
    window.contentView = content
    precondition(window.makeFirstResponder(content))
    let host = content.superview!
    func hit() -> NSView? {
      host.hitTest(host.convert(content.convert(NSPoint(x: 50, y: 50), to: host), to: host.superview))
    }
    let originalHit = hit()
    precondition(originalHit === content)
    let brightness = WindowBrightness(window: window)
    for level: Double? in [0.2, 0.6, 1.0, nil, 0.35] {
      brightness.setBrightness(level)
      precondition(hit() === originalHit, "Dimming must pass native mouse hits through")
      precondition(window.firstResponder === content, "Dimming must not steal keyboard focus")
      let dimmer = host.subviews.compactMap { $0 as? BrightnessDimView }.first!
      precondition(dimmer.hitTest(.zero) == nil)
      precondition(!dimmer.acceptsFirstResponder)
      precondition(dimmer.isHidden == (level == nil || level == 1))
      let alpha = dimmer.layer!.backgroundColor!.alpha
      precondition(abs(alpha - (1 - (level ?? 1))) < 0.001)
      let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
          timestamp: 0, windowNumber: window.windowNumber, context: nil,
          characters: "\u{F703}", charactersIgnoringModifiers: "\u{F703}",
          isARepeat: false, keyCode: 124)!
      window.firstResponder?.keyDown(with: key)
    }
    precondition(content.keys == 5)
    window.setContentSize(NSSize(width: 800, height: 600))
    NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: window)
    let dimmer = host.subviews.compactMap { $0 as? BrightnessDimView }.first!
    precondition(dimmer.frame == content.convert(content.bounds, to: host))
    precondition(hit() === originalHit)
    brightness.setBrightness(nil)
    precondition(dimmer.isHidden)
    window.orderOut(nil)
    print("Window brightness native hit-testing, focus, resize and reset checks passed")
  }
}
