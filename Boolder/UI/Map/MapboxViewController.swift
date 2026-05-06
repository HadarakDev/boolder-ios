//
//  MapboxViewController.swift
//  Boolder
//
//  Created by Nicolas Mondollot on 27/10/2022.
//  Copyright © 2022 Nicolas Mondollot. All rights reserved.
//

import UIKit
import MapboxMaps
import CoreLocation

class MapboxViewController: UIViewController {
    var mapView: MapView!
    var delegate: MapBoxViewDelegate?
    var cancelables = Set<AnyCancelable>()

    private var currentFilters: Filters?
    private var currentCircuit: Circuit?

    #if DEVELOPMENT
    // When true, taps on the map only pick problems for the Map Maker's TopoEntry —
    // no area/cluster/POI selection, no camera move, no problem details.
    var pickerMode: Bool = false

    // When true, taps add/remove vertices for an in-progress boulder polygon
    // (Map Maker draw mode). Mutually exclusive with pickerMode at the call site.
    var drawMode: Bool = false

    // Number of vertices currently in the in-progress polygon. Pushed from
    // MapboxView every update; used by the tap dispatcher to decide whether
    // a tap on a saved boulder should be interpreted as "load for edit".
    var currentDrawVertexCount: Int = 0

    // Source / layer ids for the in-progress polygon overlay. Created in
    // setupBoulderDrawSourcesAndLayers() and refreshed via updateBoulderDrawGeometry().
    fileprivate let boulderDrawPolygonSourceId = "boulder-draw-polygon"
    fileprivate let boulderDrawVerticesSourceId = "boulder-draw-vertices"
    fileprivate let boulderDrawFillLayerId = "boulder-draw-fill"
    fileprivate let boulderDrawStrokeLayerId = "boulder-draw-stroke"
    fileprivate let boulderDrawVerticesLayerId = "boulder-draw-vertices"
    fileprivate let boulderDrawVertexLabelsLayerId = "boulder-draw-vertex-labels"

    // Drag-to-move state. Set on long-press over a vertex; cleared on
    // gesture end/cancel.
    fileprivate var draggingVertexId: String?

    // Source / layer ids for the persistent "saved boulders" overlay (read
    // from disk on style load and after every save).
    fileprivate let savedBouldersSourceId = "saved-boulders"
    fileprivate let savedBouldersFillLayerId = "saved-boulders-fill"
    fileprivate let savedBouldersStrokeLayerId = "saved-boulders-stroke"
    fileprivate let savedBouldersVerticesSourceId = "saved-boulders-vertices"
    fileprivate let savedBouldersVerticesLayerId = "saved-boulders-vertices"
    fileprivate let savedBouldersVertexLabelsLayerId = "saved-boulders-vertex-labels"
    #endif
    
    // Map styles for light and dark mode.
    // The dark style is currently 404 against any TopoSud-side Mapbox token
    // (it lives in the upstream `nmondollot` account and is private), so we
    // fall back to the light style in dark mode too. Replace with our own
    // styles once TopoSud has its own Mapbox tilesets.
    private let lightStyleURI = StyleURI(rawValue: "mapbox://styles/nmondollot/cl95n147u003k15qry7pvfmq2")!
    private let darkStyleURI = StyleURI(rawValue: "mapbox://styles/nmondollot/cmkea670800a701sdc5n67k3q")!

    private var currentStyleURI: StyleURI {
        // TODO: re-enable dark style once we host our own.
        return lightStyleURI
    }
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        
        let cameraOptions = CameraOptions(
            center: CLLocationCoordinate2D(latitude: 48.3925623, longitude: 2.5968216),
            zoom: 10.2
        )
        
        let myMapInitOptions = MapInitOptions(
            cameraOptions: cameraOptions,
            styleURI: currentStyleURI
        )
        
        mapView = MapView(frame: view.bounds, mapInitOptions: myMapInitOptions)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        let configuration = Puck2DConfiguration.makeDefault(showBearing: true)
        mapView.location.options.puckType = .puck2D(configuration)
        mapView.location.options.puckBearingEnabled = true
        
        mapView.gestures.options.pitchEnabled = false
        mapView.gestures.options.simultaneousRotateAndPinchZoomEnabled = false
        mapView.gestures.options.doubleTapToZoomInEnabled = false // prevents the delay for TapInteraction
        mapView.gestures.options.doubleTouchToZoomOutEnabled = false // prevents the delay for TapInteraction
        
        mapView.ornaments.options.scaleBar.visibility = .hidden
        
        mapView.ornaments.options.compass.position = .bottomLeft
        mapView.ornaments.options.compass.margins = CGPoint(x: 12, y: 72)
        
        mapView.ornaments.options.attributionButton.position = .bottomLeading
        mapView.ornaments.options.attributionButton.margins = CGPoint(x: 4, y: 0)
        mapView.ornaments.options.logo.margins = CGPoint(x: 16, y: 8)
        
        // Make attribution elements less noticeable
        mapView.ornaments.logoView.alpha = 0.5
        mapView.ornaments.attributionButton.alpha = 0.2
        
        // Re-add sources, layers, and filters every time the style is (re)loaded.
        // This covers the initial load, dark/light mode switches, and background/foreground
        // transitions where Mapbox silently reloads the style after the Metal context is released.
        mapView.mapboxMap.onStyleLoaded.observe { [weak self] _ in
            guard let self = self else { return }
            self.addSources()
            self.addLayers()
            #if DEVELOPMENT
            self.setupBoulderDrawSourcesAndLayers()
            self.setupSavedBouldersSourceAndLayers()
            self.refreshSavedBoulders()
            #endif
            if let filters = self.currentFilters {
                self.applyFilters(filters)
            }
            if let circuit = self.currentCircuit {
                self.setCircuitAsSelected(circuit: circuit)
            }
        }.store(in: &cancelables)
        
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: MapboxViewController, _) in
            self.updateMapStyle()
        }
        
        mapView.mapboxMap.addInteraction(TapInteraction { context in
            self.findFeatures(tapPoint: context.point)
            return true
        })

        #if DEVELOPMENT
        // Long-press a vertex to drag it. Active only in draw mode.
        let drag = UILongPressGestureRecognizer(target: self, action: #selector(handleVertexDrag(_:)))
        drag.minimumPressDuration = 0.3
        drag.cancelsTouchesInView = false
        mapView.addGestureRecognizer(drag)
        #endif
        
        // Important
        // This callback is called on every rendering frame. Don’t use it to modify @State variables, it will lead to excessive body execution and higher CPU consumption.
        // https://docs.mapbox.com/ios/maps/api/11.0.0-rc.1-docc/documentation/mapboxmaps/map-swift.struct/oncamerachanged(action:)/
        mapView.mapboxMap.onCameraChanged
            .filter { [weak self] _ in
                guard let self = self else { return false }
                return !self.flyinToSomething
            }
            .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] event in
                guard let self = self else { return }
                
                self.inferAreaFromMap()
                self.inferClusterFromMap()
                self.delegate?.cameraChanged(state: mapView.mapboxMap.cameraState)
            }.store(in: &cancelables)
        
        self.view.addSubview(mapView)
    }
    
    private func updateMapStyle() {
        mapView.mapboxMap.loadStyle(currentStyleURI)
    }

    let problemsSourceLayerId = "problems-ayes3a" // name of the layer in the mapbox tileset
    
    func addSources() {
        var problems = VectorSource(id: "problems")
        problems.url = "mapbox://nmondollot.4xsv235p"
        problems.promoteId2 = .byLayer([problemsSourceLayerId: .constant("id")]) // needed to make Feature-State work
        
        var circuits = VectorSource(id: "circuits")
        circuits.url = "mapbox://nmondollot.11sumdgh"

        do {
            try self.mapView.mapboxMap.addSource(problems)
            try self.mapView.mapboxMap.addSource(circuits)
        }
        catch {
            print("Ran into an error adding the sources: \(error)")
        }
    }
    
    func addLayers() {
        var problemsLayer = CircleLayer(id: "problems", source: "problems")
        problemsLayer.sourceLayer = problemsSourceLayerId
        problemsLayer.minZoom = 15
        problemsLayer.filter = Exp(.match) {
            ["geometry-type"]
            ["Point"] // don't display boulders (stored in the tileset as LineStrings)
            true
            false
        }
        
        problemsLayer.circleRadius = .expression(
            Exp(.interpolate) {
                ["linear"]
                ["zoom"]
                15
                2
                18
                4
                22
                Exp(.switchCase) {
                    Exp(.boolean) {
                        Exp(.has) { "circuitNumber" }
                        false
                    }
                    16
                    10
                }
            }
        )
        
        problemsLayer.circleColor = circuitColorExp(attribute: "circuitColor")
        
        problemsLayer.circleStrokeWidth = .expression(
            Exp(.switchCase) {
                Exp(.boolean) {
                    Exp(.featureState) { "selected" }
                    false
                }
                3.0
                0.0
            }
        )
        
        problemsLayer.circleStrokeColor = .constant(StyleColor(UIColor(resource: .appGreen)))
        
        problemsLayer.circleSortKey = .expression(
            Exp(.switchCase) {
                Exp(.boolean) {
                    Exp(.has) { "circuitId" }
                    false
                }
                2
                1
            }
        )
        
        problemsLayer.circleEmissiveStrength = .constant(0.9)
        
        var problemsTextsLayer = SymbolLayer(id: "problems-texts", source: "problems")
        problemsTextsLayer.sourceLayer = problemsSourceLayerId
        problemsTextsLayer.minZoom = 19
        problemsTextsLayer.filter = Exp(.match) {
            ["geometry-type"]
            ["Point"]
            true
            false
        }
        
        problemsTextsLayer.textAllowOverlap = .constant(true)
        problemsTextsLayer.textField = .expression(
            Exp(.toString) {
                ["get", "circuitNumber"]
            }
        )
        
        problemsTextsLayer.textSize = .expression(
            Exp(.interpolate) {
                ["linear"]
                ["zoom"]
                19
                10
                22
                20
            }
        )
        
        problemsTextsLayer.textColor = .expression(
            Exp(.switchCase) {
                Exp(.match) {
                    ["get", "circuitColor"]
                    ["", "white"]
                    true
                    false
                }
                UIColor.black // TODO: less dark
                UIColor.white
            }
        )
        
        // ===========================
        
        var problemsNamesLayer = SymbolLayer(id: "problems-names", source: "problems")
        problemsNamesLayer.sourceLayer = problemsSourceLayerId
        problemsNamesLayer.minZoom = 15
        problemsNamesLayer.visibility = .constant(.none)
        problemsNamesLayer.filter = Exp(.match) {
            ["geometry-type"]
            ["Point"]
            true
            false
        }
        
        problemsNamesLayer.textField = .expression(
            Exp(.concat) {
                Exp(.toString) {
                    ["get", "name"]
                }
                " "
                Exp(.toString) {
                    ["get", "grade"]
                }
            }
        )
        
        problemsNamesLayer.textSize = .expression(
            Exp(.interpolate) {
                ["linear"]
                ["zoom"]
                15
                8
                20
                14
            }
        )
        
        problemsNamesLayer.textVariableAnchor = .constant([.bottom, .top, .right, .left])
        problemsNamesLayer.textRadialOffset = .expression(
            Exp(.interpolate) {
                ["linear"]
                ["zoom"]
                15
                1
                20
                1.5
            }
        )
        problemsNamesLayer.textHaloColor = .constant(.init(traitCollection.userInterfaceStyle == .dark ? .black : .white))
        problemsNamesLayer.textHaloWidth = .constant(1)
        problemsNamesLayer.textColor = .constant(.init(traitCollection.userInterfaceStyle == .dark ? .white : .black))
        
        problemsNamesLayer.textAllowOverlap = .constant(false)
        problemsNamesLayer.textOptional = .constant(true)
        problemsNamesLayer.textIgnorePlacement = .constant(false)
        
        problemsNamesLayer.symbolSortKey = .expression(
            Exp(.product) {
                Exp(.toNumber) {
                    Exp(.get) { "popularity" }
                }
                -1.0
            }
        )
        
        // (invisible) layer to prevent problem names from overlapping with the problem circles
        var problemsNamesAntioverlapLayer = SymbolLayer(id: "problems-names-antioverlap", source: "problems")
        problemsNamesAntioverlapLayer.sourceLayer = problemsSourceLayerId
        problemsNamesAntioverlapLayer.minZoom = 15
        problemsNamesAntioverlapLayer.visibility = .constant(.none)
        problemsNamesAntioverlapLayer.filter = Exp(.match) {
            ["geometry-type"]
            ["Point"]
            true
            false
        }
        
        problemsNamesAntioverlapLayer.iconImage = .constant(.name("circle-15"))
        problemsNamesAntioverlapLayer.iconSize = .expression(
            Exp(.interpolate) {
                ["linear"]
                ["zoom"]
                15
                0.2
                20
                1
            }
        )
        problemsNamesAntioverlapLayer.iconAllowOverlap = .constant(true)
        problemsNamesAntioverlapLayer.iconOpacity = .constant(0)
        
        // ===========================
        
        var circuitsLayer = LineLayer(id: "circuits", source: "circuits")
        circuitsLayer.sourceLayer = "circuits-9weff8"
        circuitsLayer.minZoom = 15
        circuitsLayer.lineWidth = .constant(2)
        circuitsLayer.lineDasharray = .constant([4,1])
        circuitsLayer.lineColor = circuitColorExp(attribute: "color")
        circuitsLayer.visibility = .constant(.none)
        circuitsLayer.lineEmissiveStrength = .constant(0.9)
        
        var circuitProblemsLayer = CircleLayer(id: "circuit-problems", source: "problems")
        circuitProblemsLayer.sourceLayer = problemsSourceLayerId
        circuitProblemsLayer.minZoom = 15
        circuitProblemsLayer.visibility = .constant(.none)
        
        circuitProblemsLayer.circleRadius = .expression(
            Exp(.interpolate) {
                ["linear"]
                ["zoom"]
                15
                2
                18
                10
                22
                16
            }
        )
        
        circuitProblemsLayer.circleEmissiveStrength = .constant(0.9)
        
        circuitProblemsLayer.circleColor = problemsLayer.circleColor
        circuitProblemsLayer.circleStrokeWidth = problemsLayer.circleStrokeWidth
        circuitProblemsLayer.circleStrokeColor = problemsLayer.circleStrokeColor
        
        var circuitProblemsTextsLayer = SymbolLayer(id: "circuit-problems-texts", source: "problems")
        circuitProblemsTextsLayer.sourceLayer = problemsSourceLayerId
        circuitProblemsTextsLayer.minZoom = 16
        circuitProblemsTextsLayer.visibility = .constant(.none)

        circuitProblemsTextsLayer.textAllowOverlap = .constant(true)
        circuitProblemsTextsLayer.textField = .expression(
            Exp(.toString) {
                ["get", "circuitNumber"]
            }
        )

        circuitProblemsTextsLayer.textSize = .expression(
            Exp(.interpolate) {
                ["linear"]
                ["zoom"]
                16
                8
                17
                10
                19
                16
                22
                20
            }
        )

        circuitProblemsTextsLayer.textColor = problemsTextsLayer.textColor
        
        // ===========================
        
        do {
            try self.mapView.mapboxMap.addLayer(problemsLayer) // TODO: use layerPosition like on the web?
            try self.mapView.mapboxMap.addLayer(problemsTextsLayer)
            
            try self.mapView.mapboxMap.addLayer(problemsNamesLayer)
            try self.mapView.mapboxMap.addLayer(problemsNamesAntioverlapLayer)
            
            try self.mapView.mapboxMap.addLayer(circuitsLayer)
            try self.mapView.mapboxMap.addLayer(circuitProblemsLayer)
            try self.mapView.mapboxMap.addLayer(circuitProblemsTextsLayer)
        }
        catch {
            print("Ran into an error adding the layers: \(error)")
        }
    }
    
    func circuitColorExp(attribute: String) -> Value<StyleColor> {
        .expression(
            Exp(.match) {
                Exp(.get) { attribute }
                "yellow"
                Circuit.CircuitColor.yellow.uicolor
                "purple"
                Circuit.CircuitColor.purple.uicolor
                "orange"
                Circuit.CircuitColor.orange.uicolor
                "green"
                Circuit.CircuitColor.green.uicolor
                "blue"
                Circuit.CircuitColor.blue.uicolor
                "skyblue"
                Circuit.CircuitColor.skyBlue.uicolor
                "salmon"
                Circuit.CircuitColor.salmon.uicolor
                "red"
                Circuit.CircuitColor.red.uicolor
                "black"
                Circuit.CircuitColor.black.uicolor
                "white"
                Circuit.CircuitColor.white.uicolor
                Circuit.CircuitColor.offCircuit.uicolor
            }
        )
    }
    
    func findFeatures(tapPoint: CGPoint) {

        #if DEVELOPMENT
        if drawMode {
            handleBoulderDrawTap(tapPoint: tapPoint)
            return
        }
        if pickerMode {
            findProblemForPicking(tapPoint: tapPoint)
            return
        }
        #endif

        // =================================================
        // Careful: the order of the queries is important
        // =================================================

        mapView.mapboxMap.queryRenderedFeatures(
            with: tapPoint,
            options: RenderedQueryOptions(layerIds: ["areas", "areas-hulls"], filter: nil)) { [weak self] result in
                
                guard let self = self else { return }
                
                if self.mapView.mapboxMap.cameraState.zoom >= 15 { return }
                
                switch result {
                case .success(let queriedfeatures):
                    
                    if let feature = queriedfeatures.first?.queriedFeature.feature,
                       case .number(let id) = feature.properties?["areaId"],
                       case .string(let southWestLon) = feature.properties?["southWestLon"],
                       case .string(let southWestLat) = feature.properties?["southWestLat"],
                       case .string(let northEastLon) = feature.properties?["northEastLon"],
                       case .string(let northEastLat) = feature.properties?["northEastLat"]
                    {
                        let coords = coordinatesFrom(southWestLat: southWestLat, southWestLon: southWestLon, northEastLat: northEastLat, northEastLon: northEastLon)

                        if let cameraOptions = self.cameraOptionsFor(coords, minZoom: 15) {
                            self.flyTo(cameraOptions)
                            self.delegate?.selectArea(id: Int(id))
                        }
                    }
                case .failure(let error):
                    print("An error occurred: \(error.localizedDescription)")
                }
            }
        
        mapView.mapboxMap.queryRenderedFeatures(
            with: tapPoint,
            options: RenderedQueryOptions(layerIds: ["clusters"], filter: nil)) { [weak self] result in
                
                guard let self = self else { return }
                
                switch result {
                case .success(let queriedfeatures):
                    
                    if let feature = queriedfeatures.first?.queriedFeature.feature,
                       case .number(let id) = feature.properties?["clusterId"],
                       case .string(let southWestLon) = feature.properties?["southWestLon"],
                       case .string(let southWestLat) = feature.properties?["southWestLat"],
                       case .string(let northEastLon) = feature.properties?["northEastLon"],
                       case .string(let northEastLat) = feature.properties?["northEastLat"]
                    {
                        let coords = coordinatesFrom(southWestLat: southWestLat, southWestLon: southWestLon, northEastLat: northEastLat, northEastLon: northEastLon)

                        if let cameraOptions = self.cameraOptionsFor(coords) {
                            self.flyTo(cameraOptions)
                            self.delegate?.selectCluster(id: Int(id))
                        }
                    }
                case .failure(let error):
                    print("An error occurred: \(error.localizedDescription)")
                }
            }
        
        // hack to be able to zoom to a level where problems are tappable
        mapView.mapboxMap.queryRenderedFeatures(
            with: CGRect(x: tapPoint.x-16, y: tapPoint.y-16, width: 32, height: 32),
            options: RenderedQueryOptions(layerIds: ["boulders", "problems-names"], filter: nil)) { [weak self] result in
                
                guard let self = self else { return }
                
                switch result {
                case .success(let queriedfeatures):
                    
                    if(queriedfeatures.first?.queriedFeature.feature.geometry != nil) {
                        if self.mapView.mapboxMap.cameraState.zoom >= 15 && self.mapView.mapboxMap.cameraState.zoom < 19 {
                            let cameraOptions = CameraOptions(
                                center: self.mapView.mapboxMap.coordinate(for: tapPoint),
                                padding: self.safePadding,
                                zoom: 19
                            )
                            self.flyTo(cameraOptions)
                        }
                    }
                    
                case .failure(let error):
                    print("An error occurred: \(error.localizedDescription)")
                }
            }
        
        mapView.mapboxMap.queryRenderedFeatures(
            with: tapPoint,
            options: RenderedQueryOptions(layerIds: ["pois"], filter: nil)) { [weak self] result in
                
                guard let self = self else { return }
                
                switch result {
                case .success(let queriedfeatures):
                    
                    if let feature = queriedfeatures.first?.queriedFeature.feature,
                       case .string(let name) = feature.properties?["name"],
                       case .string(let googleUrl) = feature.properties?["googleUrl"],
                       case .string(let type) = feature.properties?["type"],
                       case .point(let point) = feature.geometry
                    {
                        if (self.mapView.mapboxMap.cameraState.zoom >= 12 && type == "trainstation") || (self.mapView.mapboxMap.cameraState.zoom >= 14) {
                            self.delegate?.selectPoi(name: name, location: point.coordinates, googleUrl: googleUrl)
                        }
                    }
                case .failure(let error):
                    print("An error occurred: \(error.localizedDescription)")
                }
            }
        
        
        mapView.mapboxMap.queryRenderedFeatures(
            with: CGRect(x: tapPoint.x-16, y: tapPoint.y-16, width: 32, height: 32), // we use rect to avoid a weird bug with dynamic circle radius not triggering taps
            options: RenderedQueryOptions(layerIds: ["problems", "problems-names"], filter: nil)) { [weak self] result in
                
                guard let self = self else { return }
                
                if self.mapView.mapboxMap.cameraState.zoom < 19 { return }
                
                switch result {
                case .success(let queriedfeatures):
                    
                    let sortedFeatures = getSortedFeaturesByDistance(from: tapPoint, for: queriedfeatures)
                    
                    let sortedProblems = sortedFeatures.compactMap { feature in
                        if case .number(let id) = feature.properties?["id"] {
                            return Int(id)
                        }
                        return nil
                    }.compactMap { Problem.load(id: $0) }
                    
                    if let first = sortedProblems.first {
                        self.delegate?.selectProblem(id: first.id)
                        self.setProblemAsSelected(problemFeatureId: String(first.id))
                        
                        // if problem is hidden by the bottom sheet
                        if tapPoint.y >= (self.mapView.bounds.height/2 - 40) {
                            if let feature = sortedFeatures.first, case .point(let point) = feature.geometry {
                                
                                let cameraOptions = CameraOptions(
                                    center: point.coordinates,
                                    padding: self.safePaddingForBottomSheet
                                )
                                self.easeTo(cameraOptions)
                            }
                        }
                    }
                    else {
                        // TODO: make it more explicit that this works only at a certain zoom level
                        self.unselectPreviousProblem()
                        self.delegate?.dismissProblemDetails()
                    }
                case .failure(let error):
                    print("An error occurred: \(error.localizedDescription)")
                }
            }
        
        // TODO: make this DRY with problems layer
        // Note: I already tried using the same query for both problems and circuit-problems layer, but taps work better with tapPoint than with a rect => I prefered to keep a tapPoint for circuit-problem
        // Careful: the order between problems and circuit problems is important!
        mapView.mapboxMap.queryRenderedFeatures(
            with: tapPoint,
            options: RenderedQueryOptions(layerIds: ["circuit-problems"], filter: nil)) { [weak self] result in
                
                guard let self = self else { return }
                
                if self.mapView.mapboxMap.cameraState.zoom < 19 { return }
                
                switch result {
                case .success(let queriedfeatures):
                    
                    if let feature = queriedfeatures.first?.queriedFeature.feature,
                       case .number(let id) = feature.properties?["id"],
                       case .point(let point) = feature.geometry
                    {
                        self.delegate?.selectProblem(id: Int(id))
                        self.setProblemAsSelected(problemFeatureId: String(Int(id)))
                        
                        // if problem is hidden by the bottom sheet
                        if tapPoint.y >= (self.mapView.bounds.height/2 - 40) {
                            
                            let cameraOptions = CameraOptions(
                                center: point.coordinates,
                                padding: self.safePaddingForBottomSheet
                            )
                            self.easeTo(cameraOptions)
                        }
                    }
                case .failure(let error):
                    print("An error occurred: \(error.localizedDescription)")
                }
            }
    }

    #if DEVELOPMENT
    // Map Maker picker mode: a tap reports the nearest problem (if any) to the
    // delegate, which toggles it in TopoEntry.problems. No camera move, no
    // problem-details sheet, no feature-state highlight.
    private func findProblemForPicking(tapPoint: CGPoint) {
        guard mapView.mapboxMap.cameraState.zoom >= 19 else { return }

        // Try the regular problems layer first (32x32 hit rect to match findFeatures)
        mapView.mapboxMap.queryRenderedFeatures(
            with: CGRect(x: tapPoint.x - 16, y: tapPoint.y - 16, width: 32, height: 32),
            options: RenderedQueryOptions(layerIds: ["problems", "problems-names"], filter: nil)
        ) { [weak self] result in
            guard let self = self, case .success(let queriedfeatures) = result else { return }
            let sortedFeatures = getSortedFeaturesByDistance(from: tapPoint, for: queriedfeatures)
            if let firstId = sortedFeatures.compactMap({ feature -> Int? in
                if case .number(let id) = feature.properties?["id"] { return Int(id) }
                return nil
            }).first {
                self.delegate?.selectProblem(id: firstId)
                return
            }
            // Fall back to circuit-problems layer
            self.mapView.mapboxMap.queryRenderedFeatures(
                with: tapPoint,
                options: RenderedQueryOptions(layerIds: ["circuit-problems"], filter: nil)
            ) { [weak self] result in
                guard let self = self, case .success(let queriedfeatures) = result else { return }
                if let feature = queriedfeatures.first?.queriedFeature.feature,
                   case .number(let id) = feature.properties?["id"] {
                    self.delegate?.selectProblem(id: Int(id))
                }
            }
        }
    }

    // MARK: - Boulder draw mode (Map Maker)

    /// Adds the empty GeoJSON sources + render layers for the in-progress
    /// boulder polygon. Called every time the style is (re)loaded so the
    /// overlay survives dark/light switches and Metal context resets.
    func setupBoulderDrawSourcesAndLayers() {
        do {
            // Sources
            if !mapView.mapboxMap.sourceExists(withId: boulderDrawPolygonSourceId) {
                var poly = GeoJSONSource(id: boulderDrawPolygonSourceId)
                poly.data = .featureCollection(FeatureCollection(features: []))
                try mapView.mapboxMap.addSource(poly)
            }
            if !mapView.mapboxMap.sourceExists(withId: boulderDrawVerticesSourceId) {
                var verts = GeoJSONSource(id: boulderDrawVerticesSourceId)
                verts.data = .featureCollection(FeatureCollection(features: []))
                try mapView.mapboxMap.addSource(verts)
            }

            // Layers — fill, then stroke, then vertex circles on top.
            let strokeColor = UIColor(resource: .appGreen)

            if !mapView.mapboxMap.layerExists(withId: boulderDrawFillLayerId) {
                var fill = FillLayer(id: boulderDrawFillLayerId, source: boulderDrawPolygonSourceId)
                fill.fillColor = .constant(StyleColor(strokeColor.withAlphaComponent(0.18)))
                fill.fillOutlineColor = .constant(StyleColor(strokeColor))
                try mapView.mapboxMap.addLayer(fill)
            }
            if !mapView.mapboxMap.layerExists(withId: boulderDrawStrokeLayerId) {
                var stroke = LineLayer(id: boulderDrawStrokeLayerId, source: boulderDrawPolygonSourceId)
                stroke.lineColor = .constant(StyleColor(strokeColor))
                stroke.lineWidth = .constant(2.5)
                stroke.lineCap = .constant(.round)
                stroke.lineJoin = .constant(.round)
                try mapView.mapboxMap.addLayer(stroke)
            }
            if !mapView.mapboxMap.layerExists(withId: boulderDrawVerticesLayerId) {
                var verts = CircleLayer(id: boulderDrawVerticesLayerId, source: boulderDrawVerticesSourceId)
                verts.circleRadius = .constant(10.0)
                verts.circleColor = .constant(StyleColor(UIColor.white))
                verts.circleStrokeWidth = .constant(2.5)
                verts.circleStrokeColor = .constant(StyleColor(strokeColor))
                verts.circleEmissiveStrength = .constant(0.9)
                try mapView.mapboxMap.addLayer(verts)
            }
            if !mapView.mapboxMap.layerExists(withId: boulderDrawVertexLabelsLayerId) {
                var labels = SymbolLayer(id: boulderDrawVertexLabelsLayerId, source: boulderDrawVerticesSourceId)
                labels.textField = .expression(Exp(.toString) { Exp(.get) { "index" } })
                labels.textSize = .constant(11)
                labels.textColor = .constant(StyleColor(strokeColor))
                labels.textAllowOverlap = .constant(true)
                labels.textIgnorePlacement = .constant(true)
                labels.textFont = .constant(["Open Sans Semibold", "Arial Unicode MS Bold"])
                try mapView.mapboxMap.addLayer(labels)
            }
        } catch {
            print("Boulder draw layer setup error:", error)
        }
    }

    /// Refresh the polygon + vertex sources from the current vertex list.
    /// `vertices` is an array of `(id, coord)` to keep the controller free
    /// of the BoulderVertex type (which only exists in DEV).
    func updateBoulderDrawGeometry(vertexIds: [String], coordinates: [CLLocationCoordinate2D]) {
        precondition(vertexIds.count == coordinates.count)

        // Vertex points (index is 1-based for the user-visible label)
        let pointFeatures: [Feature] = zip(vertexIds, coordinates).enumerated().map { (idx, pair) in
            let (id, coord) = pair
            var f = Feature(geometry: .point(Point(coord)))
            f.identifier = .string(id)
            f.properties = [
                "id": .string(id),
                "index": .number(Double(idx + 1)),
            ]
            return f
        }
        let pointsCollection = FeatureCollection(features: pointFeatures)

        // Polygon ring (or polyline if fewer than 3 vertices, point if 1)
        var polyFeatures: [Feature] = []
        if coordinates.count >= 3 {
            let ring = coordinates + [coordinates[0]]
            polyFeatures = [Feature(geometry: .polygon(Polygon([ring])))]
        } else if coordinates.count == 2 {
            polyFeatures = [Feature(geometry: .lineString(LineString(coordinates)))]
        } else if coordinates.count == 1 {
            polyFeatures = [Feature(geometry: .point(Point(coordinates[0])))]
        }
        let polyCollection = FeatureCollection(features: polyFeatures)

        do {
            try mapView.mapboxMap.updateGeoJSONSource(
                withId: boulderDrawPolygonSourceId,
                geoJSON: .featureCollection(polyCollection)
            )
            try mapView.mapboxMap.updateGeoJSONSource(
                withId: boulderDrawVerticesSourceId,
                geoJSON: .featureCollection(pointsCollection)
            )
        } catch {
            print("Boulder draw geometry update error:", error)
        }
    }

    /// Adds the source + render layers for the persistent "saved boulders"
    /// overlay. Sits below the in-progress draw layers so a freshly-saved
    /// polygon can be redrawn from disk without a visible flicker.
    func setupSavedBouldersSourceAndLayers() {
        do {
            if !mapView.mapboxMap.sourceExists(withId: savedBouldersSourceId) {
                var src = GeoJSONSource(id: savedBouldersSourceId)
                src.data = .featureCollection(FeatureCollection(features: []))
                try mapView.mapboxMap.addSource(src)
            }
            if !mapView.mapboxMap.sourceExists(withId: savedBouldersVerticesSourceId) {
                var src = GeoJSONSource(id: savedBouldersVerticesSourceId)
                src.data = .featureCollection(FeatureCollection(features: []))
                try mapView.mapboxMap.addSource(src)
            }

            let strokeColor = UIColor(resource: .appGreen)

            if !mapView.mapboxMap.layerExists(withId: savedBouldersFillLayerId) {
                var fill = FillLayer(id: savedBouldersFillLayerId, source: savedBouldersSourceId)
                fill.fillColor = .constant(StyleColor(strokeColor.withAlphaComponent(0.22)))
                fill.fillOutlineColor = .constant(StyleColor(strokeColor))
                // Insert below the in-progress fill so the active drawing
                // visually sits on top.
                if mapView.mapboxMap.layerExists(withId: boulderDrawFillLayerId) {
                    try mapView.mapboxMap.addLayer(fill, layerPosition: .below(boulderDrawFillLayerId))
                } else {
                    try mapView.mapboxMap.addLayer(fill)
                }
            }
            if !mapView.mapboxMap.layerExists(withId: savedBouldersStrokeLayerId) {
                var stroke = LineLayer(id: savedBouldersStrokeLayerId, source: savedBouldersSourceId)
                stroke.lineColor = .constant(StyleColor(strokeColor))
                stroke.lineWidth = .constant(2.0)
                stroke.lineCap = .constant(.round)
                stroke.lineJoin = .constant(.round)
                if mapView.mapboxMap.layerExists(withId: boulderDrawStrokeLayerId) {
                    try mapView.mapboxMap.addLayer(stroke, layerPosition: .below(boulderDrawStrokeLayerId))
                } else {
                    try mapView.mapboxMap.addLayer(stroke)
                }
            }
            // Vertex circles for saved boulders (shown only when zoomed in
            // enough to be useful — a low zoom would clutter the map).
            if !mapView.mapboxMap.layerExists(withId: savedBouldersVerticesLayerId) {
                var verts = CircleLayer(id: savedBouldersVerticesLayerId, source: savedBouldersVerticesSourceId)
                verts.minZoom = 17
                verts.circleRadius = .constant(9.0)
                verts.circleColor = .constant(StyleColor(UIColor.white))
                verts.circleStrokeWidth = .constant(2.0)
                verts.circleStrokeColor = .constant(StyleColor(strokeColor))
                verts.circleEmissiveStrength = .constant(0.9)
                if mapView.mapboxMap.layerExists(withId: boulderDrawVerticesLayerId) {
                    try mapView.mapboxMap.addLayer(verts, layerPosition: .below(boulderDrawVerticesLayerId))
                } else {
                    try mapView.mapboxMap.addLayer(verts)
                }
            }
            if !mapView.mapboxMap.layerExists(withId: savedBouldersVertexLabelsLayerId) {
                var labels = SymbolLayer(id: savedBouldersVertexLabelsLayerId, source: savedBouldersVerticesSourceId)
                labels.minZoom = 17
                labels.textField = .expression(Exp(.toString) { Exp(.get) { "index" } })
                labels.textSize = .constant(11)
                labels.textColor = .constant(StyleColor(strokeColor))
                labels.textAllowOverlap = .constant(true)
                labels.textIgnorePlacement = .constant(true)
                labels.textFont = .constant(["Open Sans Semibold", "Arial Unicode MS Bold"])
                if mapView.mapboxMap.layerExists(withId: boulderDrawVertexLabelsLayerId) {
                    try mapView.mapboxMap.addLayer(labels, layerPosition: .below(boulderDrawVertexLabelsLayerId))
                } else {
                    try mapView.mapboxMap.addLayer(labels)
                }
            }
        } catch {
            print("Saved boulders layer setup error:", error)
        }
    }

    /// Show or hide every layer that draws saved boulders (polygon fill,
    /// stroke, vertex circles, vertex labels). Used to prevent visual
    /// duplication while the user is actively reshaping a polygon — the
    /// in-progress draw layers replace the saved view.
    func setSavedBouldersHidden(_ hidden: Bool) {
        let value = hidden ? "none" : "visible"
        for id in [
            savedBouldersFillLayerId,
            savedBouldersStrokeLayerId,
            savedBouldersVerticesLayerId,
            savedBouldersVertexLabelsLayerId,
        ] {
            try? mapView.mapboxMap.setLayerProperty(
                for: id,
                property: "visibility",
                value: value
            )
        }
    }

    /// Re-reads every saved boulder JSON and pushes the polygons to the
    /// "saved boulders" source. Each feature carries a `filename` property
    /// so a hit-test can map back to the on-disk record for editing.
    /// Called on style-load and after every save.
    func refreshSavedBoulders() {
        let saved = BoulderLibrary.loadAll()

        let polyFeatures: [Feature] = saved.map { b in
            var f = Feature(geometry: .polygon(Polygon([b.ring])))
            f.properties = ["filename": .string(b.filename)]
            return f
        }
        let polyCollection = FeatureCollection(features: polyFeatures)

        // Each vertex carries its parent filename + 1-based index for the
        // numbered label. Flatten across all saved boulders into one source.
        var vertexFeatures: [Feature] = []
        for b in saved {
            for (i, coord) in b.vertices.enumerated() {
                var f = Feature(geometry: .point(Point(coord)))
                f.properties = [
                    "filename": .string(b.filename),
                    "index": .number(Double(i + 1)),
                ]
                vertexFeatures.append(f)
            }
        }
        let vertexCollection = FeatureCollection(features: vertexFeatures)

        do {
            try mapView.mapboxMap.updateGeoJSONSource(
                withId: savedBouldersSourceId,
                geoJSON: .featureCollection(polyCollection)
            )
            try mapView.mapboxMap.updateGeoJSONSource(
                withId: savedBouldersVerticesSourceId,
                geoJSON: .featureCollection(vertexCollection)
            )
        } catch {
            print("refreshSavedBoulders update error:", error)
        }
    }

    /// Long-press over a vertex (in draw mode) starts a drag. Subsequent
    /// .changed events stream the new coord to the delegate; .ended/.cancelled
    /// re-enables map panning.
    @objc private func handleVertexDrag(_ gesture: UILongPressGestureRecognizer) {
        guard drawMode else { return }
        let touchPoint = gesture.location(in: mapView)

        switch gesture.state {
        case .began:
            mapView.mapboxMap.queryRenderedFeatures(
                with: CGRect(x: touchPoint.x - 22, y: touchPoint.y - 22, width: 44, height: 44),
                options: RenderedQueryOptions(layerIds: [boulderDrawVerticesLayerId], filter: nil)
            ) { [weak self] result in
                guard let self = self else { return }
                if case .success(let features) = result,
                   let f = features.first?.queriedFeature.feature,
                   case .string(let id) = f.properties?["id"] {
                    self.draggingVertexId = id
                    // Disable map pan while dragging so the touch follows the
                    // finger instead of scrolling the map underneath.
                    self.mapView.gestures.options.panEnabled = false
                }
            }
        case .changed:
            guard let id = draggingVertexId else { return }
            let coord = mapView.mapboxMap.coordinate(for: touchPoint)
            delegate?.moveBoulderVertex(vertexId: id, to: coord)
        case .ended, .cancelled, .failed:
            draggingVertexId = nil
            mapView.gestures.options.panEnabled = true
        default:
            break
        }
    }

    /// Tap dispatch in draw mode:
    ///   1. Hit-test in-progress vertex circles → tap on a vertex deletes it.
    ///   2. If the in-progress polygon is empty, hit-test saved boulder
    ///      fills → tap on a saved boulder loads it for editing.
    ///   3. Otherwise, add a vertex at the tap.
    private func handleBoulderDrawTap(tapPoint: CGPoint) {
        mapView.mapboxMap.queryRenderedFeatures(
            with: CGRect(x: tapPoint.x - 22, y: tapPoint.y - 22, width: 44, height: 44),
            options: RenderedQueryOptions(layerIds: [boulderDrawVerticesLayerId], filter: nil)
        ) { [weak self] result in
            guard let self = self else { return }
            if case .success(let features) = result,
               let f = features.first?.queriedFeature.feature,
               case .string(let id) = f.properties?["id"] {
                self.delegate?.removeBoulderVertex(vertexId: id)
                return
            }
            // No vertex hit. If we have nothing being drawn yet, treat a tap
            // on a saved boulder as a request to edit it.
            if self.currentDrawVertexCount == 0 {
                self.mapView.mapboxMap.queryRenderedFeatures(
                    with: tapPoint,
                    options: RenderedQueryOptions(layerIds: [self.savedBouldersFillLayerId], filter: nil)
                ) { [weak self] result in
                    guard let self = self else { return }
                    if case .success(let features) = result,
                       let f = features.first?.queriedFeature.feature,
                       case .string(let filename) = f.properties?["filename"] {
                        self.delegate?.editSavedBoulder(filename: filename)
                        return
                    }
                    let coord = self.mapView.mapboxMap.coordinate(for: tapPoint)
                    self.delegate?.addBoulderVertex(coord: coord)
                }
                return
            }
            let coord = self.mapView.mapboxMap.coordinate(for: tapPoint)
            self.delegate?.addBoulderVertex(coord: coord)
        }
    }
    #endif

    func inferAreaFromMap() {
        if(!flyinToSomething) {
            
            let zoom = Exp(.gt) {
                Exp(.zoom)
                14.5
            }
            
            let width = mapView.frame.width/4
            let rect = CGRect(x: mapView.center.x - width/2, y: mapView.center.y - width/2 + safePaddingYForAreaDetector, width: width, height: width)
            
            //            var debugView = UIView(frame: rect)
            //            debugView.backgroundColor = .red
            //            mapView.addSubview(debugView)
            
            mapView.mapboxMap.queryRenderedFeatures(
                with: rect,
                options: RenderedQueryOptions(layerIds: ["areas-hulls"], filter: zoom)) { [weak self] result in
                    
                    guard let self = self else { return }
                    
                    switch result {
                    case .success(let queriedfeatures):
                        
                        if let feature = queriedfeatures.first?.queriedFeature.feature,
                           case .number(let id) = feature.properties?["areaId"]
                        {
                            self.delegate?.selectArea(id: Int(id))
                        }
                    case .failure(_):
                        break
                    }
                }
            
            if(mapView.mapboxMap.cameraState.zoom < 14.5) {
                delegate?.unselectArea()
            }
        }
    }
    
    func inferClusterFromMap() {
        if(!flyinToSomething) {
            
            let zoom = Exp(.gte) {
                Exp(.zoom)
                12
            }
            
            let width = mapView.frame.width/4
            let rect = CGRect(x: mapView.center.x - width/2, y: mapView.center.y - width/2 + safePaddingYForAreaDetector, width: width, height: width)
            
//                                    var debugView = UIView(frame: rect)
//                                    debugView.backgroundColor = .blue
//                                    mapView.addSubview(debugView)
            
            mapView.mapboxMap.queryRenderedFeatures(
                with: rect,
                options: RenderedQueryOptions(layerIds: ["clusters-hulls"], filter: zoom)) { [weak self] result in
                    
                    guard let self = self else { return }
                    
                    switch result {
                    case .success(let queriedfeatures):
                        
                        if let feature = queriedfeatures.first?.queriedFeature.feature,
                           case .number(let id) = feature.properties?["clusterId"]
                        {
                            self.delegate?.selectCluster(id: Int(id))
                        }
                    case .failure(_):
                        break
                    }
                }
            
            
            if(mapView.mapboxMap.cameraState.zoom < 11) {
                delegate?.unselectCluster()
            }
        }
    }
    
    private var favorites: [Favorite] {
        let context = (UIApplication.shared.delegate as! AppDelegate).persistentContainer.viewContext
        
        do {
            let fetchRequest = Favorite.fetchRequest()
            return try context.fetch(fetchRequest)
        } catch {
            return []
        }
    }
    
    private var ticks: [Tick] {
        let context = (UIApplication.shared.delegate as! AppDelegate).persistentContainer.viewContext
        
        do {
            let fetchRequest = Tick.fetchRequest()
            return try context.fetch(fetchRequest)
        } catch {
            return []
        }
    }
    
    private var favoritesNotTicked: Set<Int> {
        Set(favorites.map{ Int($0.problemId) }).subtracting(ticks.map{ Int($0.problemId) })
    }

    func applyFilters(_ filters: Filters) {
        currentFilters = filters
        
        do {
            let gradeMin = filters.gradeRange?.min ?? Grade.min
            let gradeMax = filters.gradeRange?.max ?? Grade.max
            
            let gradesArray = (gradeMin...gradeMax).map{ $0.string }
            
            try ["problems", "problems-texts", "problems-names", "problems-names-antioverlap"].forEach { layerId in
                try mapView.mapboxMap.updateLayer(withId: layerId, type: CircleLayer.self) { layer in
                    let gradeFilter = Exp(.match) {
                        Exp(.get) { "grade" }
                        gradesArray
                        true
                        false
                    }
                    
                    let popularFilter = Exp(.get) { "featured" }
                    
                    let favoriteFilter = Exp(.inExpression) {
                        Exp(.get) { "id" }
                        favoritesNotTicked.map{Double($0)}
                    }
                    
                    let tickFilter = Exp(.inExpression) {
                        Exp(.get) { "id" }
                        ticks.map{Double($0.problemId)}
                    }
                    
                    layer.filter = Exp(.all) {
                        gradeFilter
                        filters.popular ? popularFilter : Exp(.literal) { true }
                        filters.favorite ? favoriteFilter : Exp(.literal) { true }
                        filters.ticked ? tickFilter : Exp(.literal) { true }
                    }
                }
            }
            
            try ["problems-names", "problems-names-antioverlap"].forEach { layerId in
                try mapView.mapboxMap.updateLayer(withId: layerId, type: SymbolLayer.self) { layer in
                    let visibility = (filters.popular || filters.favorite || filters.ticked) ? Visibility.visible : Visibility.none
                    layer.visibility = .constant(visibility)
                }
            }
 
        } catch {
            print("Ran into an error updating the layer: \(error)")
        }
    }
    
    func centerOnProblem(_ problem: Problem) {
        flyTo(CameraOptions(
            center: problem.coordinate,
            padding: safePaddingForBottomSheet,
            zoom: 20
        ))
    }
    
    func centerOnArea(_ area: Area) {
        let coords = [
            CLLocationCoordinate2D(latitude: area.southWestLat, longitude: area.southWestLon),
            CLLocationCoordinate2D(latitude: area.northEastLat, longitude: area.northEastLon)
        ]
        
        if let cameraOptions = self.cameraOptionsFor(coords, minZoom: 15) {
            flyTo(cameraOptions)
        }
    }
    
    func centerOnCurrentLocation() {
        if let location = mapView.location.latestLocation {
            
            let fontainebleauBounds = CoordinateBounds(
                southwest: CLLocationCoordinate2D(latitude: 48.241596, longitude: 2.3936456),
                northeast: CLLocationCoordinate2D(latitude: 48.5075073, longitude: 2.7616875)
            )
            
            let currentZoomLevel = mapView.mapboxMap.cameraState.zoom
            
            if fontainebleauBounds.contains(forPoint: location.coordinate, wrappedCoordinates: false) {
                let cameraOptions = CameraOptions(
                    center: location.coordinate,
                    padding: safePadding,
                    zoom: max(currentZoomLevel, 17)
                )
                
                flyTo(cameraOptions)
            }
            else {
                let bounds = fontainebleauBounds.extend(forPoint: location.coordinate)
                
                let coords = [bounds.southwest, bounds.northeast]
                
                if let cameraOptions = self.cameraOptionsFor(coords) {
                    flyTo(cameraOptions)
                }
            }
        }
    }
    
    func centerOnCircuit(_ circuit: Circuit) {
        let coords = [
            CLLocationCoordinate2D(latitude: circuit.southWestLat, longitude: circuit.southWestLon),
            CLLocationCoordinate2D(latitude: circuit.northEastLat, longitude: circuit.northEastLon)
        ]
        
        if let cameraOptions = self.cameraOptionsFor(coords, minZoom: 15) {
            flyTo(cameraOptions)
        }
    }
    
    func centerOnBoulderCoordinates(_ coordinates: [CLLocationCoordinate2D]) {
        guard !coordinates.isEmpty else { return }
        
        let padding = safePaddingForBoulder
        let paddedRect = CGRect(
            x: padding.left,
            y: padding.top,
            width: view.bounds.width - padding.left - padding.right,
            height: view.bounds.height - padding.top - padding.bottom
        )
        
        // Check if all coordinates are already visible within the padded area
        let allVisible = coordinates.allSatisfy { coord in
            let point = mapView.mapboxMap.point(for: coord)
            return paddedRect.contains(point)
        }
        
        guard !allVisible else { return }
        
        let currentZoom = mapView.mapboxMap.cameraState.zoom
        
        // Fit all coordinates within the padded area, keeping the current zoom
        // unless it's too tight (maxZoom caps the zoom so it only pans or zooms out).
        if let fittedCamera = try? mapView.mapboxMap.camera(
            for: coordinates,
            camera: CameraOptions(padding: UIEdgeInsets(), bearing: 0, pitch: 0),
            coordinatesPadding: padding,
            maxZoom: currentZoom,
            offset: nil
        ) {
            flyTo(fittedCamera)
        }
    }
    
    func setCircuitAsSelected(circuit: Circuit) {
        currentCircuit = circuit
        
        do {
            try ["circuits"].forEach { layerId in
                try mapView.mapboxMap.updateLayer(withId: layerId, type: LineLayer.self) { layer in
                    layer.filter = Exp(.match) {
                        Exp(.get) { "id" }
                        [Double(circuit.id)]
                        true
                        false
                    }
                    layer.visibility = .constant(.visible)
                }
            }
            
            try ["circuit-problems", "circuit-problems-texts"].forEach { layerId in
                try mapView.mapboxMap.updateLayer(withId: layerId, type: CircleLayer.self) { layer in
                    layer.filter = Exp(.match) {
                        Exp(.get) { "circuitId" }
                        [Double(circuit.id)]
                        true
                        false
                    }
                    layer.visibility = .constant(.visible)
                }
            }
 
        } catch {
            print("Ran into an error updating the layer: \(error)")
        }
    }
    
    func unselectCircuit() {
        currentCircuit = nil
        
        do {
            try ["circuits"].forEach { layerId in
                try mapView.mapboxMap.updateLayer(withId: layerId, type: LineLayer.self) { layer in
                    layer.visibility = .constant(.none)
                }
            }
            
            try ["circuit-problems", "circuit-problems-texts"].forEach { layerId in
                try mapView.mapboxMap.updateLayer(withId: layerId, type: CircleLayer.self) { layer in
                    layer.visibility = .constant(.none)
                }
            }
 
        } catch {
            print("Ran into an error updating the layer: \(error)")
        }
    }
    
    private var previouslyTappedProblemId: String = ""
    private var previouslySelectedTopoIds: [String] = []
    /// Pre-cached problem IDs for the currently selected topo.
    /// Set from MapboxView using cached data – avoids SQLite in the hot path.
    var selectedTopoProblemIds: [String] = []
    
    func setProblemAsSelected(problemFeatureId: String) {
        // Unselect previously selected topo problems
        unselectPreviousTopoProblems()
        
        self.mapView.mapboxMap.setFeatureState(sourceId: "problems",
                                               sourceLayerId: problemsSourceLayerId,
                                               featureId: problemFeatureId,
                                               state: ["selected": true]) { result in
            
        }
        
        if problemFeatureId != self.previouslyTappedProblemId {
            unselectPreviousProblem()
        }
        
        self.previouslyTappedProblemId = problemFeatureId
        
        // Also select all sibling problems on the same topo (using pre-cached IDs)
        if !selectedTopoProblemIds.isEmpty {
            var selectedIds: [String] = []
            
            for featureId in selectedTopoProblemIds {
                if featureId != problemFeatureId {
                    self.mapView.mapboxMap.setFeatureState(sourceId: "problems",
                                                           sourceLayerId: problemsSourceLayerId,
                                                           featureId: featureId,
                                                           state: ["selected": true]) { result in
                    }
                    selectedIds.append(featureId)
                }
            }
            
            previouslySelectedTopoIds = selectedIds
        }
    }
    
    func unselectPreviousProblem() {
        if(self.previouslyTappedProblemId != "") {
            self.mapView.mapboxMap.setFeatureState(sourceId: "problems",
                                                   sourceLayerId: problemsSourceLayerId,
                                                   featureId: self.previouslyTappedProblemId,
                                                   state: ["selected": false]) { result in
                
            }
        }
    }
    
    private func unselectPreviousTopoProblems() {
        for featureId in previouslySelectedTopoIds {
            self.mapView.mapboxMap.setFeatureState(sourceId: "problems",
                                                   sourceLayerId: problemsSourceLayerId,
                                                   featureId: featureId,
                                                   state: ["selected": false]) { result in
            }
        }
        previouslySelectedTopoIds = []
    }
    
    func flyTo(_ cameraOptions: CameraOptions) {
        flyinToSomething = true
        
        mapView.camera.fly(to: cameraOptions, duration: flyinDuration) { _ in
            self.flyinToSomething = false
            
            // hack to make sure we detect the right cluster and area after the fly animation is done
            // we do this because sometimes the area and/or cluster are unselected by mistake because the inferArea/inferCluster funcs are called during a flying animation
            // we can probably remove it when we move to MapboxMap.isAnimationInProgress in v11
            self.triggerMapDetectors()
        }
    }
    
    func easeTo(_ cameraOptions: CameraOptions) {
        flyinToSomething = true
        mapView.camera.ease(to: cameraOptions, duration: flyinDuration) { _ in
            self.flyinToSomething = false
            
            // TODO: use the same hack as flyTo() ?
        }
    }
    
    func triggerMapDetectors() {
        // hack to make sure we detect the right cluster and area after the flying animation is done
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.inferAreaFromMap()
            self.inferClusterFromMap()
        }
    }
    
    var flyinToSomething = false // TODO: replace with MapboxMap.isAnimationInProgress in v11 (probably more reliable)
    let flyinDuration = 0.5
    let safePadding = UIEdgeInsets(top: 180, left: 20, bottom: 180, right: 20)
    var safePaddingForBottomSheet : UIEdgeInsets {
        UIEdgeInsets(top: 100, left: 0, bottom: view.bounds.height/2 + 40, right: 0)
    }
    var safePaddingForBoulder: UIEdgeInsets {
        UIEdgeInsets(top: 100, left: 20, bottom: view.bounds.height/2 + 40, right: 20)
    }
    let safePaddingYForAreaDetector : CGFloat = 30 // TODO: check if it works
    
    private func coordinatesFrom(southWestLat: String, southWestLon: String, northEastLat: String, northEastLon: String) -> [CLLocationCoordinate2D] {
        if let southWestLat = Double(southWestLat), let southWestLon = Double(southWestLon), let northEastLat = Double(northEastLat), let northEastLon = Double(northEastLon) {
            
            return [
                CLLocationCoordinate2D(latitude: southWestLat, longitude: southWestLon),
                CLLocationCoordinate2D(latitude: northEastLat, longitude: northEastLon),
            ]
        }
        
        return []
    }
    
    private func cameraOptionsFor(_ coordinates: [CLLocationCoordinate2D], minZoom: CGFloat? = nil) -> CameraOptions? {
        if var cameraOptions = try? self.mapView.mapboxMap.camera(
            for: coordinates,
            camera: CameraOptions(padding: UIEdgeInsets(), bearing: 0, pitch: 0),
            coordinatesPadding: self.safePadding,
            maxZoom: nil,
            offset: nil) {
            
            if let minZoom = minZoom {
                cameraOptions.zoom = max(minZoom, cameraOptions.zoom ?? 0)
            }
            
            return cameraOptions
        }
        
        return nil
    }
    
    private func getSortedFeaturesByDistance(from tapPoint: CGPoint, for features: [QueriedRenderedFeature]) -> [Feature] {
        let tapCoord = mapView.mapboxMap.coordinate(for: tapPoint)
        let tapLoc = CLLocation(latitude: tapCoord.latitude, longitude: tapCoord.longitude)
        
        let withDistances = features.compactMap { qf -> (QueriedRenderedFeature, CLLocationDistance)? in
            guard case let .point(ptCoords) = qf.queriedFeature.feature.geometry else { 
                return nil 
            }
            
            let featureLoc = CLLocation(
                latitude: ptCoords.coordinates.latitude, 
                longitude: ptCoords.coordinates.longitude
            )
            let distance = featureLoc.distance(from: tapLoc)
            return (qf, distance)
        }
        
        return withDistances.sorted { $0.1 < $1.1 }.map { $0.0.queriedFeature.feature }
    }
}

import CoreLocation

protocol MapBoxViewDelegate {
    func selectProblem(id: Int)
    func selectPoi(name: String, location: CLLocationCoordinate2D, googleUrl: String)
    func selectArea(id: Int)
    func selectCluster(id: Int)
    func unselectArea()
    func unselectCluster()
    func unselectCircuit()
    func cameraChanged(state: CameraState)
    func dismissProblemDetails()

    #if DEVELOPMENT
    func addBoulderVertex(coord: CLLocationCoordinate2D)
    func removeBoulderVertex(vertexId: String)
    func moveBoulderVertex(vertexId: String, to coord: CLLocationCoordinate2D)
    func editSavedBoulder(filename: String)
    #endif
}
