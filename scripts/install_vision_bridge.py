#!/usr/bin/env python3
"""Install a local Apple Vision method channel in generated macOS runner.

Flutter recreates macos/Runner on bootstrap; modifying the generated source in
this script keeps the bridge reproducible across release and local builds.
"""
from pathlib import Path

window = Path('macos/Runner/MainFlutterWindow.swift')
source = window.read_text()
marker = '// Siftidy Apple Vision bridge v0.2'
if marker in source:
    print('Vision bridge already installed')
    raise SystemExit(0)
needle = 'RegisterGeneratedPlugins(registry: flutterViewController)'
if needle not in source or 'import FlutterMacOS' not in source:
    raise SystemExit('Unexpected Flutter macOS window template; cannot install Vision bridge')
source = source.replace('import FlutterMacOS', 'import FlutterMacOS\nimport Vision', 1)
bridge = r'''

    // Siftidy Apple Vision bridge v0.2
    let siftidyVision = FlutterMethodChannel(
      name: "siftidy/vision",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    siftidyVision.setMethodCallHandler { call, result in
      guard call.method == "hasPeople",
            let bytes = call.arguments as? FlutterStandardTypedData else {
        result(FlutterMethodNotImplemented)
        return
      }
      // Vision runs off the main thread; reply on Flutter's platform thread.
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let people = VNDetectHumanRectanglesRequest()
          let faces = VNDetectFaceRectanglesRequest()
          let handler = VNImageRequestHandler(data: bytes.data, options: [:])
          try handler.perform([people, faces])
          let detected = !(people.results ?? []).isEmpty ||
                         !(faces.results ?? []).isEmpty
          DispatchQueue.main.async { result(detected) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "VISION_FAILED",
                                message: error.localizedDescription,
                                details: nil))
          }
        }
      }
    }
'''
source = source.replace(needle, needle + bridge, 1)
window.write_text(source)
print('Installed local Apple Vision people-detection bridge')
