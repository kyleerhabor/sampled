//
//  SettingsModel.swift
//  Sampled
//
//  Created by Kyle Erhabor on 8/19/25.
//

import Defaults
import GRDB
import Observation
import OSLog

struct SettingsModelLoadConfigurationMainLibraryBookmarkInfo {
  let bookmark: BookmarkRecord
}

extension SettingsModelLoadConfigurationMainLibraryBookmarkInfo: Equatable, Decodable, FetchableRecord {}

struct SettingsModelLoadConfigurationMainLibraryInfo {
  let library: LibraryRecord
  let bookmark: SettingsModelLoadConfigurationMainLibraryBookmarkInfo
}

extension SettingsModelLoadConfigurationMainLibraryInfo: Decodable {
  enum CodingKeys: String, CodingKey {
    case library,
         bookmark = "_bookmark"
  }
}

extension SettingsModelLoadConfigurationMainLibraryInfo: Equatable, FetchableRecord {}

struct SettingsModelLoadConfigurationInfo {
  let mainLibrary: SettingsModelLoadConfigurationMainLibraryInfo
}

extension SettingsModelLoadConfigurationInfo: Decodable {
  enum CodingKeys: CodingKey {
    case mainLibrary
  }
}

extension SettingsModelLoadConfigurationInfo: Equatable, FetchableRecord {}

@Observable
@MainActor
class SettingsModel {
  func load() async {
    let observation = ValueObservation
      .trackingConstantRegion { db in
        try ConfigurationRecord
          .including(
            required: ConfigurationRecord.mainLibraryAssociation
              .forKey(SettingsModelLoadConfigurationInfo.CodingKeys.mainLibrary)
              .including(
                required: LibraryRecord.bookmarkAssociation
                  .forKey(SettingsModelLoadConfigurationMainLibraryInfo.CodingKeys.bookmark)
                  .select(Column.rowID, BookmarkRecord.Columns.data, BookmarkRecord.Columns.options, BookmarkRecord.Columns.hash),
              ),
          )
          .asRequest(of: SettingsModelLoadConfigurationInfo.self)
          .fetchOne(db)
      }
      .removeDuplicates()

    let conn: DatabasePool

    do {
      conn = try await connection()
    } catch {
      // TODO: Log.
      Logger.model.error("\(error)")

      return
    }

    do {
      for try await configuration in observation.values(in: conn) {
        guard let configuration else {
          continue
        }

        let data = configuration.mainLibrary.bookmark.bookmark.data!
        let options = configuration.mainLibrary.bookmark.bookmark.options!
        let assigned: AssignedBookmark

        do {
          assigned = try AssignedBookmark(
            data: data,
            options: URL.BookmarkResolutionOptions(options),
            relativeTo: nil,
          ) { url in
            let source = URLSource(url: url, options: options)
            let data = try source.accessingSecurityScopedResource {
              try source.url.bookmarkData(options: source.options)
            }

            return data
          }
        } catch {
          // TODO: Log.
          Logger.model.error("\(error)")

          continue
        }

        Defaults[.libraryFolderURL] = assigned.url

        let hashed = hash(data: assigned.data)

        guard hashed == configuration.mainLibrary.bookmark.bookmark.hash! else {
          do {
            try await conn.write { db in
              var bookmark = BookmarkRecord(
                data: assigned.data,
                options: options,
                hash: hashed,
                relative: nil,
              )

              try bookmark.upsert(db)

              let library = LibraryRecord(
                rowID: configuration.mainLibrary.library.rowID,
                bookmark: bookmark.rowID,
                currentQueue: nil,
              )

              try library.update(db, columns: [LibraryRecord.Columns.bookmark])
            }
          } catch {
            // TODO: Log.
            Logger.model.error("\(error)")
          }

          continue
        }
      }
    } catch {
      // TODO: Log.
      Logger.model.error("\(error)")

      return
    }
  }

  func setLibraryFolder(url: URL) async {
    let urb: URLBookmark

    do {
      urb = try url.accessingSecurityScopedResource {
        try URLBookmark(
          url: url,
          options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess, .withoutImplicitSecurityScope],
          relativeTo: nil,
        )
      }
    } catch {
      // TODO: Log.
      Logger.model.error("\(error)")

      return
    }

    Defaults[.libraryFolderURL] = urb.url

    let conn: DatabasePool

    do {
      conn = try await connection()
    } catch {
      // TODO: Log.
      Logger.model.error("\(error)")

      return
    }

    do {
      try await conn.write { db in
        var bookmark = BookmarkRecord(
          data: urb.bookmark.data,
          options: urb.bookmark.options,
          hash: hash(data: urb.bookmark.data),
          relative: nil,
        )

        try bookmark.upsert(db)

        var library = LibraryRecord(bookmark: bookmark.rowID, currentQueue: nil)
        try library.upsert(db)

        let configuration = try ConfigurationRecord.find(db)
        var config = ConfigurationRecord(rowID: configuration.rowID, mainLibrary: library.rowID)
        try config.upsert(db)
      }
    } catch {
      // TODO: Log.
      Logger.model.error("\(error)")

      return
    }
  }
}
