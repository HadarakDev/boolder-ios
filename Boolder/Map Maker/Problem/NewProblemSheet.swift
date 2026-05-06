//
//  NewProblemSheet.swift
//  Boolder
//
//  Sheet form shown after the user taps the map in problem-add mode.
//  Captures name + grade + comments and (when editing an existing record)
//  exposes a Delete button. DEVELOPMENT-only.
//

#if DEVELOPMENT

import SwiftUI

struct NewProblemSheet: View {
    @Bindable var entry: ProblemEntry
    var onSave: () -> Void
    var onCancel: () -> Void
    var onDelete: () -> Void

    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Position") {
                    if let coord = entry.pendingCoord {
                        Text(String(
                            format: "%.6f, %.6f",
                            coord.latitude,
                            coord.longitude
                        ))
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(.secondary)
                    }
                    if let boulderId = entry.boulderId {
                        LabeledContent("Boulder", value: boulderId)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Not linked to a boulder")
                            .font(.footnote)
                            .foregroundColor(.orange)
                    }
                }

                Section("Name") {
                    TextField("e.g. La Marie-Rose", text: $entry.name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                }

                Section("Grade") {
                    Picker("Grade", selection: $entry.grade) {
                        ForEach(Grade.grades, id: \.self) { g in
                            Text(g).tag(g)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 120)
                }

                Section("Comments") {
                    TextEditor(text: $entry.comments)
                        .frame(minHeight: 60)
                }

                if entry.editingFilename != nil {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete this problem")
                            }
                        }
                    }
                }
            }
            .navigationTitle(entry.editingFilename == nil ? "New problem" : "Edit problem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave() }
                        .fontWeight(.semibold)
                        .disabled(entry.pendingCoord == nil)
                }
            }
            .alert("Delete this problem?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { onDelete() }
            } message: {
                Text("The saved record will be removed permanently.")
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#endif
