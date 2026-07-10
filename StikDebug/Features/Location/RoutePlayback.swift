//
//  RoutePlayback.swift
//  StikDebug
//

import Foundation
import MapKit
import CoreLocation

func buildPlaybackSamples(
    from displayCoordinates: [CLLocationCoordinate2D],
    speedWays: [OpenStreetMapWay],
    fallbackSpeedMetersPerSecond: CLLocationSpeed
) -> [RoutePlaybackSample] {
    guard let firstCoordinate = displayCoordinates.first else { return [] }

    var samples = [RoutePlaybackSample(coordinate: firstCoordinate, delayFromPrevious: 0)]

    for (start, end) in zip(displayCoordinates, displayCoordinates.dropFirst()) {
        let segmentDistance = CLLocation(latitude: start.latitude, longitude: start.longitude)
            .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
        guard segmentDistance > 0 else { continue }

        let speedLimit = nearestSpeedLimit(forSegmentFrom: start, to: end, using: speedWays) ?? fallbackSpeedMetersPerSecond
        let clampedSpeed = max(speedLimit, RouteSimulationDefaults.minimumSpeedMetersPerSecond)
        let segmentTravelTime = segmentDistance / clampedSpeed
        let segmentStepCount = max(1, Int(ceil(segmentTravelTime / RouteSimulationDefaults.playbackTickInterval)))
        let stepDelay = segmentTravelTime / Double(segmentStepCount)

        for index in 1...segmentStepCount {
            let coordinate = interpolateCoordinate(
                from: start,
                to: end,
                fraction: Double(index) / Double(segmentStepCount)
            )
            if samples.last.map({ CoordinateSnapshot($0.coordinate) }) != CoordinateSnapshot(coordinate) {
                samples.append(RoutePlaybackSample(coordinate: coordinate, delayFromPrevious: stepDelay))
            }
        }
    }

    return samples
}

func prefetchRoutePlaybackSamples(
    displayCoordinates: [CLLocationCoordinate2D],
    fallbackSpeedMetersPerSecond: CLLocationSpeed
) async -> [RoutePlaybackSample] {
    let speedWays = (try? await fetchOpenStreetMapWays(for: displayCoordinates)) ?? []
    return buildPlaybackSamples(
        from: displayCoordinates,
        speedWays: speedWays,
        fallbackSpeedMetersPerSecond: fallbackSpeedMetersPerSecond
    )
}

