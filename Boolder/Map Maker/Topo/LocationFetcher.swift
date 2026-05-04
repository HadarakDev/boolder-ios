//
//  LocationFetcher.swift
//  Boolder
//
//  Originally created by Nicolas Mondollot on 13/12/2020.
//  Ported to TopoSud (DEVELOPMENT-only) from the legacy-map-maker branch.
//  Migrated from Combine/ObservableObject to @Observable.
//

#if DEVELOPMENT

import CoreLocation
import SwiftUI

@Observable
final class LocationFetcher: NSObject, CLLocationManagerDelegate {
    @ObservationIgnored let manager = CLLocationManager()

    var location: CLLocation?
    var heading: CLHeading?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else { return }

        // Keep the most accurate fix
        if let oldLocation = location {
            if newLocation.horizontalAccuracy <= oldLocation.horizontalAccuracy {
                location = newLocation
            }
        } else {
            location = newLocation
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading
    }
}

#endif
