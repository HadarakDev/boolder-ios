//
//  LocationAverager.swift
//  Boolder
//
//  Streams GPS while the boulder-draw overlay is on screen, exposes the live
//  fix for the on-screen accuracy badge, and on demand collects N samples
//  over a fixed window and returns their inverse-variance weighted mean
//  (so the user can do a "stand still and average" placement).
//

#if DEVELOPMENT

import CoreLocation
import Foundation

@Observable
final class LocationAverager: NSObject, CLLocationManagerDelegate {
    @ObservationIgnored let manager = CLLocationManager()

    /// Latest streaming fix. Used by the overlay to show "GPS ±X m".
    var liveLocation: CLLocation?
    /// True while collectAverage(over:completion:) is collecting samples.
    var isCollecting: Bool = false
    /// Sample count for the in-progress collection (drives the "averaging…"
    /// display and is reported to the caller via the completion).
    private var samples: [CLLocation] = []
    private var collectionCompletion: ((CLLocation?, Int) -> Void)?
    private var collectionTimer: Timer?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func startStreaming() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func stopStreaming() {
        manager.stopUpdatingLocation()
        cancelCollection()
    }

    /// Collect `over` seconds worth of samples and call `completion` with the
    /// weighted mean and the sample count. If no samples land in the window,
    /// completion fires with `(nil, 0)`.
    func collectAverage(
        over seconds: TimeInterval,
        completion: @escaping (CLLocation?, Int) -> Void
    ) {
        guard !isCollecting else { return }
        samples = []
        isCollecting = true
        collectionCompletion = completion

        // Seed with the latest streaming fix so a 0-update window still has 1
        if let l = liveLocation { samples.append(l) }

        collectionTimer?.invalidate()
        collectionTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.finishCollecting()
        }
    }

    func cancelCollection() {
        collectionTimer?.invalidate()
        collectionTimer = nil
        if isCollecting {
            isCollecting = false
            let cb = collectionCompletion
            collectionCompletion = nil
            cb?(nil, 0)
        }
    }

    private func finishCollecting() {
        let collected = samples
        let result = computeWeightedMean(collected)
        isCollecting = false
        let cb = collectionCompletion
        collectionCompletion = nil
        cb?(result, collected.count)
    }

    private func computeWeightedMean(_ samples: [CLLocation]) -> CLLocation? {
        guard !samples.isEmpty else { return nil }

        // Inverse-variance weighting: more accurate fixes contribute more.
        var totalWeight = 0.0
        var lat = 0.0
        var lon = 0.0
        var alt = 0.0
        for s in samples where s.horizontalAccuracy > 0 {
            let w = 1.0 / (s.horizontalAccuracy * s.horizontalAccuracy)
            totalWeight += w
            lat += s.coordinate.latitude * w
            lon += s.coordinate.longitude * w
            alt += s.altitude * w
        }
        guard totalWeight > 0 else {
            // All samples had unknown accuracy — fall back to arithmetic mean.
            let n = Double(samples.count)
            let mLat = samples.map(\.coordinate.latitude).reduce(0, +) / n
            let mLon = samples.map(\.coordinate.longitude).reduce(0, +) / n
            let mAlt = samples.map(\.altitude).reduce(0, +) / n
            return CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: mLat, longitude: mLon),
                altitude: mAlt,
                horizontalAccuracy: -1,
                verticalAccuracy: -1,
                timestamp: Date()
            )
        }
        let avgCoord = CLLocationCoordinate2D(
            latitude: lat / totalWeight,
            longitude: lon / totalWeight
        )
        // Standard error of the weighted mean ≈ 1 / sqrt(totalWeight).
        let avgAccuracy = 1.0 / sqrt(totalWeight)
        return CLLocation(
            coordinate: avgCoord,
            altitude: alt / totalWeight,
            horizontalAccuracy: avgAccuracy,
            verticalAccuracy: -1,
            timestamp: Date()
        )
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else { return }
        liveLocation = newLocation
        if isCollecting {
            samples.append(newLocation)
        }
    }
}

#endif
