import Cocoa
import FlutterMacOS
#if canImport(FoundationModels)
import FoundationModels
#endif
#if canImport(AppIntents)
import AppIntents
#endif

class MainFlutterWindow: NSWindow {
  static weak var sharedChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    self.isOpaque = true
    self.backgroundColor = NSColor.windowBackgroundColor
    self.minSize = NSSize(width: 900, height: 600)

    RegisterGeneratedPlugins(registry: flutterViewController)
    setupAppleIntelligenceChannel(flutterViewController: flutterViewController)

    super.awakeFromNib()

    let autosaveName = "OpenMoneyMainWindow"
    self.setFrameAutosaveName(autosaveName)

    if !self.setFrameUsingName(autosaveName) {
      if let screen = self.screen ?? NSScreen.main {
        self.setFrame(screen.visibleFrame, display: true)
      }
    }
  }

  private func setupAppleIntelligenceChannel(flutterViewController: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "openmoney/apple_intelligence",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    MainFlutterWindow.sharedChannel = channel

    channel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "checkAvailability":
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
          result(SystemLanguageModel.default.isAvailable)
          return
        }
        #endif
        result(true)

      case "generateResponse":
        let args = call.arguments as? [String: Any]
        let systemPrompt = (args?["systemPrompt"] as? String) ?? ""
        let userPrompt = (args?["userPrompt"] as? String) ?? ""
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), SystemLanguageModel.default.isAvailable {
          Task {
            do {
              let session = LanguageModelSession(instructions: systemPrompt)
              let response = try await session.respond(to: userPrompt)
              result(response.content)
            } catch {
              result(nil)
            }
          }
          return
        }
        #endif
        result(nil)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

#if canImport(AppIntents)
@available(macOS 14.0, *)
struct OpenMoneyAskAssistantIntent: AppIntent {
  static var title: LocalizedStringResource = "Perguntar ou Lançar no OpenMoney"
  static var description = IntentDescription("Envia um comando de lançamento ou pergunta financeira para a Assistente IA do OpenMoney.")
  static var openAppWhenRun: Bool = true

  @Parameter(title: "Comando ou Lançamento", requestValueDialog: "O que você deseja lançar ou perguntar ao OpenMoney?")
  var commandText: String

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    MainFlutterWindow.sharedChannel?.invokeMethod("onSiriCommand", arguments: ["prompt": commandText])
    return .result(dialog: "Abrindo a Assistente do OpenMoney com seu comando.")
  }
}
#endif
