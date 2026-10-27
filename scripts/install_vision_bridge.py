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
      guard ["hasPeople", "screenshotReason", "propertyEvidence",
                 "propertyScene"].contains(call.method),
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
          } else if call.method == "propertyScene" {
            // One Vision request batch per image. Explicitly distinguish
            // humans/events, residential rooms, and neutral interior frames.
            let humans = VNDetectHumanRectanglesRequest()
            let faces = VNDetectFaceRectanglesRequest()
            let classify = VNClassifyImageRequest()
            try handler.perform([humans, faces, classify])
            if !(humans.results ?? []).isEmpty || !(faces.results ?? []).isEmpty {
              DispatchQueue.main.async { result(2) } // People: hard boundary
            } else {
              let observations = classify.results ?? []
              let prominent = observations.prefix(15)
              func matches(_ terms: [String], minimum: Float) -> Bool {
                return prominent.contains { observation in
                  let tag = observation.identifier.lowercased()
                  return observation.confidence >= minimum &&
                    terms.contains(where: { tag == $0 ||
                         tag.contains(" " + $0) || tag.hasPrefix($0 + " ") })
                }
              }
              let events = ["party", "concert", "wedding", "banquet",
                            "festival", "celebration", "crowd",
                            "conference", "reception", "auditorium"]
              let residential = ["closet", "bedroom", "bathroom",
                                 "living room", "dining room", "kitchen",
                                 "staircase", "hallway", "corridor",
                                 "shower", "bathtub", "toilet",
                                 "garage", "garage door", "driveway",
                                 "porch", "deck", "patio", "yard",
                                 "house exterior", "building exterior",
                                 "facade", "front door", "entryway",
                                 "residential", "house interior",
                                 "house", "apartment", "real estate",
                                 "home interior", "interior design"]
              let genericInterior = ["interior", "room", "wood floor",
                                     "flooring", "door", "doorway",
                                     "stairs", "building interior",
                                     "architecture", "wall", "ceiling"]
              let code: Int
              if matches(events, minimum: 0.13) {
                code = 0 // Event/venue, never a property tour
              } else if matches(residential, minimum: 0.12) {
                code = 1 // Positive residential visual evidence
              } else if matches(genericInterior, minimum: 0.18) {
                code = 3 // Neutral indoor scene; needs positive neighbors
              } else {
                code = 0
              }
              DispatchQueue.main.async { result(code) }
            }
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
            let text = words.map { $0.0 }.joined(separator: " ")
            func containsAny(_ terms: [String]) -> Bool {
              return terms.contains(where: { text.contains($0) })
            }
            let alarm = containsAny(["alarm", "snooze", "wake up", "bedtime"])
            let email = containsAny(["inbox", "reply all", "forwarded message",
                                     "sent from my", "subject:", "from:"])
            let message = containsAny(["imessage", "text message", "messages",
                                       "delivered", "type a message", "whatsapp",
                                       "messenger"])
            let clock = words.contains { candidate in
              return candidate.1 > 0.72 &&
                     candidate.0.range(of: #"^\d{1,2}:\d{2}(\s?[ap]m)?$"#,
                                       options: .regularExpression) != nil
            }
            let weekday = words.contains { candidate in
              return candidate.1 > 0.60 &&
                ["monday", "tuesday", "wednesday", "thursday",
                      "friday", "saturday", "sunday"].contains { day in
                candidate.0.contains(day)
              }
            }
            // A status-bar time and a date word also occur in Messages,
            // Calendar, email and many web pages. Only suggest a lock screen
            // when OCR sees the sparse text layout typical of one.
            let recognizedWordCount = text.split(whereSeparator: { $0.isWhitespace }).count
            let sparseLockScreen = clock && weekday && recognizedWordCount <= 16
            let reason: String?
            if alarm {
              reason = "Possible alarm capture"
            } else if email {
              reason = "Possible email capture"
            } else if message {
              reason = "Possible message capture"
            } else if sparseLockScreen {
              reason = "Possible lock-screen capture"
            } else {
              reason = nil
            }
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
