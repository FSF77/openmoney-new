import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    self.isOpaque = true
    self.backgroundColor = NSColor.windowBackgroundColor
    self.minSize = NSSize(width: 900, height: 600)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    let autosaveName = "OpenMoneyMainWindow"
    self.setFrameAutosaveName(autosaveName)

    // Se houver posição e tamanho previamente salvos, restaura.
    // Se não houver informação salva (primeira execução), abre maximizado ocupando o visibleFrame da tela.
    if !self.setFrameUsingName(autosaveName) {
      if let screen = self.screen ?? NSScreen.main {
        self.setFrame(screen.visibleFrame, display: true)
      }
    }
  }
}
