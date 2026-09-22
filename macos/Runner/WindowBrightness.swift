import Cocoa

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
    guard let content = window?.contentView else { return }
    // Flutter manages the content view's children. Place the dimmer alongside
    // it so subsequent platform-view composition cannot reorder the dimmer.
    let host = content.superview ?? content
    if dimmer.superview !== host {
      dimmer.removeFromSuperview()
      host.addSubview(dimmer, positioned: .above, relativeTo: content === host ? nil : content)
    }
    dimmer.frame = content.convert(content.bounds, to: host)
  }
}
