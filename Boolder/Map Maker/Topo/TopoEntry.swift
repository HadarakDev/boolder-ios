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
    var pickerModeEnabled: Bool = false

    func reset() {
        photo = nil
        location = nil
        heading = nil
        comments = ""
        problems = []
        pickerModeEnabled = false
    }
}

#endif
