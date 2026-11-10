import Flutter
import UIKit
import UserNotifications
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Uygulama açıkken de bildirim gösterilsin (flutter_local_notifications).
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NobetciOcr") {
      OcrPlugin.register(with: registrar)
    }
  }
}

/// Fotoğraftaki / PDF sayfasındaki metni cihaz üstünde (internetsiz) okur:
/// Apple Vision. Her metin kutusu 0–1 arası koordinatlarla (y üstten) döner.
class OcrPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "nobetci/ocr", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(OcrPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "recognize",
      let args = call.arguments as? [String: Any],
      let image = args["image"] as? FlutterStandardTypedData
    else {
      result(FlutterMethodNotImplemented)
      return
    }
    DispatchQueue.global(qos: .userInitiated).async {
      let request = VNRecognizeTextRequest { req, err in
        if let err = err {
          DispatchQueue.main.async {
            result(FlutterError(code: "ocr", message: err.localizedDescription, details: nil))
          }
          return
        }
        var boxes: [[String: Any]] = []
        for observation in (req.results as? [VNRecognizedTextObservation]) ?? [] {
          guard let best = observation.topCandidates(1).first else { continue }
          let b = observation.boundingBox
          boxes.append([
            "text": best.string,
            "x": Double(b.minX),
            "y": Double(1 - b.maxY),
            "w": Double(b.width),
            "h": Double(b.height),
          ])
        }
        DispatchQueue.main.async { result(boxes) }
      }
      request.recognitionLevel = .accurate
      // Adlar sözlüğe göre "düzeltilmesin".
      request.usesLanguageCorrection = false
      if #available(iOS 15.0, *) {
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        let wanted = ["tr-TR", "en-US"].filter { supported.contains($0) }
        if !wanted.isEmpty { request.recognitionLanguages = wanted }
      }
      let handler = VNImageRequestHandler(data: image.data, options: [:])
      do {
        try handler.perform([request])
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "ocr", message: error.localizedDescription, details: nil))
        }
      }
    }
  }
}
