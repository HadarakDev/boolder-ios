//
//  ProblemEntry.swift
//  Boolder
//
//  Created for TopoSud (DEVELOPMENT-only) to author climbing problems on the
//  map. Mirrors BoulderDrawEntry: an @Observable state holder that lives at
//  the MapContainerView level and is read by both the FAB and the
//  add/edit sheet.
//

#if DEVELOPMENT

import Foundation
import CoreLocation

@Observable
final class ProblemEntry {
    /// True while the user is in "place a problem" mode (3rd FAB active).
    var addingEnabled: Bool = false
    /// The coord of the most recently tapped point on the map; the sheet
    /// reads this to know where the new problem will live. Nil when no
    /// sheet is open.
    var pendingCoord: CLLocationCoordinate2D?
    /// Form fields for the in-progress problem.
    var name: String = ""
    var grade: String = "7a"
    var comments: String = ""
    /// Filename of the boulder polygon this problem is anchored to. Set by
    /// the controller from a polygon hit-test at the tap point — every
    /// problem must live inside a saved boulder.
    var boulderId: String?
    /// Set when the sheet was opened to edit an existing record. Save then
    /// overwrites that file instead of creating a fresh timestamp.
    var editingFilename: String?
    /// Set when a saved problem is tapped on the map outside of any Map
    /// Maker mode — drives a read-only details sheet so the user can
    /// consult the record.
    var viewingFilename: String?
    /// Bumped after a successful save/delete so the map can re-read the
    /// on-disk problems directory. Monotonic — not cleared by reset().
    var savedProblemsVersion: Int = 0

    /// Clears form state (everything except the version counter and the
    /// addingEnabled flag — exiting the mode is a separate action).
    func clearPending() {
        pendingCoord = nil
        name = ""
        grade = "7a"
        comments = ""
        boulderId = nil
        editingFilename = nil
    }

    /// Full reset — leaves the version counter intact.
    func reset() {
        addingEnabled = false
        clearPending()
    }
}

#endif
