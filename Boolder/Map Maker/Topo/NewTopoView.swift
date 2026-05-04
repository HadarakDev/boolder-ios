//
//  NewTopoView.swift
//  Boolder
//
//  Originally created by Nicolas Mondollot on 21/12/2020.
//  Ported to TopoSud (DEVELOPMENT-only) from the legacy-map-maker branch.
//  Migrated to NavigationStack + .toolbar + @Bindable.
//

#if DEVELOPMENT

import SwiftUI
import CoreLocation

struct NewTopoView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var managedObjectContext

    @Bindable var topoEntry: TopoEntry
    @State private var locationFetcher = LocationFetcher()
    @State private var presentImagePicker = false

    private let store = MapMakerStore()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sectionTitle("GPS")

                    VStack(alignment: .leading) {
                        Text(locationText)
                            .font(.system(size: 14, design: .monospaced))
                        Text(headingText)
                            .font(.system(size: 14, design: .monospaced))
                    }

                    sectionTitle("Photo")
                    photoButton

                    sectionTitle("Problems")
                    problemsSection

                    sectionTitle("Comments")
                    TextEditor(text: $topoEntry.comments)
                        .frame(height: 80)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(white: 0.9), lineWidth: 1)
                        )
                }
                .padding()
            }
            .navigationTitle("New Topo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        topoEntry.reset()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let photo = topoEntry.photo,
                           let location = topoEntry.location,
                           let heading = topoEntry.heading {
                            save(photo: photo, location: location, heading: heading)
                            topoEntry.reset()
                            dismiss()
                        }
                    }
                    .fontWeight(.bold)
                    .disabled(topoEntry.photo == nil || topoEntry.location == nil || topoEntry.heading == nil)
                }
            }
            .onAppear {
                UITextView.appearance().backgroundColor = .clear
                topoEntry.pickerModeEnabled = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    locationFetcher.start()
                }
            }
            .onDisappear { locationFetcher.stop() }
        }
    }

    // MARK: - Subviews

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.title).fontWeight(.bold)
    }

    private var photoButton: some View {
        Button {
            presentImagePicker = true
            // Snapshot the current best fix when opening the camera
            locationFetcher.stop()
            topoEntry.location = locationFetcher.location
            topoEntry.heading = locationFetcher.heading
        } label: {
            if let photo = topoEntry.photo {
                Image(uiImage: photo)
                    .resizable()
                    .aspectRatio(4/3, contentMode: .fit)
            } else {
                ZStack {
                    Color(white: 0.9)
                        .aspectRatio(4/3, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                    Image(systemName: "camera")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                }
            }
        }
        .fullScreenCover(isPresented: $presentImagePicker) {
            ImagePickerView(sourceType: .camera, selectedImage: $topoEntry.photo)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .ignoresSafeArea()
        }
    }

    private var problemsSection: some View {
        Group {
            if topoEntry.problems.isEmpty {
                Button {
                    dismiss()  // Return to map to pick problems
                } label: {
                    HStack { Text("Choose"); Spacer() }
                }
            } else {
                VStack {
                    HStack {
                        ForEach(topoEntry.problems) { problem in
                            ProblemCircleView(problem: problem)
                        }
                        Spacer()
                    }
                    Button {
                        topoEntry.problems = []
                    } label: {
                        HStack { Text("Reset"); Spacer() }
                    }
                }
            }
        }
    }

    // MARK: - Derived text

    var locationText: String {
        let displayed = topoEntry.location ?? locationFetcher.location
        guard let l = displayed else { return "Waiting..." }
        return String(
            format: "%.6f %.6f (±%.0fm)",
            l.coordinate.latitude,
            l.coordinate.longitude,
            l.horizontalAccuracy
        )
    }

    var headingText: String {
        let displayed = topoEntry.heading ?? locationFetcher.heading
        guard let h = displayed else { return "Waiting..." }
        return String(format: "%.1f° (±%.0f°)", h.trueHeading, h.headingAccuracy)
    }

    // MARK: - Save

    struct TopoJson: Codable {
        var latitude: Double
        var longitude: Double
        var altitude: Double
        var horizontalAccuracy: Double
        var verticalAccuracy: Double
        var heading: Double
        var headingAccuracy: Double
        var problem_ids: [Int]
        var comments: String
    }

    private func save(photo: UIImage, location: CLLocation, heading: CLHeading) {
        do {
            let timestamp = store.timestamp()

            let record = TopoJson(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitude: location.altitude,
                horizontalAccuracy: location.horizontalAccuracy,
                verticalAccuracy: location.verticalAccuracy,
                heading: heading.trueHeading,
                headingAccuracy: heading.headingAccuracy,
                problem_ids: topoEntry.problems.map { $0.id },
                comments: topoEntry.comments
            )

            let jsonEncoder = JSONEncoder()
            jsonEncoder.outputFormatting = .prettyPrinted

            store.save(
                data: try jsonEncoder.encode(record),
                directory: "topos",
                filename: timestamp + ".json"
            )

            if let jpeg = photo.jpegData(compressionQuality: 1.0) {
                store.save(data: jpeg, directory: "topos", filename: timestamp + ".jpg")
            }

            // Piggy-back on Favorite to track captured problems on-device
            for problem in topoEntry.problems {
                createFavorite(problem)
            }
        } catch {
            print("NewTopoView save error:", error)
        }
    }

    private func createFavorite(_ problem: Problem) {
        let favorite = Favorite(context: managedObjectContext)
        favorite.id = UUID()
        favorite.problemId = Int64(problem.id)
        favorite.createdAt = Date()

        do {
            try managedObjectContext.save()
        } catch {
            print("NewTopoView createFavorite error:", error)
        }
    }
}

#endif
