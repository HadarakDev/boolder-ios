//
//  ProblemSaver.swift
//  Boolder
//
//  Serialises a ProblemEntry to a GeoJSON Feature on disk under
//  iCloud/local-sandbox Documents/map-maker/problems/<timestamp>.json so
//  the Python pipeline can ingest it later. Mirrors BoulderDrawSaver.
//

#if DEVELOPMENT

import Foundation
import CoreLocation

enum ProblemSaver {
    struct ProblemJson: Codable {
        var type: String                   // "Feature" — GeoJSON-friendly
        var geometry: GeometryJson
        var properties: PropertiesJson
    }

    struct GeometryJson: Codable {
        var type: String                   // "Point"
        var coordinates: [Double]          // [lon, lat]
    }

    struct PropertiesJson: Codable {
        var createdAt: String
        var name: String
        var grade: String
        var comments: String
    }

    @discardableResult
    static func save(entry: ProblemEntry, store: MapMakerStore = MapMakerStore()) -> URL? {
        guard let coord = entry.pendingCoord else { return nil }

        let isOverwrite = entry.editingFilename != nil
        let filename = entry.editingFilename ?? (store.timestamp() + ".json")

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        let record = ProblemJson(
            type: "Feature",
            geometry: GeometryJson(
                type: "Point",
                coordinates: [coord.longitude, coord.latitude]
            ),
            properties: PropertiesJson(
                createdAt: isoFormatter.string(from: Date()),
                name: entry.name,
                grade: entry.grade,
                comments: entry.comments
            )
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(record)
            store.save(data: data, directory: "problems", filename: filename, overwrite: isOverwrite)
            return URL(fileURLWithPath: filename)
        } catch {
            print("ProblemSaver save error:", error)
            return nil
        }
    }

    @discardableResult
    static func delete(filename: String) -> Bool {
        let url = directoryURL().appendingPathComponent(filename)
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch CocoaError.fileNoSuchFile {
            return true
        } catch {
            print("ProblemSaver delete error:", error)
            return false
        }
    }

    static func load(filename: String) -> ProblemJson? {
        let url = directoryURL().appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url),
              let record = try? JSONDecoder().decode(ProblemJson.self, from: data) else {
            return nil
        }
        return record
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
