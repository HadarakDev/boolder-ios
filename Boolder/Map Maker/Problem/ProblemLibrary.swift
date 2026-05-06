//
//  ProblemLibrary.swift
//  Boolder
//
//  Reads all saved problem JSONs from disk for the persistent map layer
//  (DEVELOPMENT-only).
//

#if DEVELOPMENT

import Foundation
import CoreLocation

struct SavedProblem {
    var filename: String
    var coordinate: CLLocationCoordinate2D
    var name: String
    var grade: String
}

enum ProblemLibrary {
    static func loadAll() -> [SavedProblem] {
        let dir = directoryURL()
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        let jsons = urls.filter { $0.pathExtension == "json" }

        var results: [SavedProblem] = []
        let decoder = JSONDecoder()
        for url in jsons {
            guard let data = try? Data(contentsOf: url),
                  let record = try? decoder.decode(ProblemSaver.ProblemJson.self, from: data),
                  record.geometry.coordinates.count >= 2 else {
                continue
            }
            let lon = record.geometry.coordinates[0]
            let lat = record.geometry.coordinates[1]
            results.append(SavedProblem(
                filename: url.lastPathComponent,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                name: record.properties.name,
                grade: record.properties.grade
            ))
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
        return baseURL.appendingPathComponent("map-maker").appendingPathComponent("problems")
    }
}

#endif
