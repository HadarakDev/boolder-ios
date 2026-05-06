//
//  BoulderDrawEntry.swift
//  Boolder
//
//  Created for TopoSud (DEVELOPMENT-only) to author boulder polygons on-site.
//  Mirrors the shape of TopoEntry: an @Observable holder that lives at the
//  MapContainerView level and is read by both the FAB and the drawing overlay.
//

#if DEVELOPMENT

import Foundation
import CoreLocation

/// One vertex of the boulder polygon.
/// Source distinguishes GPS-derived points (with measured accuracy) from
/// hand-tapped points on the map (no accuracy info).
struct BoulderVertex: Identifiable, Equatable {
    let id: UUID
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double?
    var sampleCount: Int
    var source: VertexSource

    enum VertexSource: String, Codable {
        case gps
        case tap
    }

    init(
        id: UUID = UUID(),
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: Double? = nil,
        sampleCount: Int = 1,
        source: VertexSource
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.sampleCount = sampleCount
        self.source = source
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

@Observable
final class BoulderDrawEntry {
    var drawingEnabled: Bool = false
    var vertices: [BoulderVertex] = []
    var comments: String = ""
    /// True while a multi-sample GPS average is in progress (used by the UI
    /// to show a "averaging…" indicator).
    var isAveraging: Bool = false
    /// Bumped after a successful Save so the map can re-read the on-disk
    /// boulders directory and refresh its "saved boulders" overlay. Not
    /// cleared by reset() — it's monotonic.
    var savedBouldersVersion: Int = 0

    func reset() {
        drawingEnabled = false
        vertices = []
        comments = ""
        isAveraging = false
    }

    func removeVertex(id: UUID) {
        vertices.removeAll { $0.id == id }
    }
}

#endif
