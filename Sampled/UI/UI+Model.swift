//
//  UI+Model.swift
//  Sampled
//
//  Created by Kyle Erhabor on 8/19/25.
//

import Algorithms
import CryptoKit
import Foundation
import GRDB
import OSLog

extension Logger {
  static let model = Self(subsystem: Bundle.appID, category: "Model")
}

extension URL.BookmarkResolutionOptions {
  init(_ options: URL.BookmarkCreationOptions) {
    self.init()

    if options.contains(.withSecurityScope) {
      self.insert(.withSecurityScope)
    }

    if options.contains(.withoutImplicitSecurityScope) {
      self.insert(.withoutImplicitStartAccessing)
    }
  }
}

extension AssignedBookmark {
  @available(*, noasync)
  init(data: Data, options: URL.BookmarkCreationOptions, relativeTo relative: URL?) throws {
    try self.init(
      data: data,
      // In my experience, if the user has a volume that was created as an image in Disk Utility and it's not mounted,
      // resolution will fail while prompting the user to unlock the volume. Now, we're not a file managing app, so we
      // don't need to invest in making that work.
      //
      // Note there is also a withoutUI option, but I haven't checked whether or not it performs the same action.
      options: URL.BookmarkResolutionOptions(options).union(.withoutMounting),
      relativeTo: relative,
    ) { url in
      Logger.model.log("Bookmark for file URL '\(url.pathString)' is stale: re-creating...")

      let source = URLSource(url: url, options: options)
      let bookmark = try source.accessingSecurityScopedResource {
        try source.url.bookmark(options: source.options, relativeTo: relative)
      }

      return bookmark
    }
  }

  init(data: Data, options: URL.BookmarkCreationOptions, relativeTo relative: URL?) async throws {
    try await self.init(
      data: data,
      options: URL.BookmarkResolutionOptions(options).union(.withoutMounting),
      relativeTo: relative,
    ) { url in
      Logger.model.log("Bookmark for file URL '\(url.pathString)' is stale: re-creating...")

      let source = URLSource(url: url, options: options)
      let bookmark = try await source.accessingSecurityScopedResource {
        try await source.url.bookmark(options: source.options, relativeTo: relative)
      }

      return bookmark
    }
  }
}

enum BookmarkStatus {
  case old, current, new
}

func bookmark(data: Data, assigned: AssignedBookmark?) -> BookmarkStatus {
  // If the bookmark wasn't assigned, return the same bookmark data to notify observers that the state of the underlying
  // resource has changed (e.g., a file we think is available is no longer available).
  guard let assigned else {
    return .old
  }

  // If the bookmark was resolved and is not stale, return to signal that the state of the underlying resource hasn't
  // changed (e.g., a file we think is available is still available).
  guard assigned.resolved.isStale else {
    return .current
  }

  // If the bookmark was resolved and is stale, return the new bookmark data to notify observers that the state of the
  // underlying resource has changed (e.g., a file we think is available is still available, but has new bookmark data).
  return .new
}

func write(_ db: Database, bookmark: BookmarkRecord, assigned: AssignedBookmark?) throws {
  switch Sampled.bookmark(data: bookmark.data!, assigned: assigned) {
    case .old:
      try db.notifyChanges(in: BookmarkRecord.all())
    case .current:
      break
    case .new:
      let bookmark = BookmarkRecord(rowID: bookmark.rowID, data: assigned?.data, options: nil)
      try bookmark.update(db, columns: [BookmarkRecord.Columns.data])
  }
}

struct BookmarkAssignmentFileBookmarkBookmark {
  let bookmark: BookmarkRecord
}

struct BookmarkAssignmentFileBookmarkRelative {
  let bookmark: BookmarkRecord
}

struct BookmarkAssignmentFileBookmark {
  let bookmark: BookmarkAssignmentFileBookmarkBookmark
  let relative: BookmarkAssignmentFileBookmarkRelative?
}

struct BookmarkAssignmentTaskResult {
  let bookmark: BookmarkRecord
  let assigned: AssignedBookmark
}

struct BookmarkAssignment {
  private var bookmarks: [RowID: AssignedBookmark]

  init() {
    self.bookmarks = [:]
  }

  mutating func assign(fileBookmarks: [BookmarkAssignmentFileBookmark]) async {
    await withTaskGroup(of: BookmarkAssignmentTaskResult?.self) { group in
      fileBookmarks
        .compactMap(\.relative)
        .uniqued(on: \.bookmark.rowID)
        .forEach { relative in
          group.addTask {
            let bookmark: AssignedBookmark

            do {
              bookmark = try await AssignedBookmark(
                data: relative.bookmark.data!,
                options: relative.bookmark.options!,
                relativeTo: nil,
              )
            } catch {
              // TODO: Elaborate.
              Logger.model.error("\(error)")

              return nil
            }

            let result = BookmarkAssignmentTaskResult(bookmark: relative.bookmark, assigned: bookmark)

            return result
          }
        }

      for await result in group {
        guard let result else {
          continue
        }

        self.bookmarks[result.bookmark.rowID!] = result.assigned
      }

      fileBookmarks.forEach { fileBookmark in
        group.addTask { [self] in
          let relative: URLSource?

          if let r = fileBookmark.relative {
            guard let bookmark = self.bookmarks[r.bookmark.rowID!] else {
              return nil
            }

            relative = URLSource(url: bookmark.resolved.url, options: r.bookmark.options!)
          } else {
            relative = nil
          }

          let bookmark: AssignedBookmark

          do {
            bookmark = try await relative.accessingSecurityScopedResource {
              try await AssignedBookmark(
                data: fileBookmark.bookmark.bookmark.data!,
                options: fileBookmark.bookmark.bookmark.options!,
                relativeTo: relative?.url,
              )
            }
          } catch {
            // TODO: Elaborate.
            Logger.model.error("\(error)")

            return nil
          }

          let result = BookmarkAssignmentTaskResult(bookmark: fileBookmark.bookmark.bookmark, assigned: bookmark)

          return result
        }
      }

      for await result in group {
        guard let result else {
          continue
        }

        self.bookmarks[result.bookmark.rowID!] = result.assigned
      }
    }
  }

  private func isSatisfied(bookmark: BookmarkRecord) -> Bool {
    guard let bookmark = self.bookmarks[bookmark.rowID!] else {
      // It's possible resolving the bookmark failed, in which we don't want to potentially spin in an infinite loop
      // when called from ValueObservation.
      return true
    }

    return !bookmark.resolved.isStale
  }

  func isSatisfied(fileBookmark: BookmarkAssignmentFileBookmark) -> Bool {
    var isBookmarkSatisfied: Bool {
      self.isSatisfied(bookmark: fileBookmark.bookmark.bookmark)
    }

    guard let relative = fileBookmark.relative else {
      return isBookmarkSatisfied
    }

    return isSatisfied(bookmark: relative.bookmark) && isBookmarkSatisfied
  }

  func write(_ db: Database, fileBookmarks: [BookmarkAssignmentFileBookmark]) throws {
    try fileBookmarks
      .compactMap(\.relative)
      .uniqued(on: \.bookmark.rowID)
      .forEach { relative in
        try Sampled.write(db, bookmark: relative.bookmark, assigned: self.bookmarks[relative.bookmark.rowID!])
      }

    try fileBookmarks.forEach { fileBookmark in
      try Sampled.write(
        db,
        bookmark: fileBookmark.bookmark.bookmark,
        assigned: self.bookmarks[fileBookmark.bookmark.bookmark.rowID!],
      )
    }
  }

  func write(_ db: Database, fileBookmark: BookmarkAssignmentFileBookmark) throws {
    try Sampled.write(
      db,
      bookmark: fileBookmark.bookmark.bookmark,
      assigned: self.bookmarks[fileBookmark.bookmark.bookmark.rowID!],
    )
  }

  private func source(bookmark: BookmarkRecord) -> URLSource? {
    guard let assigned = self.bookmarks[bookmark.rowID!] else {
      return nil
    }

    let source = URLSource(url: assigned.resolved.url, options: bookmark.options!)

    return source
  }

  func document(fileBookmark: BookmarkAssignmentFileBookmark) -> URLSourceDocument? {
    let relative: URLSource?

    if let r = fileBookmark.relative {
      guard let bookmark = self.bookmarks[r.bookmark.rowID!] else {
        return nil
      }

      relative = URLSource(url: bookmark.resolved.url, options: r.bookmark.options!)
    } else {
      relative = nil
    }

    guard let bookmark = self.bookmarks[fileBookmark.bookmark.bookmark.rowID!] else {
      return nil
    }

    let document = URLSourceDocument(
      source: URLSource(url: bookmark.resolved.url, options: fileBookmark.bookmark.bookmark.options!),
      relative: relative,
    )

    return document
  }
}

// In Info structs, CodingKeys with a prefixed string value are there to disambiguate it from the returned rows when
// decoding.

func hash(data: some DataProtocol) -> Data {
  Data(SHA256.hash(data: data))
}

extension LibraryTrackAlbumArtworkFormat {
  init?(codecID: CodecID) {
    switch codecID {
      case .png: self = .png
      case .mjpeg: self = .jpeg
      default: return nil
    }
  }

  var codecID: CodecID {
    switch self {
      case .png: .png
      case .jpeg: .mjpeg
    }
  }
}
