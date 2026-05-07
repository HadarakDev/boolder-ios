//
//  CustomAreaToolbar.swift
//  Boolder
//
//  Top floating toolbar shown when a TopoSud-authored area is selected on
//  the map (analogous to the upstream AreaToolbarView). DEVELOPMENT-only.
//

#if DEVELOPMENT

import SwiftUI

struct CustomAreaToolbar: View {
    let area: SavedArea
    var onClose: () -> Void
    var onInfo: () -> Void

    var body: some View {
        VStack {
            HStack(spacing: 12) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.primary)
                        .padding(8)
                }

                Spacer()

                VStack(spacing: 2) {
                    Text(area.name.isEmpty ? area.filename : area.name)
                        .font(.headline)
                    Text("Area")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: onInfo) {
                    Image(systemName: "info.circle")
                        .font(.title3)
                        .foregroundColor(.primary)
                        .padding(8)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Spacer()
        }
    }
}

#endif
