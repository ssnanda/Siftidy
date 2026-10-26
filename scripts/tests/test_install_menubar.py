import importlib.util
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "install_menubar", ROOT / "install_menubar.py"
)
installer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(installer)


class InstallMenuBarTests(unittest.TestCase):
    def test_install_reproducible_and_idempotent(self):
        with tempfile.TemporaryDirectory() as temporary:
            window = Path(temporary) / "MainFlutterWindow.swift"
            window.write_text(
                "import Cocoa\nimport FlutterMacOS\n"
                "class MainFlutterWindow: NSWindow {\n"
                "  override func awakeFromNib() {\n"
                "    let flutterViewController = FlutterViewController()\n"
                "    RegisterGeneratedPlugins(registry: flutterViewController)\n"
                "  }\n}\n"
            )
            self.assertTrue(installer.install(window))
            output = window.read_text()
            self.assertIn(installer.MARKER, output)
            self.assertIn('siftidy/menu_bar', output)
            self.assertIn('windowShouldClose', output)
            self.assertIn('Quit Completely', output)
            self.assertIn('ramMb', output)
            self.assertIn('idleSeconds', output)
            self.assertIn('turboSecondsRemaining', output)
            self.assertIn('Running', output)
            self.assertIn('stateSymbol', output)
            self.assertIn('data["fraction"] as? Double', output)
            self.assertIn('complete ? 100 : min(99', output)
            self.assertFalse(installer.install(window))
            self.assertEqual(window.read_text(), output)

    def test_dock_activation_restores_hidden_window(self):
        source = installer.SWIFT
        self.assertIn("func showWindowIfHidden()", source)
        self.assertIn("NSApplication.didBecomeActiveNotification", source)
        self.assertNotIn("NSApp.setActivationPolicy(.accessory)", source)
        self.assertIn('if command == "open" {', source)

    def test_upgrades_previous_generated_window(self):
        old = installer.SWIFT.replace(
            "  private var activationObserver: NSObjectProtocol?\\n", ""
        )
        old = old.replace(
            '''    setupMenu()
    // Dock/app switcher activation must reopen a window hidden to the tray.
    // A weak capture avoids keeping the singleton alive through the observer.
    if activationObserver == nil {
      activationObserver = NotificationCenter.default.addObserver(
        forName: NSApplication.didBecomeActiveNotification,
        object: NSApp, queue: .main
      ) { [weak self] _ in
        self?.showWindowIfHidden()
      }
    }
    update([:])''',
            '    setupMenu()\\n    update([:])',
        )
        old = old.replace(
            '''  func showWindowIfHidden() {
    guard let window = appWindow else { return }
    if window.isVisible && !window.isMiniaturized { return }
    if window.isMiniaturized { window.deminiaturize(nil) }
    NSApp.setActivationPolicy(.regular)
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func hideToMenuBar() {
    appWindow?.orderOut(nil)
    channel?.invokeMethod("action", arguments: "windowHidden")
    // Keep the Dock icon so clicking it can restore the app normally.
  }''',
            '''  func hideToMenuBar() {
    appWindow?.orderOut(nil)
    channel?.invokeMethod("action", arguments: "windowHidden")
    NSApp.setActivationPolicy(.accessory)
  }''',
        )
        old = old.replace(
            '''    if command == "open" {
      showWindowIfHidden()
      return
    }''',
            '''    if command == "open" {
      NSApp.setActivationPolicy(.regular)
      appWindow?.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }''',
        )
        upgraded = installer.upgrade_existing_menu(old)
        self.assertIn("func showWindowIfHidden()", upgraded)
        self.assertIn("NSApplication.didBecomeActiveNotification", upgraded)
        self.assertNotIn("NSApp.setActivationPolicy(.accessory)", upgraded)
        self.assertEqual(upgraded, installer.upgrade_existing_menu(upgraded))

    def test_quit_offers_graceful_pause_with_hard_20_second_deadline(self):
        source = installer.SWIFT
        self.assertIn('alert.addButton(withTitle: "Pause & Quit")', source)
        self.assertIn('alert.addButton(withTitle: "Quit Now")', source)
        self.assertIn('alert.addButton(withTitle: "Cancel")', source)
        self.assertIn('arguments: "prepareQuit"', source)
        self.assertIn('deadline: .now() + 20.0', source)
        self.assertIn('Darwin._exit(0)', source)
        self.assertIn('quitCompletely()', source)
        self.assertIn('let restoring = data["restoring"]', source)
        self.assertIn('Restoring checkpoint', source)

    def test_terminate_only_through_explicit_quit(self):
        with tempfile.TemporaryDirectory() as temporary:
            delegate = Path(temporary) / "AppDelegate.swift"
            delegate.write_text(
                "override func applicationShouldTerminateAfterLastWindowClosed("
                "_ sender: NSApplication) -> Bool {\n"
                "    return true\n  }\n"
            )
            self.assertTrue(installer.keep_running_on_last_window_close(delegate))
            self.assertIn('return false', delegate.read_text())
            self.assertFalse(installer.keep_running_on_last_window_close(delegate))

    def test_command_q_hides_and_explicit_quit_is_allowed(self):
        with tempfile.TemporaryDirectory() as temporary:
            delegate = Path(temporary) / "AppDelegate.swift"
            delegate.write_text(
                "import Cocoa\nclass AppDelegate: FlutterAppDelegate {\n"
                "  override func applicationShouldTerminateAfterLastWindowClosed("
                "_ sender: NSApplication) -> Bool {\n    return true\n  }\n}\n"
            )
            self.assertTrue(installer.keep_running_on_last_window_close(delegate))
            self.assertTrue(installer.install_quit_policy(delegate))
            content = delegate.read_text()
            self.assertIn("override func applicationShouldTerminate(", content)
            self.assertIn("tray.hideToMenuBar()", content)
            self.assertIn("return .terminateCancel", content)
            self.assertIn("tray.allowsTermination", content)
            self.assertIn("return .terminateNow", content)
            self.assertFalse(installer.install_quit_policy(delegate))
            self.assertEqual(content, delegate.read_text())
            self.assertIn("func quitCompletely()", installer.SWIFT)
            self.assertIn("quittingCompletely = true", installer.SWIFT)
            self.assertIn("quitCompletely()", installer.SWIFT)
            self.assertNotIn('if command == "quit" {\n      NSApp.terminate(nil)',
                             installer.SWIFT)


if __name__ == "__main__":
    unittest.main()
