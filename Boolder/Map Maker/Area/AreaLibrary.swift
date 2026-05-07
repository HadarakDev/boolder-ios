//
//  AreaLibrary.swift
//  Boolder
//
//  Reads all saved area polygons from disk for the persistent map layer.
//  DEVELOPMENT-only.
//

#if DEVELOPMENT

import Foundation
import CoreLocation

struct SavedArea {
    var filename: String
    var name: String
    var ring: [CLLocationCoordinate2D]
    var vertices: [CLLocationCoordinate2D]
    var southWest: CLLocationCoordinate2D
    var northEast: CLLocationCoordinate2D

    /// Approximate centroid of the bounding box — useful for labeling the
    /// area on the map.
    var centroid: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: (southWest.latitude + northEast.latitude) / 2,
            longitude: (southWest.longitude + northEast.longitude) / 2
        )
    }
}

enum AreaLibrary {
    static func loadAll() -> [SavedArea] {
        let dir = directoryURL()
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        let jsons = urls.filter { $0.pathExtension == "json" }

        var results: [SavedArea] = []
        let decoder = JSONDecoder()
        for url in jsons {
            guard let data = try? Data(contentsOf: url),
                  let record = try? decoder.decode(AreaDrawSaver.AreaJson.self, from: data),
                  let outer = record.geometry.coordinates.first else {
                continue
            }
            let ring = outer.compactMap { pair -> CLLocationCoordinate2D? in
                guard pair.count >= 2 else { return nil }
                return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
            }
            let vertices = record.properties.vertices.map { v in
                CLLocationCoordinate2D(latitude: v.latitude, longitude: v.longitude)
            }
            if ring.count >= 4 {
                results.append(SavedArea(
                    filename: url.lastPathComponent,
                    name: record.properties.name,
                    ring: ring,
                    vertices: vertices,
                    southWest: CLLocationCoordinate2D(
                        latitude: record.properties.southWestLat,
                        longitude: record.properties.southWestLon
                    ),
                    northEast: CLLocationCoordinate2D(
                        latitude: record.properties.northEastLat,
                        longitude: record.properties.northEastLon
                    )
                ))
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
        return baseURL.appendingPathComponent("map-maker").appendingPathComponent("areas")
    }
}

#endif
