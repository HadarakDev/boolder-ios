//
//  AreaDrawOverlay.swift
//  Boolder
//
//  Top banner shown over the map while the user is authoring a climbing
//  area polygon. Mirrors BoulderDrawOverlay (long-press for GPS averaging,
//  Cancel / Delete / Save), but adds an inline name TextField since an
//  unnamed area is not very useful. DEVELOPMENT-only.
//

#if DEVELOPMENT

import SwiftUI
import CoreLocation

struct AreaDrawOverlay: View {
    @Bindable var entry: AreaDrawEntry
    @Bindable var averager: LocationAverager
    var onSave: () -> Void
    var onCancel: () -> Void
    var onDelete: () -> Void

    @State private var showDeleteConfirm = false
    private let averageWindow: TimeInterval = 5.0

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .overlay(alignment: .bottom) { Divider() }

            nameField
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .overlay(alignment: .bottom) { Divider() }

            Spacer()

            HStack(alignment: .bottom) {
                Spacer()
                gpsButton
                    .padding(.trailing, 24)
                    .padding(.bottom, 200)
            }
        }
        .allowsHitTesting(true)
        .onAppear { averager.startStreaming() }
        .onDisappear { averager.stopStreaming() }
        .alert("Delete this area?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { onDelete() }
        } message: {
            Text("The saved area polygon will be removed permanently.")
        }
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(role: .cancel) {
                averager.cancelCollection()
                onCancel()
            } label: {
                Text("Cancel").font(.body)
            }

            if entry.editingFilename != nil {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash").font(.body)
                }
                .tint(.red)
            }

            Spacer()

            VStack(spacing: 2) {
                Text("\(entry.vertices.count) vertex\(entry.vertices.count > 1 ? "es" : "")")
                    .font(.subheadline.weight(.semibold))
                Group {
                    if entry.isAveraging {
                        Text("Averaging GPS…")
                    } else if let acc = averager.liveLocation?.horizontalAccuracy, acc >= 0 {
                        Text(String(format: "GPS ±%.0f m", acc))
                    } else {
                        Text("Acquiring GPS…")
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                onSave()
            } label: {
                Text("Save").fontWeight(.semibold)
            }
            .disabled(entry.vertices.count < 3 || entry.isAveraging || entry.name.isEmpty)
        }
    }

    private var nameField: some View {
        HStack {
            Image(systemName: "tag")
                .foregroundColor(.secondary)
            TextField("Area name", text: $entry.name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
        }
    }

    private var gpsButton: some View {
        Button {
            guard !entry.isAveraging else { return }
            guard let loc = averager.liveLocation else { return }
            entry.vertices.append(BoulderVertex(
                latitude: loc.coordinate.latitude,
                longitude: loc.coordinate.longitude,
                horizontalAccuracy: loc.horizontalAccuracy,
                sampleCount: 1,
                source: .gps
            ))
        } label: {
            ZStack {
                Circle()
                    .fill(entry.isAveraging ? Color.orange : Color.purple)
                    .frame(width: 64, height: 64)
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                Image(systemName: entry.isAveraging ? "dot.radiowaves.left.and.right" : "scope")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.white)
            }
            .overlay(alignment: .bottom) {
                Text(entry.isAveraging ? "averaging…" : "tap = 1 / hold = avg")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
                    .offset(y: 22)
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in
                    guard !entry.isAveraging else { return }
                    entry.isAveraging = true
                    averager.collectAverage(over: averageWindow) { result, count in
                        entry.isAveraging = false
                        guard let loc = result else { return }
                        entry.vertices.append(BoulderVertex(
                            latitude: loc.coordinate.latitude,
                            longitude: loc.coordinate.longitude,
                            horizontalAccuracy: loc.horizontalAccuracy,
                            sampleCount: count,
                            source: .gps
                        ))
                    }
                }
        )
    }
}

#endif
