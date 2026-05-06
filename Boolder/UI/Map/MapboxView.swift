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
        // Hide saved boulders only once the user has started reshaping (any
        // vertex in the in-progress polygon). With an empty entry we keep
        // them visible so the user can tap one to load it for edit.
        let hideSaved = (boulderDrawEntry?.drawingEnabled ?? false)
            && (boulderDrawEntry?.vertices.isEmpty == false)
        vc.setSavedBouldersHidden(hideSaved)

        // Refresh the "saved boulders" overlay from disk whenever a new
        // boulder is saved (the version counter is monotonic).
        let savedVersion = boulderDrawEntry?.savedBouldersVersion ?? 0
        if context.coordinator.lastSavedBouldersVersion != savedVersion {
            context.coordinator.lastSavedBouldersVersion = savedVersion
            vc.refreshSavedBoulders()
        }
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
        var lastSavedBouldersVersion: Int = -1
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
        #endif
    }
}
