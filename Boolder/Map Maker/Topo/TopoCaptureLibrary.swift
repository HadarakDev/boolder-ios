//
//  TopoCaptureLibrary.swift
//  Boolder
//
//  Reads saved topo captures from disk and indexes them by the custom
//  problem filenames they reference. DEVELOPMENT-only.
//

#if DEVELOPMENT

import Foundation
import UIKit

struct SavedTopoCapture {
    var jsonFilename: String
    var jpegURL: URL
    var customProblemFilenames: [String]
    var comments: String
    var grade: String?
}

enum TopoCaptureLibrary {
    /// All saved topos that reference `problemFilename` in their
    /// custom_problem_filenames array.
    static func topos(referencingProblem problemFilename: String) -> [SavedTopoCapture] {
        loadAll().filter { $0.customProblemFilenames.contains(problemFilename) }
    }

    static func loadAll() -> [SavedTopoCapture] {
        let dir = directoryURL()
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        let jsons = urls.filter { $0.pathExtension == "json" }
        return jsons.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            // Decode permissively — the topo JSON has more fields than we
            // care about here.
            guard let decoded = try? JSONDecoder().decode(MinimalTopoJson.self, from: data) else {
                return nil
            }
            let stem = url.deletingPathExtension().lastPathComponent
            let jpegURL = dir.appendingPathComponent(stem + ".jpg")
            return SavedTopoCapture(
                jsonFilename: url.lastPathComponent,
                jpegURL: jpegURL,
                customProblemFilenames: decoded.custom_problem_filenames ?? [],
                comments: decoded.comments ?? "",
                grade: nil
            )
        }
    }

    /// Strict subset of NewTopoView.TopoJson — we only read the fields we
    /// need so older captures (without `custom_problem_filenames`) still
    /// decode cleanly.
    private struct MinimalTopoJson: Codable {
        var custom_problem_filenames: [String]?
        var comments: String?
    }

    private static func directoryURL() -> URL {
        let baseURL: URL = {
            if let iCloud = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
                return iCloud.appendingPathComponent("Documents")
            }
            return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }()
        return baseURL.appendingPathComponent("map-maker").appendingPathComponent("topos")
    }
}

#endif
