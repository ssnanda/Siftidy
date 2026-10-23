#!/usr/bin/env python3
"""Install the native Siftidy macOS menu bar / process metrics bridge.

Flutter regenerates MainFlutterWindow.swift at every bootstrap. Keep all
native functionality reproducible without committing generated Xcode files.
"""
from pathlib import Path

MARKER = "// Siftidy menu bar and scan performance bridge v0.2"
BOOT = """
    SiftidyMenuBar.shared.install(window: self,
      messenger: flutterViewController.engine.binaryMessenger)
"""

SWIFT = r'''

// Siftidy menu bar and scan performance bridge v0.2
// Closing the window hides it; only Quit Completely terminates Siftidy.
final class SiftidyMenuBar: NSObject, NSWindowDelegate {
  static let shared = SiftidyMenuBar()

  private weak var appWindow: NSWindow?
  private var channel: FlutterMethodChannel?
  private var statusItem: NSStatusItem?
  private var menu: NSMenu?
  private var detailsItem: NSMenuItem?
  private var progressItem: NSMenuItem?
  private var resourcesItem: NSMenuItem?
  private var durationItem: NSMenuItem?
  private var scanItem: NSMenuItem?
  private var pauseItem: NSMenuItem?
  private var stopItem: NSMenuItem?
  private var discardItem: NSMenuItem?
  private var idleItem: NSMenuItem?
  private var modeItems: [String: NSMenuItem] = [:]
  private var previousCpuSeconds: Double = 0
  private var previousUptime: Double = 0
  private var cpu: Double = 0
  private var quittingCompletely = false
  var isInstalled: Bool { statusItem != nil }
  var allowsTermination: Bool { quittingCompletely }

  func install(window: NSWindow, messenger: FlutterBinaryMessenger) {
    appWindow = window
    window.delegate = self
    channel = FlutterMethodChannel(name: "siftidy/menu_bar",
                                   binaryMessenger: messenger)
    channel?.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(FlutterMethodNotImplemented); return }
      switch call.method {
      case "metrics":
        result(self.metrics())
      case "status":
        guard let fields = call.arguments as? [String: Any] else {
          result(FlutterError(code: "BAD_STATUS",
                              message: "Expected status dictionary", details: nil))
          return
        }
        self.update(fields)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    setupMenu()
    update([:])
  }

  func hideToMenuBar() {
    appWindow?.orderOut(nil)
    channel?.invokeMethod("action", arguments: "windowHidden")
    NSApp.setActivationPolicy(.accessory)
  }

  func quitCompletely() {
    quittingCompletely = true
    NSApp.terminate(nil)
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    hideToMenuBar()
    return false
  }

  private func addItem(_ title: String, action: String, to menu: NSMenu) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: #selector(activate(_:)), keyEquivalent: "")
    item.target = self
    item.representedObject = action
    menu.addItem(item)
    return item
  }

  private func setupMenu() {
    if statusItem != nil { return }
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem = item
    item.button?.title = "▧ —"
    item.button?.toolTip = "Siftidy background scan"
    let root = NSMenu(title: "Siftidy")
    menu = root
    item.menu = root

    detailsItem = NSMenuItem(title: "Scan is idle", action: nil, keyEquivalent: "")
    detailsItem?.isEnabled = false
    if let detailsItem = detailsItem { root.addItem(detailsItem) }
    progressItem = NSMenuItem(title: "0 scanned", action: nil, keyEquivalent: "")
    resourcesItem = NSMenuItem(title: "CPU — · RAM —", action: nil, keyEquivalent: "")
    durationItem = NSMenuItem(title: "Duration — · ETA —", action: nil, keyEquivalent: "")
    for entry in [progressItem, resourcesItem, durationItem] {
      entry?.isEnabled = false
      if let entry = entry { root.addItem(entry) }
    }
    root.addItem(NSMenuItem.separator())
    addItem("Open Siftidy", action: "open", to: root)
    addItem("Scan history & storage", action: "history", to: root)
    scanItem = addItem("Start scan", action: "scan", to: root)
    pauseItem = addItem("Pause scan", action: "pause", to: root)
    stopItem = addItem("Stop scan", action: "stop", to: root)
    discardItem = addItem("Discard scan results", action: "discard", to: root)
    root.addItem(NSMenuItem.separator())

    let performance = NSMenuItem(title: "Scanning speed", action: nil, keyEquivalent: "")
    let choices = NSMenu(title: "Scanning speed")
    for (label, value) in [("Minimal · ~1–3% CPU", "minimal"),
                           ("Eco · ~5–10% CPU", "eco"),
                           ("Balanced · ~20–40% CPU", "balanced")] {
      modeItems[value] = addItem(label, action: "mode:" + value, to: choices)
    }
    choices.addItem(NSMenuItem.separator())
    addItem("Turbo now · 60 minutes", action: "mode:turbo:60", to: choices)
    let turbo = NSMenuItem(title: "Turbo for…", action: nil, keyEquivalent: "")
    let durations = NSMenu(title: "Turbo duration")
    for minutes in [30, 60, 120] {
      addItem("\(minutes) minutes or until you return",
              action: "mode:turbo:\(minutes)", to: durations)
    }
    choices.setSubmenu(durations, for: turbo)
    choices.addItem(turbo)
    performance.submenu = choices
    root.addItem(performance)
    idleItem = addItem("Auto Turbo after 10 min idle (AC only)",
                       action: "toggleIdleTurbo", to: root)
    root.addItem(NSMenuItem.separator())
    addItem("Quit Completely", action: "quit", to: root)
  }

  @objc private func activate(_ sender: NSMenuItem) {
    guard let command = sender.representedObject as? String else { return }
    if command == "open" {
      NSApp.setActivationPolicy(.regular)
      appWindow?.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    if command == "quit" {
      quitCompletely()
      return
    }
    channel?.invokeMethod("action", arguments: command)
  }

  private func update(_ data: [String: Any]) {
    let visited = data["visited"] as? Int ?? 0
    let total = data["total"] as? Int ?? 0
    let analyzed = data["analyzed"] as? Int ?? 0
    let running = data["running"] as? Bool ?? false
    let paused = data["paused"] as? Bool ?? false
    let complete = data["complete"] as? Bool ?? false
    let mode = data["activeMode"] as? String ?? "eco"
    let baseMode = data["baseMode"] as? String ?? "eco"
    let isIdleEnabled = data["idleTurbo"] as? Bool ?? false
    let percent = total > 0 ? min(100, Int(Double(visited) * 100 / Double(total))) : 0
    let pending = max(0, total - visited)
    let state = running ? (paused ? "Paused" : "Running") :
                  (complete ? "Complete" : "Idle")
    let stateSymbol = running ? (paused ? "⏸" : "▶") : (complete ? "✓" : "–")
    let turboSeconds = data["turboSecondsRemaining"] as? Int
    let speedLabel = mode == "turbo" && turboSeconds != nil
      ? "Turbo · \(max(1, (turboSeconds! + 59) / 60))m left"
      : mode.capitalized
    let cpuValue = data["cpu"] as? Double ?? cpu
    let ramValue = data["ramMb"] as? Double ?? 0
    let eta = data["etaSeconds"] as? Int
    let elapsedMs = data["elapsedMs"] as? Int ?? 0
    let rate = data["ratePerMinute"] as? Double ?? 0
    let durationMinutes = elapsedMs / 60000
    let etaDescription = eta == nil ? "Calculating" :
                         (eta! >= 60 ? "\(eta! / 60) min" : "\(eta!) sec")
    statusItem?.button?.title = running ? "\(stateSymbol) \(percent)%" :
      (complete ? "▧ ✓" : "▧ —")
    statusItem?.button?.toolTip =
      "Siftidy · \(state)\n" +
      "\(visited) scanned / \(pending) pending (\(total) total)\n" +
      "\(analyzed) analyzed · \(percent)% complete\n" +
      String(format: "CPU %.1f%% · RAM %.0f MB\n", cpuValue, ramValue) +
      "Speed: \(speedLabel) · ETA: \(etaDescription)"
    detailsItem?.title = "\(stateSymbol) \(state) · \(percent)% · \(speedLabel)"
    progressItem?.title = "\(visited) scanned · \(pending) pending · \(analyzed) analyzed"
    resourcesItem?.title = String(format: "CPU %.1f%% · RAM %.0f MB", cpuValue, ramValue)
    durationItem?.title = String(format: "Elapsed %dm · ETA %@ · %.0f/min",
                                 durationMinutes, etaDescription, rate)
    scanItem?.isEnabled = !running
    pauseItem?.isEnabled = running
    pauseItem?.title = paused ? "Resume scan" : "Pause scan"
    stopItem?.isEnabled = running
    discardItem?.isEnabled = running || complete || analyzed > 0
    idleItem?.state = isIdleEnabled ? .on : .off
    for (key, item) in modeItems {
      item.state = key == baseMode ? .on : .off
    }
  }

  private func metrics() -> [String: Any] {
    var usage = rusage()
    let ok = getrusage(0, &usage)
    let uptime = ProcessInfo.processInfo.systemUptime
    if ok == 0 {
      let seconds = Double(usage.ru_utime.tv_sec) +
        Double(usage.ru_utime.tv_usec) / 1000000.0 +
        Double(usage.ru_stime.tv_sec) +
        Double(usage.ru_stime.tv_usec) / 1000000.0
      if previousUptime > 0 && uptime > previousUptime {
        cpu = max(0, (seconds - previousCpuSeconds) * 100 /
                  (uptime - previousUptime))
      }
      previousCpuSeconds = seconds
      previousUptime = uptime
    }

    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size /
                                       MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO),
                  $0, &count)
      }
    }
    let ram = result == KERN_SUCCESS ?
      Double(info.resident_size) / 1048576.0 : 0

    // CGEventSource provides seconds since the last physical input. No key
    // content is ever read or stored.
    let idle = CGEventSource.secondsSinceLastEventType(
      .combinedSessionState, eventType: .null)
    let thermal = ProcessInfo.processInfo.thermalState
    return [
      "cpu": cpu,
      "ramMb": ram,
      "idleSeconds": idle.isFinite ? max(0, idle) : 0,
      "thermalLimited": thermal == .serious || thermal == .critical,
      "onAcPower": isOnAcPower(),
    ]
  }

  private func isOnAcPower() -> Bool {
    // Native IOKit power-source query avoids polling a shell command.
    guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let sourceType = IOPSGetProvidingPowerSourceType(blob)?
            .takeUnretainedValue() else {
      return false // Unknown: don't automatically activate Turbo.
    }
    return (sourceType as String) == kIOPMACPowerKey
  }
}
'''

def install(path: Path) -> bool:
    source = path.read_text()
    if MARKER in source:
        return False
    needle = "RegisterGeneratedPlugins(registry: flutterViewController)"
    if source.count(needle) != 1 or "import Cocoa" not in source:
        raise RuntimeError("Unsupported generated Flutter window template")
    source = source.replace("import Cocoa", "import Cocoa\nimport IOKit.ps", 1)
    source = source.replace(needle, needle + "\n" + BOOT, 1)
    path.write_text(source + SWIFT)
    return True


QUIT_MARKER = "// Siftidy Cmd-Q hides window; explicit Quit Completely exits"
QUIT_POLICY = """
  // Siftidy Cmd-Q hides window; explicit Quit Completely exits.
  override func applicationShouldTerminate(_ sender: NSApplication)
      -> NSApplication.TerminateReply {
    let tray = SiftidyMenuBar.shared
    if tray.allowsTermination || !tray.isInstalled {
      return .terminateNow
    }
    tray.hideToMenuBar()
    return .terminateCancel
  }
"""


def install_quit_policy(path: Path) -> bool:
    content = path.read_text()
    if QUIT_MARKER in content:
        return False
    needle = "override func applicationShouldTerminateAfterLastWindowClosed"
    if content.count(needle) != 1:
        raise RuntimeError("Generated AppDelegate template has changed")
    content = content.replace(needle, QUIT_POLICY + "\n  " + needle, 1)
    path.write_text(content)
    return True


def keep_running_on_last_window_close(path: Path) -> bool:
    content = path.read_text()
    marker = "applicationShouldTerminateAfterLastWindowClosed"
    if marker not in content:
        raise RuntimeError("Generated AppDelegate lacks close handling")
    if "return false" in content:
        return False
    if "return true" not in content:
        raise RuntimeError("Unexpected Flutter app termination policy")
    content = content.replace("return true", "return false", 1)
    path.write_text(content)
    return True


if __name__ == "__main__":
    if install(Path("macos/Runner/MainFlutterWindow.swift")):
        print("Installed Siftidy menu-bar scanning and CPU/RAM/idle bridge")
    else:
        print("Siftidy menu-bar scanning already installed")
    delegate = Path("macos/Runner/AppDelegate.swift")
    if keep_running_on_last_window_close(delegate):
        print("Siftidy now remains active when the last window is closed")
    if install_quit_policy(delegate):
        print("Cmd-Q hides Siftidy; only Quit Completely stops its background scan")
