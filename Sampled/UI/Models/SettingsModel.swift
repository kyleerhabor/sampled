//
//  SettingsModel.swift
//  Sampled
//
//  Created by Kyle Erhabor on 8/19/25.
//

import GRDB
import Observation
import OSLog

@Observable
@MainActor
class SettingsModel {
  func setLibraryFolder(url: URL) async {
    UserDefaults.standard.set(url, forKey: StorageKeys.libraryFolder.name)

    let bookmark: Bookmark

    do {
      bookmark = try await url.accessingSecurityScopedResource {
        try await Bookmark(
          url: url,
          options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
          relativeTo: nil,
        )
      }
    } catch {
      // TODO: Log.
      Logger.model.error("\(error)")

      return
    }

    let connection: DatabasePool

    do {
      connection = try await databaseConnection()
    } catch {
      Logger.model.error("Could not create database connection: \(error)")

      return
    }

    do {
      try await connection.write { db in
        var bookmark = BookmarkRecord(data: bookmark.data, options: bookmark.options)
        try bookmark.upsert(db)

        var fileBookmark = FileBookmarkRecord(bookmark: bookmark.rowID, relative: nil)
        try fileBookmark.upsert(db)

//        let libraryID = try LibraryRecord
//          .filter(key: [LibraryRecord.Columns.fileBookmark.name: fileBookmark.rowID])
//          .selectPrimaryKey(as: RowID.self)
//          .fetchOne(db)
//
//        let library: LibraryRecord
//
//        if let id = libraryID {
//          library = LibraryRecord(rowID: id, fileBookmark: fileBookmark.rowID, currentQueue: nil)
//          try library.update(db, columns: [LibraryRecord.Columns.fileBookmark])
//        } else {
//          var lib = LibraryRecord(fileBookmark: fileBookmark.rowID, currentQueue: nil)
//          try lib.insert(db)
//
//          library = lib
//        }
        let library = try LibraryRecord
          .filter(key: [LibraryRecord.Columns.fileBookmark.name: fileBookmark.rowID])
          .fetchOne(db) ?? LibraryRecord(fileBookmark: fileBookmark.rowID, currentQueue: nil)

        var lib = LibraryRecord(
          rowID: library.rowID,
          fileBookmark: fileBookmark.rowID,
          currentQueue: library.currentQueue,
        )

        try lib.upsert(db)

        let configuration = try ConfigurationRecord.find(db)
        var config = ConfigurationRecord(rowID: configuration.rowID, mainLibrary: lib.rowID)
        try config.upsert(db)
      }
    } catch {
      Logger.model.error("Could not write to database: \(error)")

      return
    }
  }
}
