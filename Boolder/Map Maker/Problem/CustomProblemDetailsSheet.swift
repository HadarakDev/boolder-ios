//
//  CustomProblemDetailsSheet.swift
//  Boolder
//
//  Tap a TopoSud-authored problem on the map (outside of any Map Maker
//  mode) and this sheet appears: shows the problem metadata plus any
//  topo photos that reference the problem in their JSON. Mirrors the
//  upstream "classic" problem details UX as closely as a TopoSud-side
//  photo set allows. DEVELOPMENT-only.
//

#if DEVELOPMENT

import SwiftUI
import UIKit

struct CustomProblemDetailsSheet: View {
    let filename: String
    var onClose: () -> Void
    var onEdit: () -> Void

    @State private var fullscreenURL: URL?

    var body: some View {
        NavigationStack {
            content
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
                .fullScreenCover(item: $fullscreenURL) { url in
                    FullscreenPhotoView(url: url) { fullscreenURL = nil }
                }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var content: some View {
        if let record = ProblemSaver.load(filename: filename),
           record.geometry.coordinates.count >= 2 {
            let topos = TopoCaptureLibrary.topos(referencingProblem: filename)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(name: record.properties.name, grade: record.properties.grade)

                    if !topos.isEmpty {
                        photosSection(topos: topos)
                    } else {
                        emptyPhotosHint
                    }

                    metaSection(record: record)

                    if !record.properties.comments.isEmpty {
                        commentsSection(record.properties.comments)
                    }
                }
                .padding()
            }
        } else {
            ContentUnavailableView(
                "Problem unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text("Couldn't read \(filename).")
            )
        }
    }

    private func header(name: String, grade: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name.isEmpty ? "(no name)" : name)
                .font(.title2.weight(.semibold))
            HStack(spacing: 8) {
                Text(grade)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color("AppGreen").opacity(0.18), in: Capsule())
                    .foregroundColor(Color("AppGreen"))
                Spacer()
            }
        }
    }

    private func photosSection(topos: [SavedTopoCapture]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Photos (\(topos.count))")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                ForEach(topos, id: \.jsonFilename) { topo in
                    Button {
                        fullscreenURL = topo.jpegURL
                    } label: {
                        thumbnail(url: topo.jpegURL)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func thumbnail(url: URL) -> some View {
        Group {
            if let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .overlay(
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    )
            }
        }
        .frame(height: 110)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
    }

    private var emptyPhotosHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "camera").foregroundColor(.secondary)
            Text("No topo photo yet — capture one with the camera FAB and pick this problem.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metaSection(record: ProblemSaver.ProblemJson) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Position")
                .font(.headline)
            Text(String(
                format: "%.6f, %.6f",
                record.geometry.coordinates[1],
                record.geometry.coordinates[0]
            ))
            .font(.system(.footnote, design: .monospaced))
            .foregroundColor(.secondary)
            if let boulderId = record.properties.boulderId {
                Text("Boulder: \(boulderId)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func commentsSection(_ comments: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Comments")
                .font(.headline)
            Text(comments)
                .font(.subheadline)
        }
    }
}

private struct FullscreenPhotoView: View {
    let url: URL
    var onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Photo unavailable")
                    .foregroundColor(.white)
            }
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white, .black.opacity(0.6))
                    .padding()
            }
        }
    }
}

extension URL: Identifiable {
    public var id: String { absoluteString }
}

#endif
