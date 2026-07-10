//
//  CoordinateImportParser.swift
//  StikDebug
//

import Foundation
import MapKit
import CoreLocation
import UniformTypeIdentifiers

enum CoordinateImportError: LocalizedError {
    case emptyFile
    case noCoordinates

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "The selected file is empty."
        case .noCoordinates:
            return "No valid coordinates were found. Use GPX, GeoJSON, JSON, CSV, or plain text with latitude and longitude values."
        }
    }
}

enum CoordinateImportParser {
    static let supportedContentTypes: [UTType] = [
        .plainText,
        .commaSeparatedText,
        .json,
        .xml,
        UTType(filenameExtension: "gpx", conformingTo: .xml) ?? .xml,
        UTType(filenameExtension: "kml", conformingTo: .xml) ?? .xml,
        UTType(filenameExtension: "geojson", conformingTo: .json) ?? .json
    ]

    private enum CoordinateOrder {
        case latitudeLongitude
        case longitudeLatitude
    }

    static func parse(url: URL) throws -> [CLLocationCoordinate2D] {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { throw CoordinateImportError.emptyFile }

        let fileExtension = url.pathExtension.lowercased()
        if fileExtension == "json" || fileExtension == "geojson" {
            if let coordinates = try? parseJSONCoordinates(from: data),
               !coordinates.isEmpty {
                return coordinates
            }
        }

        if fileExtension == "gpx" || fileExtension == "kml" || fileExtension == "xml" {
            let coordinates = parseXMLCoordinates(from: data)
            if !coordinates.isEmpty {
                return coordinates
            }
        }

        if let text = decodedText(from: data) {
            let coordinates = parseInline(text)
            if !coordinates.isEmpty {
                return coordinates
            }
        }

        if let coordinates = try? parseJSONCoordinates(from: data),
           !coordinates.isEmpty {
            return coordinates
        }

        let coordinates = parseXMLCoordinates(from: data)
        if !coordinates.isEmpty {
            return coordinates
        }

        throw CoordinateImportError.noCoordinates
    }

    static func parseInline(_ text: String) -> [CLLocationCoordinate2D] {
        sanitized(parseTextCoordinates(from: text))
    }

    private static func decodedText(from data: Data) -> String? {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .ascii)
    }

    private static func sanitized(_ coordinates: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        var result: [CLLocationCoordinate2D] = []
        for coordinate in coordinates where CLLocationCoordinate2DIsValid(coordinate) {
            if result.last.map(CoordinateSnapshot.init) == CoordinateSnapshot(coordinate) {
                continue
            }
            result.append(coordinate)
        }
        return result
    }

    private static func coordinate(
        first: Double,
        second: Double,
        order: CoordinateOrder
    ) -> CLLocationCoordinate2D? {
        let preferred: CLLocationCoordinate2D
        let fallback: CLLocationCoordinate2D

        switch order {
        case .latitudeLongitude:
            preferred = CLLocationCoordinate2D(latitude: first, longitude: second)
            fallback = CLLocationCoordinate2D(latitude: second, longitude: first)
        case .longitudeLatitude:
            preferred = CLLocationCoordinate2D(latitude: second, longitude: first)
            fallback = CLLocationCoordinate2D(latitude: first, longitude: second)
        }

        if CLLocationCoordinate2DIsValid(preferred) {
            return preferred
        }
        if CLLocationCoordinate2DIsValid(fallback) {
            return fallback
        }
        return nil
    }

    private static func parseJSONCoordinates(from data: Data) throws -> [CLLocationCoordinate2D] {
        let object = try JSONSerialization.jsonObject(with: data)
        return sanitized(coordinates(fromJSONObject: object, order: .latitudeLongitude))
    }

    private static func coordinates(
        fromJSONObject object: Any,
        order: CoordinateOrder
    ) -> [CLLocationCoordinate2D] {
        if let dictionary = object as? [String: Any] {
            if let latitude = numberValue(forAnyKey: ["latitude", "lat"], in: dictionary),
               let longitude = numberValue(forAnyKey: ["longitude", "lon", "lng"], in: dictionary),
               let coordinate = coordinate(first: latitude, second: longitude, order: .latitudeLongitude) {
                return [coordinate]
            }

            if let geometry = dictionary["geometry"] {
                return coordinates(fromJSONObject: geometry, order: order)
            }

            if let type = dictionary["type"] as? String {
                let loweredType = type.lowercased()
                if loweredType == "featurecollection",
                   let features = dictionary["features"] as? [Any] {
                    return features.flatMap { coordinates(fromJSONObject: $0, order: .longitudeLatitude) }
                }
                if loweredType == "geometrycollection",
                   let geometries = dictionary["geometries"] as? [Any] {
                    return geometries.flatMap { coordinates(fromJSONObject: $0, order: .longitudeLatitude) }
                }
                if let coordinateObject = dictionary["coordinates"] {
                    return coordinates(fromJSONObject: coordinateObject, order: .longitudeLatitude)
                }
            }

            return dictionary.values.flatMap { coordinates(fromJSONObject: $0, order: order) }
        }

        if let array = object as? [Any] {
            if array.count >= 2,
               let first = numericValue(array[0]),
               let second = numericValue(array[1]),
               let coordinate = coordinate(first: first, second: second, order: order) {
                return [coordinate]
            }

            return array.flatMap { coordinates(fromJSONObject: $0, order: order) }
        }

        return []
    }

    private static func numericValue(_ value: Any) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func numberValue(forAnyKey keys: [String], in dictionary: [String: Any]) -> Double? {
        let keyedValues = Dictionary(uniqueKeysWithValues: dictionary.map { ($0.key.lowercased(), $0.value) })
        for key in keys {
            if let value = keyedValues[key],
               let number = numericValue(value) {
                return number
            }
        }
        return nil
    }

    private static func parseXMLCoordinates(from data: Data) -> [CLLocationCoordinate2D] {
        let collector = XMLCoordinateCollector()
        let parser = XMLParser(data: data)
        parser.delegate = collector
        guard parser.parse() else { return [] }
        return sanitized(collector.coordinates)
    }

    private final class XMLCoordinateCollector: NSObject, XMLParserDelegate {
        var coordinates: [CLLocationCoordinate2D] = []
        private var isCollectingKMLCoordinates = false
        private var kmlCoordinateBuffer = ""

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            let name = elementName.lowercased()
            if ["wpt", "trkpt", "rtept"].contains(name),
               let latitude = Double(attributeDict["lat"] ?? ""),
               let longitude = Double(attributeDict["lon"] ?? ""),
               let coordinate = CoordinateImportParser.coordinate(
                    first: latitude,
                    second: longitude,
                    order: .latitudeLongitude
               ) {
                coordinates.append(coordinate)
            } else if name == "coordinates" {
                isCollectingKMLCoordinates = true
                kmlCoordinateBuffer = ""
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if isCollectingKMLCoordinates {
                kmlCoordinateBuffer += string
            }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            guard elementName.lowercased() == "coordinates" else { return }
            coordinates.append(contentsOf: CoordinateImportParser.parseKMLCoordinateText(kmlCoordinateBuffer))
            isCollectingKMLCoordinates = false
            kmlCoordinateBuffer = ""
        }
    }

    private static func parseKMLCoordinateText(_ text: String) -> [CLLocationCoordinate2D] {
        text
            .split(whereSeparator: { $0.isWhitespace })
            .compactMap { token -> CLLocationCoordinate2D? in
                let values = token
                    .split(separator: ",")
                    .compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                guard values.count >= 2 else { return nil }
                return coordinate(first: values[0], second: values[1], order: .longitudeLatitude)
            }
    }

    private static func parseTextCoordinates(from text: String) -> [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        var headerIndices: (latitude: Int, longitude: Int)?

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let fields = splitFields(trimmed)
            if headerIndices == nil,
               let detectedHeader = detectHeader(in: fields) {
                headerIndices = detectedHeader
                continue
            }

            if let headerIndices,
               fields.indices.contains(headerIndices.latitude),
               fields.indices.contains(headerIndices.longitude),
               let latitude = numbers(in: fields[headerIndices.latitude]).first,
               let longitude = numbers(in: fields[headerIndices.longitude]).first,
               let coordinate = coordinate(first: latitude, second: longitude, order: .latitudeLongitude) {
                coordinates.append(coordinate)
                continue
            }

            let values = numbers(in: trimmed)
            if values.count >= 2,
               let coordinate = coordinate(first: values[0], second: values[1], order: .latitudeLongitude) {
                coordinates.append(coordinate)
            }
        }

        return coordinates
    }

    private static func splitFields(_ line: String) -> [String] {
        line
            .split { character in
                character == "," ||
                character == ";" ||
                character == "\t"
            }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func detectHeader(in fields: [String]) -> (latitude: Int, longitude: Int)? {
        let lowered = fields.map { $0.lowercased() }
        guard let latitude = lowered.firstIndex(where: { $0 == "lat" || $0 == "latitude" }),
              let longitude = lowered.firstIndex(where: { $0 == "lon" || $0 == "lng" || $0 == "long" || $0 == "longitude" }) else {
            return nil
        }
        return (latitude, longitude)
    }

    private static func numbers(in text: String) -> [Double] {
        let pattern = #"[-+]?(?:\d+(?:\.\d*)?|\.\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else { return nil }
            return Double(text[matchRange])
        }
    }
}

