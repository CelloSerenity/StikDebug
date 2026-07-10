//
//  OpenStreetMapSpeedLimits.swift
//  StikDebug
//

import Foundation
import MapKit
import CoreLocation

func parseSpeedLimitMetersPerSecond(from rawValue: String) -> CLLocationSpeed? {
    let normalized = rawValue
        .lowercased()
        .split(separator: ";")
        .first?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    guard !normalized.isEmpty else { return nil }
    guard normalized != "none",
          normalized != "signals",
          normalized != "implicit",
          normalized != "walk" else {
        return nil
    }

    let scanner = Scanner(string: normalized)
    guard let numericValue = scanner.scanDouble() else { return nil }

    if normalized.contains("mph") {
        return numericValue * 0.44704
    }
    if normalized.contains("knot") {
        return numericValue * 0.514444
    }

    return numericValue / 3.6
}

func speedLimitMetersPerSecond(from tags: [String: String]) -> CLLocationSpeed? {
    if let maxspeed = tags["maxspeed"],
       let parsed = parseSpeedLimitMetersPerSecond(from: maxspeed) {
        return parsed
    }

    let directionalValues = [
        tags["maxspeed:forward"],
        tags["maxspeed:backward"]
    ]
        .compactMap { $0 }
        .compactMap(parseSpeedLimitMetersPerSecond(from:))

    guard !directionalValues.isEmpty else { return nil }
    return directionalValues.min()
}

func overpassQuery(for coordinates: [CLLocationCoordinate2D]) -> String? {
    guard let first = coordinates.first else { return nil }

    var minLatitude = first.latitude
    var maxLatitude = first.latitude
    var minLongitude = first.longitude
    var maxLongitude = first.longitude

    for coordinate in coordinates.dropFirst() {
        minLatitude = min(minLatitude, coordinate.latitude)
        maxLatitude = max(maxLatitude, coordinate.latitude)
        minLongitude = min(minLongitude, coordinate.longitude)
        maxLongitude = max(maxLongitude, coordinate.longitude)
    }

    let padding = OpenStreetMapSpeedLimitService.boundingBoxPaddingDegrees
    let south = minLatitude - padding
    let west = minLongitude - padding
    let north = maxLatitude + padding
    let east = maxLongitude + padding

    let bbox = String(format: "%.6f,%.6f,%.6f,%.6f", south, west, north, east)

    return """
    [out:json][timeout:20];
    (
      way(\(bbox))[highway][maxspeed];
      way(\(bbox))[highway]["maxspeed:forward"];
      way(\(bbox))[highway]["maxspeed:backward"];
    );
    out tags geom;
    """
}

func fetchOpenStreetMapWays(for coordinates: [CLLocationCoordinate2D]) async throws -> [OpenStreetMapWay] {
    guard let query = overpassQuery(for: coordinates) else { return [] }

    var components = URLComponents(url: OpenStreetMapSpeedLimitService.endpoint, resolvingAgainstBaseURL: false)
    components?.queryItems = [URLQueryItem(name: "data", value: query)]
    guard let url = components?.url else { return [] }

    let (data, response) = try await URLSession.shared.data(from: url)

    if let httpResponse = response as? HTTPURLResponse,
       !(200...299).contains(httpResponse.statusCode) {
        throw NSError(
            domain: "OpenStreetMapSpeedLimits",
            code: httpResponse.statusCode,
            userInfo: [NSLocalizedDescriptionKey: "Overpass returned HTTP \(httpResponse.statusCode)."]
        )
    }

    let decoded = try JSONDecoder().decode(OverpassResponse.self, from: data)
    return decoded.elements.compactMap { element in
        guard let tags = element.tags,
              let speedLimit = speedLimitMetersPerSecond(from: tags),
              let geometry = element.geometry?.map({ CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }),
              geometry.count > 1 else {
            return nil
        }

        return OpenStreetMapWay(
            geometry: geometry,
            speedLimitMetersPerSecond: speedLimit
        )
    }
}

func nearestSpeedLimit(
    forSegmentFrom start: CLLocationCoordinate2D,
    to end: CLLocationCoordinate2D,
    using ways: [OpenStreetMapWay]
) -> CLLocationSpeed? {
    let midpoint = MKMapPoint(midpointCoordinate(from: start, to: end))
    var bestMatch: (speed: CLLocationSpeed, distance: CLLocationDistance)?

    for way in ways {
        for (wayStart, wayEnd) in zip(way.geometry, way.geometry.dropFirst()) {
            let candidateDistance = distanceFromPoint(
                midpoint,
                toSegmentFrom: MKMapPoint(wayStart),
                to: MKMapPoint(wayEnd)
            )

            if bestMatch == nil || candidateDistance < bestMatch!.distance {
                bestMatch = (way.speedLimitMetersPerSecond, candidateDistance)
            }
        }
    }

    guard let bestMatch,
          bestMatch.distance <= OpenStreetMapSpeedLimitService.nearestWayThreshold else {
        return nil
    }

    return bestMatch.speed
}

