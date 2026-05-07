//
//  AreaDrawEntry.swift
//  Boolder
//
//  Created for TopoSud (DEVELOPMENT-only) to author climbing areas (sectors)
//  on the map. Mirrors BoulderDrawEntry's shape — same vertex / drag /
//  averaging patterns — but renders in a different colour and lives in
//  its own on-disk directory (`map-maker/areas/`).
//

#if DEVELOPMENT

import Foundation
import CoreLocation

@Observable
final class AreaDrawEntry {
    var drawingEnabled: Bool = false
    var vertices: [BoulderVertex] = []
    var name: String = ""
    var comments: String = ""
    var isAveraging: Bool = false
    var savedAreasVersion: Int = 0
    var editingFilename: String?
    /// Set when a saved area is tapped on the map outside of any Map
    /// Maker mode — drives the top toolbar + the optional info sheet.
    var viewingFilename: String?

    func reset() {
        drawingEnabled = false
        vertices = []
        name = ""
        comments = ""
        isAveraging = false
        editingFilename = nil
    }

    func removeVertex(id: UUID) {
        vertices.removeAll { $0.id == id }
    }

    func moveVertex(id: UUID, to coord: CLLocationCoordinate2D) {
        guard let idx = vertices.firstIndex(where: { $0.id == id }) else { return }
        var v = vertices[idx]
        v.latitude = coord.latitude
        v.longitude = coord.longitude
        v.horizontalAccuracy = nil
        v.sampleCount = 1
        v.source = .tap
        vertices[idx] = v
    }

    func translateAll(dLat: Double, dLon: Double) {
        guard !vertices.isEmpty else { return }
        vertices = vertices.map { v in
            var copy = v
            copy.latitude += dLat
            copy.longitude += dLon
            return copy
        }
    }
}

#endif
