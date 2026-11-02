import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var activeSecurityScopedURL: URL?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    setupNativeFileChannel(engineBridge: engineBridge)
  }

  private func setupNativeFileChannel(engineBridge: FlutterImplicitEngineBridge) {
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NativeFilePickerPlugin") else {
      return
    }
    let channel = FlutterMethodChannel(name: "openmoney/native_file_picker", binaryMessenger: registrar.messenger())

    channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard let self = self else {
        result(nil)
        return
      }

      switch call.method {
      case "pickFile":
        let args = call.arguments as? [String: Any]
        let allowedExts = (args?["allowedExtensions"] as? [String]) ?? ["json"]
        self.presentFilePicker(allowedExtensions: allowedExts, result: result)

      case "saveFile":
        let args = call.arguments as? [String: Any]
        let defaultName = (args?["defaultName"] as? String) ?? "openmoney.json"
        self.presentFileSaver(defaultName: defaultName, result: result)

      case "startAccessingPath":
        let args = call.arguments as? [String: Any]
        let path = args?["path"] as? String ?? ""
        if !path.isEmpty {
          let url = URL(fileURLWithPath: path)
          self.stopAccessingCurrentSecurityResource()
          if url.startAccessingSecurityScopedResource() {
            self.activeSecurityScopedURL = url
          }
        }
        result(true)

      case "resolveBookmark":
        let args = call.arguments as? [String: Any]
        guard let bookmarkB64 = args?["bookmark"] as? String,
              let bookmarkData = Data(base64Encoded: bookmarkB64) else {
          result(nil)
          return
        }
        var isStale = false
        do {
          let resolvedURL = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
          )
          self.stopAccessingCurrentSecurityResource()
          if resolvedURL.startAccessingSecurityScopedResource() {
            self.activeSecurityScopedURL = resolvedURL
          }
          var ret: [String: Any] = ["path": resolvedURL.path]
          if isStale, let freshBookmark = try? resolvedURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            ret["bookmark"] = freshBookmark.base64EncodedString()
          }
          result(ret)
        } catch {
          result(nil)
        }

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func stopAccessingCurrentSecurityResource() {
    if let active = activeSecurityScopedURL {
      active.stopAccessingSecurityScopedResource()
      activeSecurityScopedURL = nil
    }
  }

  private func topViewController() -> UIViewController? {
    let keyWindow = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }

    var top = keyWindow?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }

  private func presentFilePicker(allowedExtensions: [String], result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      guard let presenter = self.topViewController() else {
        result(nil)
        return
      }

      var contentTypes: [UTType] = []
      for ext in allowedExtensions {
        let clean = ext.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        if clean == "json" {
          contentTypes.append(.json)
        } else if clean == "csv" {
          contentTypes.append(.commaSeparatedText)
        } else if clean == "qif" || clean == "txt" {
          contentTypes.append(.plainText)
        } else if let ut = UTType(filenameExtension: clean) {
          contentTypes.append(ut)
        }
      }
      if contentTypes.isEmpty {
        contentTypes = [.item]
      }

      let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: false)
      picker.allowsMultipleSelection = false

      let delegate = DocumentPickerDelegate(
        onPick: { [weak self] url in
          guard let self = self else {
            result(nil)
            return
          }
          self.stopAccessingCurrentSecurityResource()
          let accessed = url.startAccessingSecurityScopedResource()
          if accessed {
            self.activeSecurityScopedURL = url
          }
          let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
          result([
            "path": url.path,
            "bookmark": bookmark?.base64EncodedString() ?? ""
          ])
        },
        onCancel: {
          result(nil)
        }
      )

      picker.delegate = delegate
      objc_setAssociatedObject(picker, &AssociatedKeys.delegateKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

      if let popover = picker.popoverPresentationController {
        popover.sourceView = presenter.view
        popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
        popover.permittedArrowDirections = []
      }

      presenter.present(picker, animated: true, completion: nil)
    }
  }

  private func presentFileSaver(defaultName: String, result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      guard let presenter = self.topViewController() else {
        result(nil)
        return
      }

      // Prepara arquivo temporário vazio para o UIDocumentPicker exportar e criar
      let tempDir = FileManager.default.temporaryDirectory
      let tempURL = tempDir.appendingPathComponent(defaultName)

      // Garante que o arquivo temporário existe com estrutura base inicial caso seja json
      if !FileManager.default.fileExists(atPath: tempURL.path) {
        let emptyPayload = "{\n  \"v\": 7,\n  \"accounts\": [],\n  \"cats\": [],\n  \"txs\": [],\n  \"recs\": [],\n  \"budgets\": {}\n}\n"
        try? emptyPayload.data(using: .utf8)?.write(to: tempURL)
      }

      let picker = UIDocumentPickerViewController(forExporting: [tempURL], asCopy: true)

      let delegate = DocumentPickerDelegate(
        onPick: { [weak self] url in
          guard let self = self else {
            result(nil)
            return
          }
          self.stopAccessingCurrentSecurityResource()
          let accessed = url.startAccessingSecurityScopedResource()
          if accessed {
            self.activeSecurityScopedURL = url
          }
          let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
          result([
            "path": url.path,
            "bookmark": bookmark?.base64EncodedString() ?? ""
          ])
        },
        onCancel: {
          result(nil)
        }
      )

      picker.delegate = delegate
      objc_setAssociatedObject(picker, &AssociatedKeys.delegateKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

      if let popover = picker.popoverPresentationController {
        popover.sourceView = presenter.view
        popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
        popover.permittedArrowDirections = []
      }

      presenter.present(picker, animated: true, completion: nil)
    }
  }
}

private struct AssociatedKeys {
  static var delegateKey = "DocumentPickerDelegateKey"
}

private class DocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
  private let onPick: (URL) -> Void
  private let onCancel: () -> Void

  init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
    self.onPick = onPick
    self.onCancel = onCancel
    super.init()
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first else {
      onCancel()
      return
    }
    onPick(url)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    onCancel()
  }
}
