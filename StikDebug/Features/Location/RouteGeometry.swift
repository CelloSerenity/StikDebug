//
//  RouteGeometry.swift
//  StikDebug
//

import MapKit
import CoreLocation

struct CoordinateSnapshot: Equatable {
    let latitude: Double
    let longitude: Double

    init(_ coordinate: CLLocationCoordinate2D) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct RouteSearchSelection {
    let title: String
    let coordinate: CLLocationCoordinate2D
}

enum RouteSearchField {
    case start
    case end
}

struct RouteSimulationPlan {
    let displayCoordinates: [CLLocationCoordinate2D]
    let distance: CLLocationDistance
    let expectedTravelTime: TimeInterval
}

enum RouteSimulationDefaults {
    static let pathSamplingDistance: CLLocationDistance = 10
    static let playbackTickInterval: TimeInterval = 0.5
    static let minimumSpeedMetersPerSecond: CLLocationSpeed = 1.0
    static let importedRouteFallbackSpeedMetersPerSecond: CLLocationSpeed = 13.4
}

struct RoutePlaybackSample {
    let coordinate: CLLocationCoordinate2D
    let delayFromPrevious: TimeInterval
}

struct OpenStreetMapWay {
    let geometry: [CLLocationCoordinate2D]
    let speedLimitMetersPerSecond: CLLocationSpeed
}

enum OpenStreetMapSpeedLimitService {
    static let endpoint = URL(string: "https://overpass-api.de/api/interpreter")!
    static let copyrightURL = URL(string: "https://www.openstreetmap.org/copyright")!
    static let boundingBoxPaddingDegrees = 0.0015
    static let nearestWayThreshold: CLLocationDistance = 40
}

struct OverpassResponse: Decodable {
    let elements: [Element]

    struct Element: Decodable {
        let tags: [String: String]?
        let geometry: [Coordinate]?
    }

    struct Coordinate: Decodable {
        let lat: Double
        let lon: Double
    }
}

extension MKPolyline {
    var coordinateArray: [CLLocationCoordinate2D] {
        var coordinates = [CLLocationCoordinate2D](
            repeating: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            count: pointCount
        )
        getCoordinates(&coordinates, range: NSRange(location: 0, length: pointCount))
        return coordinates
    }
}

func interpolateCoordinate(
    from start: CLLocationCoordinate2D,
    to end: CLLocationCoordinate2D,
    fraction: Double
) -> CLLocationCoordinate2D {
    CLLocationCoordinate2D(
        latitude: start.latitude + ((end.latitude - start.latitude) * fraction),
        longitude: start.longitude + ((end.longitude - start.longitude) * fraction)
    )
}

func sampledRouteCoordinates(
    from coordinates: [CLLocationCoordinate2D],
    targetDistance: CLLocationDistance
) -> [CLLocationCoordinate2D] {
    guard coordinates.count > 1 else { return coordinates }

    var sampled = [coordinates[0]]
    for (start, end) in zip(coordinates, coordinates.dropFirst()) {
        let distance = CLLocation(latitude: start.latitude, longitude: start.longitude)
            .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
        let segmentCount = max(1, Int(ceil(distance / targetDistance)))
        for index in 1...segmentCount {
            let point = interpolateCoordinate(
                from: start,
                to: end,
                fraction: Double(index) / Double(segmentCount)
            )
            if sampled.last.map(CoordinateSnapshot.init) != CoordinateSnapshot(point) {
                sampled.append(point)
            }
        }
    }

    return sampled
}

func midpointCoordinate(
    from start: CLLocationCoordinate2D,
    to end: CLLocationCoordinate2D
) -> CLLocationCoordinate2D {
    interpolateCoordinate(from: start, to: end, fraction: 0.5)
}

func distanceAlong(_ coordinates: [CLLocationCoordinate2D]) -> CLLocationDistance {
    zip(coordinates, coordinates.dropFirst()).reduce(0) { total, pair in
        total + CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
            .distance(from: CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude))
    }
}

func distanceFromPoint(
    _ point: MKMapPoint,
    toSegmentFrom start: MKMapPoint,
    to end: MKMapPoint
) -> CLLocationDistance {
    let dx = end.x - start.x
    let dy = end.y - start.y

    guard dx != 0 || dy != 0 else {
        return point.distance(to: start)
    }

    let projection = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / ((dx * dx) + (dy * dy))))
    let projectedPoint = MKMapPoint(
        x: start.x + (dx * projection),
        y: start.y + (dy * projection)
    )
    return point.distance(to: projectedPoint)
}

