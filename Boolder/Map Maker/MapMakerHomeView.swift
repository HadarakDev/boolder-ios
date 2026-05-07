//
//  MapMakerHomeView.swift
//  Boolder
//
//  Hub for the TopoSud Map Maker (DEVELOPMENT-only). Entry point from the
//  "Dev" section of DiscoverView.
//

#if DEVELOPMENT

import SwiftUI

struct MapMakerHomeView: View {
    @State private var topoEntry = TopoEntry()
    @State private var problemEntry = ProblemEntry()
    @State private var presentNewTopo = false
    @State private var capturedCount: Int = 0

    var body: some View {
        Form {
            Section("Captures") {
                LabeledContent("Saved topos") {
                    Text("\(capturedCount)")
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }

                Button {
                    presentNewTopo = true
                } label: {
                    Label("New topo capture", systemImage: "camera.viewfinder")
                }
            }

            Section("Storage") {
                Text("Captures are saved to iCloud Documents under \"map-maker/\". Pull them off your Mac for processing into boolder.db.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Map Maker")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $presentNewTopo, onDismiss: refreshCount) {
            NewTopoView(topoEntry: topoEntry, problemEntry: problemEntry)
        }
        .onAppear(perform: refreshCount)
    }

    private func refreshCount() {
        let fm = FileManager.default
        let baseURL: URL = {
            if let iCloud = fm.url(forUbiquityContainerIdentifier: nil) {
                return iCloud.appendingPathComponent("Documents")
            }
            return fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }()
        let toposDir = baseURL.appendingPathComponent("map-maker/topos")
        let count = (try? fm.contentsOfDirectory(at: toposDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.count) ?? 0
        capturedCount = count
    }
}

#endif
