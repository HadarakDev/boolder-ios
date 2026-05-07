//
//  AreaDrawSaver.swift
//  Boolder
//
//  Serialises an AreaDrawEntry to a GeoJSON Feature Polygon at
//  Documents/map-maker/areas/<timestamp>.json. Mirrors BoulderDrawSaver.
//

#if DEVELOPMENT

import Foundation
import CoreLocation

enum AreaDrawSaver {
    struct VertexJson: Codable {
        var longitude: Double
        var latitude: Double
        var horizontalAccuracy: Double?
        var sampleCount: Int
        var source: String
    }

    struct AreaJson: Codable {
        var type: String                  // "Feature" — GeoJSON-friendly
        var geometry: GeometryJson
        var properties: PropertiesJson
    }

    struct GeometryJson: Codable {
        var type: String                  // "Polygon"
        var coordinates: [[[Double]]]
    }

    struct PropertiesJson: Codable {
        var createdAt: String
        var name: String
        var comments: String
        var vertices: [VertexJson]
        /// Bounding box derived from the vertex ring — useful for the
        /// pipeline so an area JSON drops cleanly into the upstream
        /// `areas` table without re-deriving on the Python side.
        var southWestLat: Double
        var southWestLon: Double
        var northEastLat: Double
        var northEastLon: Double
    }

    @discardableResult
    static func save(entry: AreaDrawEntry, store: MapMakerStore = MapMakerStore()) -> URL? {
        guard entry.vertices.count >= 3 else { return nil }

        let isOverwrite = entry.editingFilename != nil
        let baseFilename = entry.editingFilename ?? (store.timestamp() + ".json")

        let ring: [[Double]] = entry.vertices.map { v in [v.longitude, v.latitude] }
        let closedRing = ring + [ring[0]]

        let lats = entry.vertices.map(\.latitude)
        let lons = entry.vertices.map(\.longitude)
        let swLat = lats.min() ?? 0
        let neLat = lats.max() ?? 0
        let swLon = lons.min() ?? 0
        let neLon = lons.max() ?? 0

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        let record = AreaJson(
            type: "Feature",
            geometry: GeometryJson(type: "Polygon", coordinates: [closedRing]),
            properties: PropertiesJson(
                createdAt: isoFormatter.string(from: Date()),
                name: entry.name,
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
                southWestLat: swLat,
                southWestLon: swLon,
                northEastLat: neLat,
                northEastLon: neLon
            )
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(record)
            store.save(data: data, directory: "areas", filename: baseFilename, overwrite: isOverwrite)
            return URL(fileURLWithPath: baseFilename)
        } catch {
            print("AreaDrawSaver save error:", error)
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
            print("AreaDrawSaver delete error:", error)
            return false
        }
    }

    static func loadVertices(filename: String) -> [BoulderVertex]? {
        let url = directoryURL().appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url),
              let record = try? JSONDecoder().decode(AreaJson.self, from: data) else {
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

    static func load(filename: String) -> AreaJson? {
        let url = directoryURL().appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url),
              let record = try? JSONDecoder().decode(AreaJson.self, from: data) else {
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
        return baseURL.appendingPathComponent("map-maker").appendingPathComponent("areas")
    }
}

#endif
