import Cocoa
import CoreImage
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var configTransferChannel: FlutterMethodChannel?
  private var readerFocusChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerConfigTransferChannel(flutterViewController)
    registerReaderFocusChannel(flutterViewController)

    super.awakeFromNib()
  }

  private func registerReaderFocusChannel(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "com.modu.reader/reader_focus",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self, weak controller] call, result in
      guard call.method == "restore" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let self, let controller else {
        result(false)
        return
      }
      result(self.makeFirstResponder(controller.view))
    }
    readerFocusChannel = channel
  }

  private func registerConfigTransferChannel(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "com.modu.reader/config_transfer",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "UNAVAILABLE", message: "Window is unavailable", details: nil))
        return
      }
      switch call.method {
      case "generateQrCode":
        guard
          let arguments = call.arguments as? [String: Any],
          let text = arguments["text"] as? String,
          !text.isEmpty
        else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: "QR text is empty", details: nil))
          return
        }
        guard let data = self.generateQrCode(text) else {
          result(FlutterError(
            code: "QR_TOO_LARGE",
            message: "配置内容过长，无法生成单个二维码，请使用配置代码导入。",
            details: nil
          ))
          return
        }
        result(FlutterStandardTypedData(bytes: data))
      case "decodeQrCode":
        guard
          let arguments = call.arguments as? [String: Any],
          let path = arguments["path"] as? String,
          !path.isEmpty
        else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: "Image path is empty", details: nil))
          return
        }
        guard let value = self.decodeQrCode(path) else {
          result(FlutterError(
            code: "QR_NOT_FOUND",
            message: "图片中没有识别到有效二维码。",
            details: nil
          ))
          return
        }
        result(value)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    configTransferChannel = channel
  }

  private func generateQrCode(_ text: String) -> Data? {
    guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
    filter.setValue(Data(text.utf8), forKey: "inputMessage")
    filter.setValue("L", forKey: "inputCorrectionLevel")
    guard let output = filter.outputImage else { return nil }

    let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
    let context = CIContext(options: [.useSoftwareRenderer: false])
    guard let image = context.createCGImage(scaled, from: scaled.extent.integral) else {
      return nil
    }
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
  }

  private func decodeQrCode(_ path: String) -> String? {
    guard let image = CIImage(contentsOf: URL(fileURLWithPath: path)) else {
      return nil
    }
    let context = CIContext(options: [.useSoftwareRenderer: false])
    guard let detector = CIDetector(
      ofType: CIDetectorTypeQRCode,
      context: context,
      options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
    ) else {
      return nil
    }
    return detector.features(in: image)
      .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
      .first
  }
}
