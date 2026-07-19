import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Custom chrome: real traffic lights stay functional, but the native
    // title bar becomes transparent/textless so Flutter can draw its own
    // title strip underneath (matches the Crisp Utility desktop design).
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)
    self.minSize = NSSize(width: 1180, height: 760)

    super.awakeFromNib()
  }
}
