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
    @Bindable var problemEntry: ProblemEntry
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
            if topoEntry.problems.isEmpty && topoEntry.customProblems.isEmpty {
                Button {
                    dismiss()  // Return to map to pick problems
                } label: {
                    HStack { Text("Choose"); Spacer() }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if !topoEntry.problems.isEmpty {
                        HStack {
                            ForEach(topoEntry.problems) { problem in
                                ProblemCircleView(problem: problem)
                            }
                            Spacer()
                        }
                    }
                    if !topoEntry.customProblems.isEmpty {
                        ForEach(topoEntry.customProblems, id: \.filename) { saved in
                            customProblemRow(saved)
                        }
                    }
                    Button {
                        topoEntry.problems = []
                        topoEntry.customProblems = []
                    } label: {
                        HStack { Text("Reset"); Spacer() }
                    }
                }
            }
        }
    }

    /// One row per picked custom problem: name + grade + a "📍 GPS" button
    /// that overwrites the problem's stored coordinate with the current
    /// best GPS fix from the LocationFetcher (the photographer is
    /// physically next to the rock at this point — much better than the
    /// initial tap-pose).
    private func customProblemRow(_ saved: SavedProblem) -> some View {
        HStack {
            Circle()
                .stroke(Color("AppGreen"), lineWidth: 2)
                .background(Circle().fill(Color.white))
                .frame(width: 22, height: 22)
                .overlay(Text(saved.grade).font(.system(size: 9)))
            VStack(alignment: .leading, spacing: 1) {
                Text(saved.name.isEmpty ? "(no name)" : saved.name)
                    .font(.subheadline)
                Text(String(format: "%.6f, %.6f", saved.coordinate.latitude, saved.coordinate.longitude))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                calibrateProblem(saved)
            } label: {
                Image(systemName: "location.fill.viewfinder")
                    .font(.body)
            }
            .buttonStyle(.borderless)
            .disabled(locationFetcher.location == nil)
        }
        .padding(.vertical, 4)
    }

    /// Overwrite a custom problem's stored coordinate with the current GPS
    /// fix and force the map to refresh from disk.
    private func calibrateProblem(_ saved: SavedProblem) {
        guard let loc = locationFetcher.location else { return }
        guard let record = ProblemSaver.load(filename: saved.filename) else { return }
        // Re-use the entry as a scratch buffer for ProblemSaver.save (which
        // reads its fields). We restore the picker state after.
        let backup = (
            problemEntry.pendingCoord,
            problemEntry.name,
            problemEntry.grade,
            problemEntry.comments,
            problemEntry.boulderId,
            problemEntry.editingFilename
        )
        problemEntry.pendingCoord = loc.coordinate
        problemEntry.name = record.properties.name
        problemEntry.grade = record.properties.grade
        problemEntry.comments = record.properties.comments
        problemEntry.boulderId = record.properties.boulderId
        problemEntry.editingFilename = saved.filename
        _ = ProblemSaver.save(entry: problemEntry)
        problemEntry.pendingCoord = backup.0
        problemEntry.name = backup.1
        problemEntry.grade = backup.2
        problemEntry.comments = backup.3
        problemEntry.boulderId = backup.4
        problemEntry.editingFilename = backup.5
        // Update the in-memory copy in topoEntry too so the row reflects
        // the new coord without needing to reopen the sheet.
        if let idx = topoEntry.customProblems.firstIndex(where: { $0.filename == saved.filename }) {
            topoEntry.customProblems[idx].coordinate = loc.coordinate
        }
        problemEntry.savedProblemsVersion += 1
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
        /// Filenames (relative to map-maker/problems/) of the TopoSud-authored
        /// problems associated with this topo. The pipeline resolves these
        /// to problem records when ingesting captures.
        var custom_problem_filenames: [String]
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
                custom_problem_filenames: topoEntry.customProblems.map { $0.filename },
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
