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
source = source.replace('import FlutterMacOS', 'import FlutterMacOS\nimport Vision\nimport CoreLocation', 1)
bridge = r'''

    // Siftidy Apple Vision bridge v0.2
    let siftidyVision = FlutterMethodChannel(
      name: "siftidy/vision",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    siftidyVision.setMethodCallHandler { call, result in
      guard ["hasPeople", "screenshotReason", "propertyEvidence"].contains(call.method),
            let bytes = call.arguments as? FlutterStandardTypedData else {
        result(FlutterMethodNotImplemented)
        return
      }
      DispatchQueue.global(qos: .utility).async {
        do {
          let handler = VNImageRequestHandler(data: bytes.data, options: [:])
          if call.method == "hasPeople" {
            let people = VNDetectHumanRectanglesRequest()
            let faces = VNDetectFaceRectanglesRequest()
            try handler.perform([people, faces])
            let detected = !(people.results ?? []).isEmpty ||
                           !(faces.results ?? []).isEmpty
            DispatchQueue.main.async { result(detected) }
          } else if call.method == "screenshotReason" {
            let recognize = VNRecognizeTextRequest()
            recognize.recognitionLevel = .fast
            recognize.usesLanguageCorrection = false
            try handler.perform([recognize])
            let observations = recognize.results ?? []
            let words = observations.compactMap { observation -> (String, Float)? in
              guard let candidate = observation.topCandidates(1).first else {
                return nil
              }
              return (candidate.string.lowercased(), Float(observation.boundingBox.midY))
            }
            let clock = words.contains { candidate in
              return candidate.1 > 0.42 &&
                     candidate.0.range(of: #"^\d{1,2}:\d{2}$"#,
                                       options: .regularExpression) != nil
            }
            let weekday = words.contains { candidate in
              return ["monday", "tuesday", "wednesday", "thursday",
                      "friday", "saturday", "sunday"].contains { day in
                candidate.0.contains(day)
              }
            }
            // A clock alone is not sufficient: a normal app may show time.
            let reason: String? = (clock && weekday)
                ? "Possible lock-screen capture" : nil
            DispatchQueue.main.async { result(reason) }
          } else {
            let classify = VNClassifyImageRequest()
            try handler.perform([classify])
            let terms = ["living room", "bedroom", "bathroom", "kitchen",
                         "dining room", "house", "residence", "apartment",
                         "home interior", "interior design", "stairway",
                         "hallway", "real estate", "building exterior"]
            let matches = (classify.results ?? []).prefix(15).contains { item in
              let label = item.identifier.lowercased()
              return item.confidence >= 0.10 &&
                     terms.contains(where: { label == $0 || label.contains(" " + $0) })
            }
            DispatchQueue.main.async { result(matches) }
          }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "VISION_FAILED",
                                message: error.localizedDescription,
                                details: nil))
          }
        }
      }
    }

    // Explicit-only: CoreLocation may consult Apple's geocoding service.
    // Never call this channel silently while scanning photos.
    let siftidyGeocode = FlutterMethodChannel(
      name: "siftidy/geocoding",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    siftidyGeocode.setMethodCallHandler { call, result in
      guard call.method == "reverseAddress",
            let args = call.arguments as? [String: Double],
            let latitude = args["latitude"],
            let longitude = args["longitude"],
            abs(latitude) <= 90, abs(longitude) <= 180 else {
        result(FlutterMethodNotImplemented)
        return
      }
      let geocoder = CLGeocoder()
      geocoder.reverseGeocodeLocation(
        CLLocation(latitude: latitude, longitude: longitude)) {
          placemarks, error in
        if let error = error {
          result(FlutterError(code: "GEOCODE_FAILED",
                              message: error.localizedDescription,
                              details: nil))
          return
        }
        guard let place = placemarks?.first else {
          result(nil)
          return
        }
        let street = [place.subThoroughfare, place.thoroughfare]
          .compactMap { $0 }.joined(separator: " ")
        let parts = [street.isEmpty ? nil : street, place.locality,
                     place.administrativeArea, place.postalCode]
                     .compactMap { $0 }
        result(parts.isEmpty ? nil : parts.joined(separator: ", "))
      }
    }
'''
source = source.replace(needle, needle + bridge, 1)
window.write_text(source)
print('Installed local Apple Vision people-detection bridge')
