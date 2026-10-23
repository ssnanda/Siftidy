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
            self.assertFalse(installer.install(window))
            self.assertEqual(window.read_text(), output)

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


if __name__ == "__main__":
    unittest.main()
