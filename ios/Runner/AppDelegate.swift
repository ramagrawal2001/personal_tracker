import Flutter
import UIKit
import UserNotifications
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var captureChannel: FlutterMethodChannel?
  /// Action that arrived before Dart asked for it (cold start).
  private var pendingAction: [String: String]?
  /// True once Dart has called `takeInitialAction` — later actions are pushed.
  private var dartReady = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Without a delegate iOS silently drops notifications while the app is
    // in the foreground (flutter_local_notifications needs this hook).
    UNUserNotificationCenter.current().delegate = self

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "com.aspyric.app/capture", binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { [weak self] call, result in
        self?.handle(call, result: result)
      }
      captureChannel = channel
    }

    if let url = launchOptions?[.url] as? URL {
      _ = deliver(url: url)
    }
    if let item = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
      deliver(shortcut: item)
      // Returning false stops iOS from also calling performActionFor.
      _ = super.application(application, didFinishLaunchingWithOptions: launchOptions)
      return false
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - Channel

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "takeInitialAction":
      dartReady = true
      result(pendingAction)
      pendingAction = nil
    case "drainCaptured":
      result([]) // iOS can't read SMS / other apps' notifications — Shortcuts use aspyric://capture
    case "localTimezone":
      result(TimeZone.current.identifier)
    case "recognizeText":
      guard let args = call.arguments as? [String: Any], let path = args["path"] as? String else {
        result(FlutterError(code: "bad_args", message: "path is required", details: nil))
        return
      }
      recognizeText(path: path, result: result)
    case "hasSmsPermission", "requestSmsPermission", "notificationAccessEnabled", "requestPinWidget", "requestAddTile":
      result(false)
    case "scanSmsInbox":
      result([])
    case "openNotificationAccessSettings", "setCaptureEnabled", "updateWidget":
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func push(_ action: [String: String]) {
    if dartReady, let channel = captureChannel {
      channel.invokeMethod("onAction", arguments: action)
    } else {
      pendingAction = action
    }
  }

  // MARK: - aspyric:// links (iOS Shortcuts automations, widgets later)

  private func deliver(url: URL) -> Bool {
    guard url.scheme == "aspyric", let host = url.host, !host.isEmpty else { return false }
    var action: [String: String] = ["kind": host]
    if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
      for item in items { if let v = item.value { action[item.name] = v } }
    }
    push(action)
    return true
  }

  override func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
    if deliver(url: url) { return true }
    return super.application(app, open: url, options: options)
  }

  // MARK: - Home-screen quick actions (long-press the app icon)

  private func deliver(shortcut: UIApplicationShortcutItem) {
    switch shortcut.type {
    case "com.aspyric.add_expense": push(["kind": "add", "type": "expense", "source": "shortcut"])
    case "com.aspyric.add_income": push(["kind": "add", "type": "income", "source": "shortcut"])
    case "com.aspyric.voice": push(["kind": "voice", "source": "shortcut"])
    case "com.aspyric.scan": push(["kind": "scan", "source": "shortcut"])
    default: break
    }
  }

  override func application(
    _ application: UIApplication,
    performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) {
    deliver(shortcut: shortcutItem)
    completionHandler(true)
  }

  // MARK: - On-device OCR (Apple Vision — free, offline)

  private func recognizeText(path: String, result: @escaping FlutterResult) {
    guard let image = UIImage(contentsOfFile: path), let cg = image.cgImage else {
      result(FlutterError(code: "ocr_failed", message: "Could not read image", details: nil))
      return
    }
    let request = VNRecognizeTextRequest { req, err in
      if let err = err {
        DispatchQueue.main.async { result(FlutterError(code: "ocr_failed", message: err.localizedDescription, details: nil)) }
        return
      }
      let lines = (req.results as? [VNRecognizedTextObservation] ?? [])
        .compactMap { $0.topCandidates(1).first?.string }
      DispatchQueue.main.async { result(lines.joined(separator: "\n")) }
    }
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    let orientation = CGImagePropertyOrientation(image.imageOrientation)
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try VNImageRequestHandler(cgImage: cg, orientation: orientation, options: [:]).perform([request])
      } catch {
        DispatchQueue.main.async { result(FlutterError(code: "ocr_failed", message: error.localizedDescription, details: nil)) }
      }
    }
  }
}

private extension CGImagePropertyOrientation {
  init(_ o: UIImage.Orientation) {
    switch o {
    case .up: self = .up
    case .down: self = .down
    case .left: self = .left
    case .right: self = .right
    case .upMirrored: self = .upMirrored
    case .downMirrored: self = .downMirrored
    case .leftMirrored: self = .leftMirrored
    case .rightMirrored: self = .rightMirrored
    @unknown default: self = .up
    }
  }
}
