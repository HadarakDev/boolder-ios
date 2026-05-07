//
//  CustomProblemDetailsSheet.swift
//  Boolder
//
//  Read-only details for a saved (TopoSud-authored) problem. Shown when
//  the user taps a green pin on the map outside of any Map Maker mode.
//  DEVELOPMENT-only.
//

#if DEVELOPMENT

import SwiftUI

struct CustomProblemDetailsSheet: View {
    let filename: String
    var onClose: () -> Void
    var onEdit: () -> Void

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(filename)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { onClose() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            onEdit()
                        } label: {
                            Image(systemName: "pencil")
                        }
                    }
                }
        }
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private var content: some View {
        if let record = ProblemSaver.load(filename: filename),
           record.geometry.coordinates.count >= 2 {
            Form {
                Section("Name") {
                    Text(record.properties.name.isEmpty ? "(no name)" : record.properties.name)
                }
                Section("Grade") {
                    Text(record.properties.grade)
                        .font(.body.weight(.semibold))
                }
                Section("Position") {
                    Text(String(
                        format: "%.6f, %.6f",
                        record.geometry.coordinates[1],
                        record.geometry.coordinates[0]
                    ))
                    .font(.system(.footnote, design: .monospaced))
                    if let boulderId = record.properties.boulderId {
                        LabeledContent("Boulder", value: boulderId)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Not linked to a boulder")
                            .font(.footnote)
                            .foregroundColor(.orange)
                    }
                }
                if !record.properties.comments.isEmpty {
                    Section("Comments") {
                        Text(record.properties.comments)
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "Problem unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text("Couldn't read \(filename).")
            )
        }
    }
}

#endif
