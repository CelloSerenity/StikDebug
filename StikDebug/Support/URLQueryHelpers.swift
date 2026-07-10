//
//  URLQueryHelpers.swift
//  StikDebug
//

import Foundation

enum URLQueryHelpers {
    static func queryValue(_ names: [String], in components: URLComponents?) -> String? {
        guard let items = components?.queryItems else { return nil }
        for name in names {
            if let value = items.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.value?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    static func coordinate(from url: URL) -> (latitude: Double, longitude: Double)? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []

        func value(_ names: [String]) -> String? {
            for name in names {
                if let match = items.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.value {
                    return match
                }
            }
            return nil
        }

        if let latText = value(["lat", "latitude"]),
           let lonText = value(["lon", "lng", "long", "longitude"]),
           let lat = Double(latText.trimmingCharacters(in: .whitespacesAndNewlines)),
           let lon = Double(lonText.trimmingCharacters(in: .whitespacesAndNewlines)),
           coordinateIsValid(latitude: lat, longitude: lon) {
            return (lat, lon)
        }

        let text = value(["coordinate", "coordinates", "coords", "q", "ll"]) ?? components?.path ?? ""
        let values = numbers(in: text)
        guard values.count >= 2, coordinateIsValid(latitude: values[0], longitude: values[1]) else {
            return nil
        }
        return (values[0], values[1])
    }

    static func coordinateIsValid(latitude: Double, longitude: Double) -> Bool {
        (-90.0...90.0).contains(latitude) && (-180.0...180.0).contains(longitude)
    }

    static func numbers(in text: String) -> [Double] {
        guard let regex = try? NSRegularExpression(pattern: #"[-+]?(?:\d+(?:\.\d*)?|\.\d+)"#) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else { return nil }
            return Double(text[matchRange])
        }
    }

    static func base64URLToBase64(_ base64url: String) -> String {
        var base64 = base64url
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = 4 - (base64.count % 4)
        if pad < 4 {
            base64 += String(repeating: "=", count: pad)
        }
        return base64
    }
}
