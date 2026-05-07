//
//  MapboxView.swift
//  Boolder
//
//  Created by Nicolas Mondollot on 27/10/2022.
//  Copyright © 2022 Nicolas Mondollot. All rights reserved.
//

import SwiftUI
import CoreLocation
import MapboxMaps
import Combine

// Bridge between SwiftUI-world (driven by MapState) and UIKit-world (MapboxViewController)
// 2 ways to communicate:
// SwiftUI -> UIKit : MapboxView.updateUIViewController
// UIKit -> SwiftUI : MapBoxViewDelegate protocol

struct MapboxView: UIViewControllerRepresentable {
    var mapState: MapState
    #if DEVELOPMENT
    var topoEntry: TopoEntry? = nil
    var boulderDrawEntry: BoulderDrawEntry? = nil
    var problemEntry: ProblemEntry? = nil
    var areaDrawEntry: AreaDrawEntry? = nil
    #endif

    func makeUIViewController(context: Context) -> MapboxViewController {
        let vc = MapboxViewController()
        vc.delegate = context.coordinator
        context.coordinator.viewController = vc
        return vc
    }
    
    func updateUIViewController(_ vc: MapboxViewController, context: Context) {
        #if DEVELOPMENT
        // Wire Map Maker picker mode through to the controller and coordinator.
        vc.pickerMode = topoEntry?.pickerModeEnabled ?? false
        context.coordinator.topoEntry = topoEntry

        // Wire Map Maker boulder-draw mode the same way. Drawing geometry is
        // re-pushed every update so a vertex add/remove driven by the overlay
        // re-renders the polygon on the map without a roundtrip through state.
        vc.drawMode = boulderDrawEntry?.drawingEnabled ?? false
        vc.currentDrawVertexCount = boulderDrawEntry?.vertices.count ?? 0
        context.coordinator.boulderDrawEntry = boulderDrawEntry
        if let entry = boulderDrawEntry, entry.drawingEnabled {
            let ids = entry.vertices.map { $0.id.uuidString }
            let coords = entry.vertices.map { $0.coordinate }
            vc.updateBoulderDrawGeometry(vertexIds: ids, coordinates: coords)
        } else {
            vc.updateBoulderDrawGeometry(vertexIds: [], coordinates: [])
        }
        // Hide saved boulders only when reshaping an *existing* polygon —
        // that's where the duplicate-vertex visual issue happens. While
        // drawing a brand-new polygon (no editingFilename), keep the other
        // saved boulders visible so the user has spatial reference.
        let hideSaved = (boulderDrawEntry?.drawingEnabled ?? false)
            && (boulderDrawEntry?.editingFilename != nil)
            && (boulderDrawEntry?.vertices.isEmpty == false)
        vc.setSavedBouldersHidden(hideSaved)

        // Refresh the "saved boulders" overlay from disk whenever a new
        // boulder is saved (the version counter is monotonic).
        let savedVersion = boulderDrawEntry?.savedBouldersVersion ?? 0
        if context.coordinator.lastSavedBouldersVersion != savedVersion {
            context.coordinator.lastSavedBouldersVersion = savedVersion
            vc.refreshSavedBoulders()
        }

        // Wire problem-add mode through to the controller and coordinator.
        vc.addProblemMode = problemEntry?.addingEnabled ?? false
        context.coordinator.problemEntry = problemEntry

        // Refresh the "saved problems" overlay from disk on monotonic bumps.
        let savedProblemsVersion = problemEntry?.savedProblemsVersion ?? 0
        if context.coordinator.lastSavedProblemsVersion != savedProblemsVersion {
            context.coordinator.lastSavedProblemsVersion = savedProblemsVersion
            vc.refreshSavedProblems()
        }

        // Hide the saved-problems pin while it's being edited (avoids the
        // "two pins on top of each other" effect during edit).
        let editingProblem = (problemEntry?.editingFilename != nil)
            && (problemEntry?.pendingCoord != nil)
        vc.setSavedProblemsHidden(editingProblem)

        // Wire area-draw mode through.
        vc.drawAreaMode = areaDrawEntry?.drawingEnabled ?? false
        vc.currentDrawAreaVertexCount = areaDrawEntry?.vertices.count ?? 0
        context.coordinator.areaDrawEntry = areaDrawEntry
        if let entry = areaDrawEntry, entry.drawingEnabled {
            let ids = entry.vertices.map { $0.id.uuidString }
            let coords = entry.vertices.map { $0.coordinate }
            vc.updateAreaDrawGeometry(vertexIds: ids, coordinates: coords)
        } else {
            vc.updateAreaDrawGeometry(vertexIds: [], coordinates: [])
        }

        let savedAreasVersion = areaDrawEntry?.savedAreasVersion ?? 0
        if context.coordinator.lastSavedAreasVersion != savedAreasVersion {
            context.coordinator.lastSavedAreasVersion = savedAreasVersion
            vc.refreshSavedAreas()
        }

        // Same reasoning as boulders: only hide the saved-areas overlay when
        // we're reshaping an existing area, not while drawing a fresh one.
        let hideAreas = (areaDrawEntry?.drawingEnabled ?? false)
            && (areaDrawEntry?.editingFilename != nil)
            && (areaDrawEntry?.vertices.isEmpty == false)
        vc.setSavedAreasHidden(hideAreas)
        #endif

        // Pass pre-cached topo problem IDs so setProblemAsSelected never hits SQLite
        if let topoId = mapState.selectedTopo?.id {
            vc.selectedTopoProblemIds = mapState.boulderProblems
                .filter { $0.topoId == topoId }
                .map { String($0.id) }
        } else {
            vc.selectedTopoProblemIds = []
        }
        
        // Handle selection changes (problem or topo)
        let selectedId = mapState.selectedProblem?.id ?? 0
        let isTopoMode = mapState.selectedTopo != nil
        
        if context.coordinator.lastSelectedProblemId != selectedId || context.coordinator.lastIsTopoMode != isTopoMode {
            context.coordinator.lastSelectedProblemId = selectedId
            context.coordinator.lastIsTopoMode = isTopoMode
            if selectedId != 0 {
                vc.setProblemAsSelected(problemFeatureId: String(selectedId))
            }
        }
        
        // Handle centerOnProblem changes
        if let centerOnProblem = mapState.centerOnProblem {
            let centerOnProblemId = centerOnProblem.id
            if context.coordinator.lastCenterOnProblemId != centerOnProblemId {
                context.coordinator.lastCenterOnProblemId = centerOnProblemId
                vc.centerOnProblem(centerOnProblem)
            }
        }
        
        // Handle centerOnArea changes
        if let centerOnArea = mapState.centerOnArea {
            let centerOnAreaId = centerOnArea.id
            if context.coordinator.lastCenterOnAreaId != centerOnAreaId {
                context.coordinator.lastCenterOnAreaId = centerOnAreaId
                vc.centerOnArea(centerOnArea)
            }
        }
        
        // Handle centerOnCurrentLocation changes
        if mapState.currentLocationCount != context.coordinator.lastCurrentLocationCount {
            context.coordinator.lastCurrentLocationCount = mapState.currentLocationCount
            vc.centerOnCurrentLocation()
        }
        
        // Handle centerOnBoulder changes
        if mapState.centerOnBoulderCount != context.coordinator.lastCenterOnBoulderCount {
            context.coordinator.lastCenterOnBoulderCount = mapState.centerOnBoulderCount
            vc.centerOnBoulderCoordinates(mapState.centerOnBoulderCoordinates)
        }
        
        // Handle centerOnCircuit changes
        if let centerOnCircuit = mapState.centerOnCircuit {
            let centerOnCircuitId = centerOnCircuit.id
            if context.coordinator.lastCenterOnCircuitId != centerOnCircuitId {
                context.coordinator.lastCenterOnCircuitId = centerOnCircuitId
                vc.centerOnCircuit(centerOnCircuit)
            }
        }
        else {
            if context.coordinator.lastSelectedCircuitId != 0 {
                context.coordinator.lastSelectedCircuitId = 0
                vc.unselectCircuit()
            }
        }

        // Handle selectedCircuit changes
        if let selectedCircuit = mapState.selectedCircuit {
            let selectedCircuitId = selectedCircuit.id
            if context.coordinator.lastSelectedCircuitId != selectedCircuitId {
                context.coordinator.lastSelectedCircuitId = selectedCircuitId
                vc.setCircuitAsSelected(circuit: selectedCircuit)
            }
        }
        else {
            if context.coordinator.lastSelectedCircuitId != 0 {
                context.coordinator.lastSelectedCircuitId = 0
                vc.unselectCircuit()
            }
        }
        
        // Handle refreshFilters changes
        if mapState.refreshFiltersCount != context.coordinator.lastRefreshFiltersCount {
            context.coordinator.lastRefreshFiltersCount = mapState.refreshFiltersCount
            vc.applyFilters(mapState.filters)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: Coordinator
    
    class Coordinator: MapBoxViewDelegate {
        var parent: MapboxView
        var viewController: MapboxViewController?

        var lastSelectedProblemId: Int = 0
        var lastCenterOnProblemId: Int = 0
        var lastCenterOnAreaId: Int = 0
        var lastCurrentLocationCount: Int = 0
        var lastCenterOnCircuitId: Int = 0
        var lastSelectedCircuitId: Int = 0
        var lastRefreshFiltersCount: Int = 0
        var lastIsTopoMode: Bool = false
        var lastCenterOnBoulderCount: Int = 0

        #if DEVELOPMENT
        var topoEntry: TopoEntry?
        var boulderDrawEntry: BoulderDrawEntry?
        var problemEntry: ProblemEntry?
        var areaDrawEntry: AreaDrawEntry?
        var lastSavedBouldersVersion: Int = -1
        var lastSavedProblemsVersion: Int = -1
        var lastSavedAreasVersion: Int = -1
        #endif

        init(_ parent: MapboxView) {
            self.parent = parent
        }

        func selectProblem(id: Int) {
            #if DEVELOPMENT
            if let entry = topoEntry, entry.pickerModeEnabled {
                guard let problem = Problem.load(id: id) else { return }
                if let idx = entry.problems.firstIndex(where: { $0.id == problem.id }) {
                    entry.problems.remove(at: idx)
                } else {
                    entry.problems.append(problem)
                }
                return
            }
            #endif
            if let problem = Problem.load(id: id) {
                parent.mapState.selectProblem(problem, source: .map)
                parent.mapState.presentProblemDetails = true
            }
        }
        
        func selectArea(id: Int) {
            if let area = Area.load(id: id) {
                parent.mapState.selectArea(area)
            }
        }
        
        func selectCluster(id: Int) {
            if let cluster = Cluster.load(id: id) {
                parent.mapState.selectCluster(cluster)
            }
        }
        
        func unselectArea() {
            parent.mapState.unselectArea()
        }
        
        func unselectCluster() {
            parent.mapState.unselectCluster()
        }
        
        func unselectCircuit() {
            parent.mapState.unselectCircuit()
        }
        
        func selectPoi(name: String, location: CLLocationCoordinate2D, googleUrl: String) {
            // FIXME: use short name or long name?
            // FIXME: don't use id=0
            let poi = Poi(id: 0, type: .parking, name: name, shortName: name, googleUrl: googleUrl, coordinate: location)
            parent.mapState.selectedPoi = poi
        }
        
        func dismissProblemDetails() {
            parent.mapState.presentProblemDetails = false
        }
        
        func cameraChanged(state: MapboxMaps.CameraState) {
            if parent.mapState.displayCircuitStartButton {
                parent.mapState.displayCircuitStartButton = false
            }

            // TODO: deal with padding
            parent.mapState.updateCameraState(center: state.center, zoom: state.zoom)
        }

        #if DEVELOPMENT
        func addBoulderVertex(coord: CLLocationCoordinate2D) {
            guard let entry = boulderDrawEntry, entry.drawingEnabled else { return }
            entry.vertices.append(BoulderVertex(
                latitude: coord.latitude,
                longitude: coord.longitude,
                horizontalAccuracy: nil,
                sampleCount: 1,
                source: .tap
            ))
        }

        func removeBoulderVertex(vertexId: String) {
            guard let entry = boulderDrawEntry, entry.drawingEnabled else { return }
            guard let uuid = UUID(uuidString: vertexId) else { return }
            entry.removeVertex(id: uuid)
        }

        func moveBoulderVertex(vertexId: String, to coord: CLLocationCoordinate2D) {
            guard let entry = boulderDrawEntry, entry.drawingEnabled else { return }
            guard let uuid = UUID(uuidString: vertexId) else { return }
            entry.moveVertex(id: uuid, to: coord)
        }

        func translateBoulderPolygon(dLat: Double, dLon: Double) {
            guard let entry = boulderDrawEntry, entry.drawingEnabled else { return }
            entry.translateAll(dLat: dLat, dLon: dLon)
        }

        func editSavedBoulder(filename: String) {
            guard let entry = boulderDrawEntry, entry.drawingEnabled else { return }
            // Only load if the in-progress polygon is empty so we never wipe
            // an unsaved drawing.
            guard entry.vertices.isEmpty else { return }
            guard let verts = BoulderDrawSaver.loadVertices(filename: filename) else { return }
            entry.vertices = verts
            entry.editingFilename = filename
        }

        func addProblemAt(coord: CLLocationCoordinate2D, boulderFilename: String) {
            guard let entry = problemEntry, entry.addingEnabled else { return }
            guard entry.pendingCoord == nil else { return }
            entry.clearPending()
            entry.pendingCoord = coord
            entry.boulderId = boulderFilename
        }

        func editSavedProblem(filename: String) {
            guard let entry = problemEntry, entry.addingEnabled else { return }
            guard entry.pendingCoord == nil else { return }
            guard let record = ProblemSaver.load(filename: filename),
                  record.geometry.coordinates.count >= 2 else { return }
            entry.pendingCoord = CLLocationCoordinate2D(
                latitude: record.geometry.coordinates[1],
                longitude: record.geometry.coordinates[0]
            )
            entry.name = record.properties.name
            entry.grade = record.properties.grade
            entry.comments = record.properties.comments
            entry.boulderId = record.properties.boulderId
            entry.editingFilename = filename
        }

        func saveProblemMove(filename: String, to coord: CLLocationCoordinate2D, boulderFilename: String) {
            guard let entry = problemEntry else { return }
            // Load + mutate + write through the existing save path so the
            // overwrite logic (atomic + version bump) stays in one place.
            guard let record = ProblemSaver.load(filename: filename) else {
                entry.savedProblemsVersion += 1
                return
            }
            entry.pendingCoord = coord
            entry.name = record.properties.name
            entry.grade = record.properties.grade
            entry.comments = record.properties.comments
            entry.boulderId = boulderFilename
            entry.editingFilename = filename
            _ = ProblemSaver.save(entry: entry)
            entry.clearPending()
            entry.savedProblemsVersion += 1
        }

        func revertProblemMove() {
            // Bumping the version forces refreshSavedProblems() — it
            // re-pulls from disk and overwrites the in-memory edits the
            // controller pushed during the drag.
            problemEntry?.savedProblemsVersion += 1
        }

        func addAreaVertex(coord: CLLocationCoordinate2D) {
            guard let entry = areaDrawEntry, entry.drawingEnabled else { return }
            entry.vertices.append(BoulderVertex(
                latitude: coord.latitude,
                longitude: coord.longitude,
                horizontalAccuracy: nil,
                sampleCount: 1,
                source: .tap
            ))
        }

        func removeAreaVertex(vertexId: String) {
            guard let entry = areaDrawEntry, entry.drawingEnabled else { return }
            guard let uuid = UUID(uuidString: vertexId) else { return }
            entry.removeVertex(id: uuid)
        }

        func moveAreaVertex(vertexId: String, to coord: CLLocationCoordinate2D) {
            guard let entry = areaDrawEntry, entry.drawingEnabled else { return }
            guard let uuid = UUID(uuidString: vertexId) else { return }
            entry.moveVertex(id: uuid, to: coord)
        }

        func translateAreaPolygon(dLat: Double, dLon: Double) {
            guard let entry = areaDrawEntry, entry.drawingEnabled else { return }
            entry.translateAll(dLat: dLat, dLon: dLon)
        }

        func editSavedArea(filename: String) {
            guard let entry = areaDrawEntry, entry.drawingEnabled else { return }
            guard entry.vertices.isEmpty else { return }
            guard let verts = AreaDrawSaver.loadVertices(filename: filename),
                  let record = AreaDrawSaver.load(filename: filename) else { return }
            entry.vertices = verts
            entry.name = record.properties.name
            entry.comments = record.properties.comments
            entry.editingFilename = filename
        }

        func selectCustomProblem(filename: String) {
            // Picker mode (camera FAB) toggles a custom problem in the
            // TopoEntry's customProblems array, mirroring how upstream
            // problems get toggled in TopoEntry.problems.
            guard let entry = topoEntry, entry.pickerModeEnabled else { return }
            // Locate the saved problem by filename via the on-disk library.
            // Reading on every tap is cheap (a handful of small JSONs).
            guard let saved = ProblemLibrary.loadAll().first(where: { $0.filename == filename }) else { return }
            if let idx = entry.customProblems.firstIndex(where: { $0.filename == filename }) {
                entry.customProblems.remove(at: idx)
            } else {
                entry.customProblems.append(saved)
            }
        }
        #endif
    }
}
