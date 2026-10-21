#!/usr/bin/env python3
"""Set a roomy first-launch macOS window without overriding user resizing.

Called after Flutter generates macos/Runner and after the Vision bridge is
installed. The native window saves its frame between launches.
"""
from pathlib import Path

MARKER = "// Siftidy initial window geometry v0.2"
FRAME_CODE = '''
    // Siftidy initial window geometry v0.2
    // Restore a user's previously resized window; use this size only the first time.
    let siftidyFrameName = "SiftidyMainWindow"
    if !setFrameUsingName(siftidyFrameName),
       let visibleFrame = (screen ?? NSScreen.main)?.visibleFrame {
      let initialWidth: CGFloat = min(1450, visibleFrame.width * 0.94)
      let initialHeight: CGFloat = min(950, visibleFrame.height * 0.92)
      let initialFrame = NSRect(
        x: visibleFrame.midX - initialWidth / 2,
        y: visibleFrame.midY - initialHeight / 2,
        width: initialWidth,
        height: initialHeight)
      setFrame(initialFrame, display: true)
    }
    setFrameAutosaveName(siftidyFrameName)
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
        print("Set adaptive 1450x950 first-launch window with saved sizing")
    else:
        print("Siftidy window sizing already installed")


if __name__ == "__main__":
    main()