//
//  TopoEntry.swift
//  Boolder
//
//  Originally created by Nicolas Mondollot on 10/01/2021.
//  Ported to TopoSud (DEVELOPMENT-only) from the legacy-map-maker branch.
//  Migrated from ObservableObject to @Observable.
//

#if DEVELOPMENT

import Foundation
import CoreLocation
import SwiftUI

@Observable
final class TopoEntry {
    var photo: UIImage?
    var location: CLLocation?
    var heading: CLHeading?
    var comments: String = ""
    var problems: [Problem] = []
    /// Custom (TopoSud-authored) problems picked from the saved-problems
    /// layer — kept separately from `problems` because they aren't backed
    /// by SQLite IDs and are referenced by their on-disk filename.
    var customProblems: [SavedProblem] = []
    var pickerModeEnabled: Bool = false

    func reset() {
        photo = nil
        location = nil
        heading = nil
        comments = ""
        problems = []
        customProblems = []
        pickerModeEnabled = false
    }
}

#endif
