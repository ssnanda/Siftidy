#!/usr/bin/env python3
"""Open Siftidy in the full usable desktop area without macOS fullscreen.

Install into the generated macOS Flutter runner during every build. Never cover
macOS's menu bar or Dock, and preserve ordinary resizability after opening.
"""
from pathlib import Path

MARKER = "// Siftidy usable desktop frame v0.2"
FRAME_CODE = '''
    // Siftidy usable desktop frame v0.2
    // Cover the usable desktop on launch, without entering fullscreen mode.
    // This deliberately overrides an older saved undersized window frame.
    if let visibleFrame = (screen ?? NSScreen.main)?.visibleFrame {
      setFrame(visibleFrame, display: true)
    }
'''


def install(window_path: Path) -> bool:
    content = window_path.read_text()
    if MARKER in content:
        return False
    needle = "    super.awakeFromNib()"
    if content.count(needle) != 1 or "import Cocoa" not in content:
        raise RuntimeError("Unexpected Flutter macOS window template")
    content = content.replace(needle, needle + "\n" + FRAME_CODE, 1)
    window_path.write_text(content)
    return True


def main() -> None:
    window = Path("macos/Runner/MainFlutterWindow.swift")
    if install(window):
        print("Siftidy opens across the macOS visible desktop (not fullscreen)")
    else:
        print("Siftidy window sizing already installed")


if __name__ == "__main__":
    main()