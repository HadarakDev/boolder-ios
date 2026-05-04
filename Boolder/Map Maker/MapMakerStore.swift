//
//  MapMakerStore.swift
//  Boolder
//
//  Originally created by Nicolas Mondollot on 08/01/2021.
//  Ported to TopoSud (DEVELOPMENT-only) from the legacy-map-maker branch.
//

#if DEVELOPMENT

import Foundation

class MapMakerStore {
    func save(data: Data, directory: String, filename: String) {
        let fileURL = directoryURL(directory: directory).appendingPathComponent(filename)

        do {
            try data.write(to: fileURL, options: [.withoutOverwriting])
        }
        catch {
            print("MapMakerStore save error:", error)
        }
    }

    func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH.mm.ss"
        return f.string(from: Date())
    }

    private var baseURL: URL {
        // iCloud Documents container so captures are pulled to the Mac for
        // post-processing. Falls back to local Documents if iCloud isn't
        // available (e.g. simulator without an iCloud account).
        if let iCloud = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            return iCloud.appendingPathComponent("Documents")
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func directoryURL(directory: String) -> URL {
        let url = baseURL.appendingPathComponent("map-maker").appendingPathComponent(directory)

        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("MapMakerStore mkdir error:", error)
            }
        }

        return url
    }
}

#endif
