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

struct SavedBoulder {
    var filename: String
    var ring: [CLLocationCoordinate2D]   // closed ring (first == last)
}

enum BoulderLibrary {
    /// Lists every saved boulder polygon along with the filename it was read
    /// from (so the map layer can stamp the filename on each feature for
    /// hit-tested editing).
    static func loadAll() -> [SavedBoulder] {
        let dir = directoryURL()
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        let jsons = urls.filter { $0.pathExtension == "json" }

        var results: [SavedBoulder] = []
        let decoder = JSONDecoder()
        for url in jsons {
            guard let data = try? Data(contentsOf: url),
                  let record = try? decoder.decode(BoulderDrawSaver.BoulderJson.self, from: data),
                  let outer = record.geometry.coordinates.first else {
                continue
            }
            let ring = outer.compactMap { pair -> CLLocationCoordinate2D? in
                guard pair.count >= 2 else { return nil }
                return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
            }
            if ring.count >= 4 { // 3 unique vertices + closing repeat
                results.append(SavedBoulder(filename: url.lastPathComponent, ring: ring))
            }
        }
        return results
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
