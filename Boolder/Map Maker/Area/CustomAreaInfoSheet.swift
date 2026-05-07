//
//  CustomAreaInfoSheet.swift
//  Boolder
//
//  Sheet that opens from the (i) button of the CustomAreaToolbar — lists
//  the climbing problems whose coordinates fall inside the area's
//  bounding box. Tapping a row opens the existing CustomProblemDetailsSheet.
//

#if DEVELOPMENT

import SwiftUI
import CoreLocation

struct CustomAreaInfoSheet: View {
    let area: SavedArea
    var onClose: () -> Void
    var onSelectProblem: (SavedProblem) -> Void

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(area.name.isEmpty ? area.filename : area.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { onClose() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var content: some View {
        let problems = problemsInside(area: area)
        let bouldersInside = bouldersInside(area: area)
        Form {
            Section("Summary") {
                LabeledContent("Boulders", value: "\(bouldersInside.count)")
                LabeledContent("Problems", value: "\(problems.count)")
            }

            if !problems.isEmpty {
                Section("Problems") {
                    ForEach(problems, id: \.filename) { p in
                        Button {
                            onSelectProblem(p)
                        } label: {
                            HStack {
                                ZStack {
                                    Circle()
                                        .stroke(Color("AppGreen"), lineWidth: 2)
                                        .background(Circle().fill(Color.white))
                                        .frame(width: 28, height: 28)
                                    Text(p.grade)
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(p.name.isEmpty ? "(no name)" : p.name)
                                        .foregroundColor(.primary)
                                    if let bid = p.boulderId {
                                        Text(bid)
                                            .font(.caption2.monospacedDigit())
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            } else {
                Section {
                    Text("No problem inside this area yet.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func problemsInside(area: SavedArea) -> [SavedProblem] {
        ProblemLibrary.loadAll().filter { p in
            isInsideBoundingBox(coord: p.coordinate, area: area)
        }
    }

    private func bouldersInside(area: SavedArea) -> [SavedBoulder] {
        BoulderLibrary.loadAll().filter { b in
            // A boulder counts as "inside" if any of its vertices is inside
            // the area's bounding box. Cheap approximation that's good
            // enough for V1 — the area polygon is much bigger than a rock.
            b.vertices.contains { isInsideBoundingBox(coord: $0, area: area) }
        }
    }

    private func isInsideBoundingBox(coord: CLLocationCoordinate2D, area: SavedArea) -> Bool {
        coord.latitude >= area.southWest.latitude
            && coord.latitude <= area.northEast.latitude
            && coord.longitude >= area.southWest.longitude
            && coord.longitude <= area.northEast.longitude
    }
}

#endif
