//
//  BoulderLibrary.swift
//  Boolder
//
//  Reads all saved boulder polygons from the Map Maker store directory and
//  returns their rings. The Mapbox controller uses this to populate a
//  "saved boulders" layer that persists what the user has authored across
//  draw sessions (DEVELOPMENT-only).
//

#if DEVELOPMENT

import Foundation
import CoreLocation

enum BoulderLibrary {
    /// Each element is a closed ring: an array of coordinates whose first
    /// and last entries are equal (GeoJSON Polygon convention).
    static func loadAllRings() -> [[CLLocationCoordinate2D]] {
        let dir = directoryURL()
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        let jsons = urls.filter { $0.pathExtension == "json" }

        var rings: [[CLLocationCoordinate2D]] = []
        let decoder = JSONDecoder()
        for url in jsons {
            guard let data = try? Data(contentsOf: url),
                  let record = try? decoder.decode(BoulderDrawSaver.BoulderJson.self, from: data),
                  let outer = record.geometry.coordinates.first else {
                continue
            }
            // Each pair is [lon, lat]; keep the closed ring as Mapbox emits it.
            let ring = outer.compactMap { pair -> CLLocationCoordinate2D? in
                guard pair.count >= 2 else { return nil }
                return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
            }
            if ring.count >= 4 { // 3 unique vertices + closing repeat
                rings.append(ring)
            }
        }
        return rings
    }

    private static func directoryURL() -> URL {
        let baseURL: URL = {
            if let iCloud = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
                return iCloud.appendingPathComponent("Documents")
            }
            return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }()
        return baseURL.appendingPathComponent("map-maker").appendingPathComponent("boulders")
    }
}

#endif
