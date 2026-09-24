import Cocoa

/// Own the overlay host instead of inserting views into AppKit's theme frame.
/// Flutter can freely compose platform views inside its child controller.
final class BrightnessContentViewController: NSViewController {
  private let contentController: NSViewController

  init(contentController: NSViewController) {
    self.contentController = contentController
    super.init(nibName: nil, bundle: nil)
    addChild(contentController)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func loadView() {
    let content = contentController.view
    let container = NSView(frame: content.frame)
    container.wantsLayer = true
    content.frame = container.bounds
    content.autoresizingMask = [.width, .height]
    container.addSubview(content)
    view = container
  }
}

/// Lives outside Flutter's platform-view composition. It only paints: neither
/// hit testing nor the first-responder chain may ever select this view.
final class BrightnessDimView: NSView {
  override var acceptsFirstResponder: Bool { false }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { false }

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    setAccessibilityElement(false)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  func setBrightness(_ value: Double?) {
    let opacity = value.map { 1 - min(1, max(0.2, $0)) } ?? 0
    layer?.backgroundColor = NSColor.black.withAlphaComponent(opacity).cgColor
    isHidden = opacity == 0
  }
}

final class WindowBrightness {
  private weak var window: NSWindow?
  private let dimmer = BrightnessDimView(frame: .zero)
  private var resizeObserver: NSObjectProtocol?

  init(window: NSWindow) {
    self.window = window
    resizeObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didResizeNotification, object: window, queue: .main
    ) { [weak self] _ in self?.layout() }
  }

  deinit {
    if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
  }

  func setBrightness(_ value: Double?) {
    layout()
    dimmer.setBrightness(value)
    // Do not order/activate a window or change its first responder here.
  }

  private func layout() {
    guard let controller = window?.contentViewController as? BrightnessContentViewController
    else { return }
    let host = controller.view
    // This is our own container, never the private AppKit title/frame view.
    // The dimmer remains a sibling of Flutter's root, outside its composition.
    if dimmer.superview !== host {
      dimmer.removeFromSuperview()
      dimmer.autoresizingMask = [.width, .height]
      host.addSubview(dimmer, positioned: .above, relativeTo: nil)
    }
    dimmer.frame = host.bounds
  }
}
