import importlib.util
import tempfile
import unittest
from pathlib import Path

MODULE = Path(__file__).resolve().parents[1] / "configure_macos_window.py"
spec = importlib.util.spec_from_file_location("configure_macos_window", MODULE)
config = importlib.util.module_from_spec(spec)
spec.loader.exec_module(config)


class ConfigureMacosWindowTest(unittest.TestCase):
    def test_patches_generated_window_idempotently(self):
        swift = """import Cocoa
import FlutterMacOS
class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    RegisterGeneratedPlugins(registry: flutterViewController)
    super.awakeFromNib()
  }
}
"""
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "MainFlutterWindow.swift"
            target.write_text(swift)
            self.assertTrue(config.install(target))
            result = target.read_text()
            self.assertEqual(result.count(config.MARKER), 1)
            self.assertIn("visibleFrame", result)
            self.assertIn("setFrame(visibleFrame, display: true)", result)
            self.assertNotIn("setFrameUsingName", result)
            self.assertFalse(config.install(target))
            self.assertEqual(result, target.read_text())

    def test_fails_when_template_changes(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "MainFlutterWindow.swift"
            target.write_text("import Cocoa\nclass WrongTemplate {}\n")
            with self.assertRaisesRegex(RuntimeError, "Unexpected Flutter"):
                config.install(target)


if __name__ == "__main__":
    unittest.main()