//
//  Data+Core.swift
//  Sampled
//
//  Created by Kyle Erhabor on 8/17/25.
//

import Defaults
import Foundation
import GRDB
import OSLog

extension Logger {
  static let data = Self(subsystem: Bundle.appID, category: "Data")
}

extension URL {
  #if DEBUG
  static let dataDirectory = Self.applicationSupportDirectory.appending(
    components: Bundle.appID, "DebugData",
    directoryHint: .isDirectory,
  )

  #else
  static let dataDirectory = Self.applicationSupportDirectory.appending(
    components: Bundle.appID, "Data",
    directoryHint: .isDirectory,
  )

  #endif

  static let databaseFile = Self.dataDirectory
    .appending(component: "Data", directoryHint: .notDirectory)
    .appendingPathExtension("sqlite")
}

extension GRDB.Configuration {
  static var standard: Self {
    var configuration = Self()

    #if DEBUG
    configuration.publicStatementArguments = true
    configuration.prepareDatabase { db in
      db.trace(options: .profile) { trace in
        Logger.data.debug("SQL> \(trace)")
      }
    }

    #endif

    return configuration
  }
}

let connection = Once {
  let url = URL.databaseFile
  let configuration = GRDB.Configuration.standard
  let connection: DatabasePool

  do {
    connection = try DatabasePool(path: url.pathString, configuration: configuration)
  } catch let error as DatabaseError where error.resultCode == .SQLITE_CANTOPEN {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

    connection = try DatabasePool(path: url.pathString, configuration: configuration)
  }

  var migrator = DatabaseMigrator()
  migrator.registerMigration("v1") { db in
    try db.create(table: BookmarkRecord.databaseTableName) { table in
      table.primaryKey(Column.rowID.name, .integer)

      table
        .column(BookmarkRecord.Columns.data.name, .blob)
        .notNull()
        .unique()

      table
        .column(BookmarkRecord.Columns.options.name, .integer)
        .notNull()

      table
        .column(BookmarkRecord.Columns.hash.name, .blob)
        .notNull()
        .unique()

      table
        .column(BookmarkRecord.Columns.relative.name, .integer)
        .references(BookmarkRecord.databaseTableName)
    }

    try db.create(table: LibraryRecord.databaseTableName) { table in
      table.primaryKey(Column.rowID.name, .integer)
      table
        .column(LibraryRecord.Columns.bookmark.name, .integer)
        .notNull()
        .unique()
        .references(BookmarkRecord.databaseTableName)
    }

    try db.create(table: LibraryTrackAlbumArtworkRecord.databaseTableName) { table in
      table.primaryKey(Column.rowID.name, .integer)

      table
        .column(LibraryTrackAlbumArtworkRecord.Columns.data.name, .blob)
        .notNull()
        .unique()

      table
        .column(LibraryTrackAlbumArtworkRecord.Columns.hash.name, .blob)
        .notNull()
        .unique()
    }

    try db.create(table: LibraryTrackRecord.databaseTableName) { table in
      table.primaryKey(Column.rowID.name, .integer)
      table
        .column(LibraryTrackRecord.Columns.bookmark.name, .integer)
        .notNull()
        .unique()
        .references(BookmarkRecord.databaseTableName)

      table
        .column(LibraryTrackRecord.Columns.library.name, .integer)
        .notNull()
        .references(LibraryRecord.databaseTableName)

      table.column(LibraryTrackRecord.Columns.title.name, .text)

      table
        .column(LibraryTrackRecord.Columns.duration.name, .integer)
        .notNull()

      table.column(LibraryTrackRecord.Columns.artistName.name, .text)
      table.column(LibraryTrackRecord.Columns.albumName.name, .text)
      table.column(LibraryTrackRecord.Columns.albumArtistName.name, .text)
      table.column(LibraryTrackRecord.Columns.albumDate.name, .text)

      table
        .column(LibraryTrackRecord.Columns.albumArtwork.name, .integer)
        .references(LibraryTrackAlbumArtworkRecord.databaseTableName)

      table.column(LibraryTrackRecord.Columns.trackNumber.name, .integer)
      table.column(LibraryTrackRecord.Columns.trackTotal.name, .integer)
      table.column(LibraryTrackRecord.Columns.discNumber.name, .integer)
      table.column(LibraryTrackRecord.Columns.discTotal.name, .integer)
    }

    try db.create(table: ConfigurationRecord.databaseTableName) { table in
      table
        .primaryKey(Column.rowID.name, .integer)
        .check { $0 == ConfigurationRecord.default.rowID }

      table
        .column(ConfigurationRecord.Columns.mainLibrary.name, .integer)
        .references(LibraryRecord.databaseTableName)
    }
  }

  #if DEBUG
  if try await connection.read(migrator.hasSchemaChanges) {
    try await connection.erase()

    // It's a little annoying that we're letting Defaults leak into data, which is for UI.
    Defaults.reset(.libraryFolderURL)
  }

  #endif

  try migrator.migrate(connection)

  return connection
}
