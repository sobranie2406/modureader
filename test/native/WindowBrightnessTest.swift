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
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    window.title = "Modu"
    let content = InputView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
    let contentController = NSViewController()
    contentController.view = content
    window.contentViewController = BrightnessContentViewController(contentController: contentController)
    window.orderFront(nil)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    precondition(window.makeFirstResponder(content))
    let host = content.superview!
    let frameView = host.superview!
    let originalFrameChildren = frameView.subviews
    func titleField(_ view: NSView) -> NSTextField? {
      if let text = view as? NSTextField, text.stringValue == "Modu" { return text }
      return view.subviews.lazy.compactMap { titleField($0) }.first
    }
    let title = titleField(frameView)!
    let initialTitleFrame = title.convert(title.bounds, to: nil)
    func checkTitle() {
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
      precondition(frameView.subviews == originalFrameChildren, "Brightness must not alter AppKit frame children")
      let button = window.standardWindowButton(.zoomButton)!
      precondition(title.convert(title.bounds, to: nil).minX >= button.convert(button.bounds, to: nil).maxX,
                   "Window title must not overlap traffic-light buttons")
    }
    func hit() -> NSView? {
      host.hitTest(host.convert(content.convert(NSPoint(x: 50, y: 50), to: host), to: host.superview))
    }
    let originalHit = hit()
    precondition(originalHit === content)
    let brightness = WindowBrightness(window: window)
    for level: Double? in [nil, 0.2, 0.6, 1.0, nil, 0.35] {
      brightness.setBrightness(level)
      checkTitle()
      precondition(title.convert(title.bounds, to: nil) == initialTitleFrame)
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
    precondition(content.keys == 6)
    window.setContentSize(NSSize(width: 800, height: 600))
    NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: window)
    let dimmer = host.subviews.compactMap { $0 as? BrightnessDimView }.first!
    precondition(dimmer.frame == content.convert(content.bounds, to: host))
    precondition(content.frame == host.bounds, "Flutter must fill the wrapper after resizing")
    checkTitle()
    precondition(hit() === originalHit)
    brightness.setBrightness(nil)
    precondition(dimmer.isHidden)
    window.orderOut(nil)
    checkTitle()
    print("Window brightness titlebar, native hit-testing, focus, resize and reset checks passed")
  }
}
