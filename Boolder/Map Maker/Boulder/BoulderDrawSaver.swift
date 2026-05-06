//
//  BoulderDrawSaver.swift
//  Boolder
//
//  Serialises a finished BoulderDrawEntry to a GeoJSON Feature on disk under
//  iCloud Documents/map-maker/boulders/<timestamp>.json so the Python
//  pipeline can ingest it later. Mirrors NewTopoView's save() flow.
//

#if DEVELOPMENT

import Foundation
import CoreLocation

enum BoulderDrawSaver {
    /// One vertex inside the saved JSON. Lon/lat to match GeoJSON convention,
    /// plus per-point accuracy and provenance for downstream tooling.
    struct VertexJson: Codable {
        var longitude: Double
        var latitude: Double
        var horizontalAccuracy: Double?
        var sampleCount: Int
        var source: String
    }

    struct BoulderJson: Codable {
        var type: String                  // "Feature" — GeoJSON-friendly
        var geometry: GeometryJson
        var properties: PropertiesJson
    }

    struct GeometryJson: Codable {
        var type: String                  // "Polygon"
        /// GeoJSON polygon coordinates: an array of linear rings, each ring
        /// is an array of [lon, lat] pairs and is closed (first == last).
        var coordinates: [[[Double]]]
    }

    struct PropertiesJson: Codable {
        var createdAt: String
        var comments: String
        var vertices: [VertexJson]
        var averageHorizontalAccuracy: Double?
    }

    @discardableResult
    static func save(entry: BoulderDrawEntry, store: MapMakerStore = MapMakerStore()) -> URL? {
        guard entry.vertices.count >= 3 else { return nil }

        // If we're editing an existing record, reuse its filename so Save
        // overwrites; otherwise mint a fresh timestamp filename.
        let isOverwrite = entry.editingFilename != nil
        let baseFilename = entry.editingFilename ?? (store.timestamp() + ".json")

        let ring: [[Double]] = entry.vertices.map { v in
            [v.longitude, v.latitude]
        }
        let closedRing = ring + [ring[0]]

        let measured = entry.vertices.compactMap { $0.horizontalAccuracy }.filter { $0 >= 0 }
        let avgAcc: Double? = measured.isEmpty ? nil : measured.reduce(0, +) / Double(measured.count)

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        let record = BoulderJson(
            type: "Feature",
            geometry: GeometryJson(type: "Polygon", coordinates: [closedRing]),
            properties: PropertiesJson(
                createdAt: isoFormatter.string(from: Date()),
                comments: entry.comments,
                vertices: entry.vertices.map { v in
                    VertexJson(
                        longitude: v.longitude,
                        latitude: v.latitude,
                        horizontalAccuracy: v.horizontalAccuracy,
                        sampleCount: v.sampleCount,
                        source: v.source.rawValue
                    )
                },
                averageHorizontalAccuracy: avgAcc
            )
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(record)
            let filename = baseFilename
            store.save(data: data, directory: "boulders", filename: filename, overwrite: isOverwrite)
            return URL(fileURLWithPath: filename) // informational; MapMakerStore handles real path
        } catch {
            print("BoulderDrawSaver save error:", error)
            return nil
        }
    }

    /// Deletes the JSON for a saved boulder. Returns true if the file was
    /// removed (or was already gone), false on a real I/O error.
    @discardableResult
    static func delete(filename: String) -> Bool {
        let url = directoryURL().appendingPathComponent(filename)
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch CocoaError.fileNoSuchFile {
            return true
        } catch {
            print("BoulderDrawSaver delete error:", error)
            return false
        }
    }

    /// Returns vertices stored in the JSON at `<map-maker>/boulders/<filename>`
    /// in the user's GeoJSON shape. Used to load a saved boulder back into the
    /// editor.
    static func loadVertices(filename: String) -> [BoulderVertex]? {
        let url = directoryURL().appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url),
              let record = try? JSONDecoder().decode(BoulderJson.self, from: data) else {
            return nil
        }
        return record.properties.vertices.map { v in
            BoulderVertex(
                latitude: v.latitude,
                longitude: v.longitude,
                horizontalAccuracy: v.horizontalAccuracy,
                sampleCount: v.sampleCount,
                source: BoulderVertex.VertexSource(rawValue: v.source) ?? .tap
            )
        }
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
