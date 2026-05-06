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

        let timestamp = store.timestamp()

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
            let filename = timestamp + ".json"
            store.save(data: data, directory: "boulders", filename: filename)
            return URL(fileURLWithPath: filename) // informational; MapMakerStore handles real path
        } catch {
            print("BoulderDrawSaver save error:", error)
            return nil
        }
    }
}

#endif
