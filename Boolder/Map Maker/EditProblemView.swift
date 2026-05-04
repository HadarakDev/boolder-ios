//
//  EditProblemView.swift
//  Boolder
//
//  Originally created by Nicolas Mondollot on 08/01/2021.
//  Ported to TopoSud (DEVELOPMENT-only) from the legacy-map-maker branch.
//  Migrated to NavigationStack + .toolbar + \.dismiss.
//

#if DEVELOPMENT

import SwiftUI

struct EditProblemView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var managedObjectContext

    let problem: Problem

    @State var selectedSteepness: Steepness
    @State var selectedHeight: Double
    @State private var selectedLandingDifficulty: Difficulty = .easy
    @State private var selectedDescentDifficulty: Difficulty = .easy
    @State private var comments: String = ""

    private let store = MapMakerStore()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Steepness", selection: $selectedSteepness) {
                        ForEach(Steepness.allCases, id: \.self) { steepness in
                            Text(steepness.rawValue).tag(steepness)
                        }
                    }

                    VStack {
                        HStack {
                            Text("Height")
                            Spacer()
                            Text(String(format: "%.0f m", selectedHeight))
                                .foregroundColor(.gray)
                        }
                        Slider(value: $selectedHeight, in: 0...10, step: 1.0)
                    }

                    Picker("Landing", selection: $selectedLandingDifficulty) {
                        ForEach(Difficulty.allCases, id: \.self) { difficulty in
                            Text(difficulty.rawValue).tag(difficulty)
                        }
                    }

                    Picker("Descent", selection: $selectedDescentDifficulty) {
                        ForEach(Difficulty.allCases, id: \.self) { difficulty in
                            Text(difficulty.rawValue).tag(difficulty)
                        }
                    }
                }

                Section("Comments") {
                    TextEditor(text: $comments)
                }
            }
            .navigationTitle(problem.localizedName.isEmpty ? "Problem #\(problem.id)" : problem.localizedName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }

    // MARK: - Save

    private func save() {
        let record = ProblemJson(
            problemId: problem.id,
            steepness: selectedSteepness.rawValue,
            height: Int(selectedHeight),
            landingDifficulty: selectedLandingDifficulty.rawValue,
            descentDifficulty: selectedDescentDifficulty.rawValue,
            comments: comments
        )

        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = .prettyPrinted

        do {
            let jsonData = try jsonEncoder.encode(record)
            let filename = store.timestamp() + ".json"
            store.save(data: jsonData, directory: "problems", filename: filename)

            // Piggy-back on Tick to track edited problems on-device
            createTick()
        } catch {
            print("EditProblemView save error:", error)
        }
    }

    private func createTick() {
        let tick = Tick(context: managedObjectContext)
        tick.id = UUID()
        tick.problemId = Int64(problem.id)
        tick.createdAt = Date()

        do {
            try managedObjectContext.save()
        } catch {
            print("EditProblemView createTick error:", error)
        }
    }
}

enum Difficulty: String, CaseIterable {
    case easy
    case medium
    case hard
}

struct ProblemJson: Codable {
    var problemId: Int
    var steepness: String
    var height: Int
    var landingDifficulty: String
    var descentDifficulty: String
    var comments: String
}

#endif
