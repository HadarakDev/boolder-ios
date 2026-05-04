//
//  SqliteStore.swift
//  Boolder
//
//  Created by Nicolas Mondollot on 28/10/2022.
//  Copyright © 2022 Nicolas Mondollot. All rights reserved.
//

import Foundation
import SQLite

class SqliteStore {
    static let shared = SqliteStore()
    
    let db: Connection
    
    private init() {
        let databaseURL = Bundle.main.url(forResource: "boolder", withExtension: "db")!
        // Open read-only: boolder.db lives in the app bundle (read-only FS).
        // iOS 26 enforces this strictly; opening read-write triggers SQLITE_IOERR
        // when SQLite tries to create its journal file.
        db = try! Connection(databaseURL.path, readonly: true) // TODO: catch errors
    }
}
