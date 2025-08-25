//
//  Data+Schema.swift
//  Sampled
//
//  Created by Kyle Erhabor on 8/17/25.
//

import Foundation
import GRDB

typealias RowID = Int64

extension TableRecord {
  static var everyColumn: [SQLSelectable] {
    [AllColumns(), Column.rowID]
  }
}

struct BookmarkRecord {
  var rowID: RowID? = nil
  let data: Data?
  let options: URL.BookmarkCreationOptions?
  let hash: Data?
  let relative: RowID?
}

extension BookmarkRecord: Equatable, FetchableRecord {}

extension BookmarkRecord: Codable {
  enum CodingKeys: String, CodingKey {
    case rowID = "rowid",
         data, options, hash, relative
  }

  enum Columns {
    static let data = Column(CodingKeys.data)
    static let options = Column(CodingKeys.options)
    static let hash = Column(CodingKeys.hash)
    static let relative = Column(CodingKeys.relative)
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    self.init(
      rowID: try container.decodeIfPresent(RowID.self, forKey: .rowID),
      data: try container.decodeIfPresent(Data.self, forKey: .data),
      options: try container.decodeIfPresent(URL.BookmarkCreationOptions.self, forKey: .options),
      hash: try container.decodeIfPresent(Data.self, forKey: .hash),
      relative: try container.decodeIfPresent(RowID.self, forKey: .relative),
    )
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(rowID, forKey: .rowID)
    try container.encode(data, forKey: .data)
    try container.encode(options, forKey: .options)
    try container.encode(hash, forKey: .hash)
    try container.encode(relative, forKey: .relative)
  }
}

extension BookmarkRecord: MutablePersistableRecord {
  mutating func didInsert(_ inserted: InsertionSuccess) {
    rowID = inserted.rowID
  }
}

extension BookmarkRecord: TableRecord {
  static let databaseTableName = "bookmarks"

  static var databaseSelection: [SQLSelectable] {
    Self.everyColumn
  }

  static var relativeAssociation: BelongsToAssociation<Self, Self> {
    self.belongsTo(Self.self, using: ForeignKey([Columns.relative]))
  }

  var relativeRequest: QueryInterfaceRequest<Self> {
    self.request(for: Self.relativeAssociation)
  }
}

struct LibraryRecord {
  var rowID: RowID? = nil
  let bookmark: RowID?
}

extension LibraryRecord: Codable {
  enum CodingKeys: String, CodingKey {
    case rowID = "rowid",
         bookmark
  }

  enum Columns {
    static let bookmark = Column(CodingKeys.bookmark)
  }
}

extension LibraryRecord: MutablePersistableRecord {
  mutating func didInsert(_ inserted: InsertionSuccess) {
    self.rowID = inserted.rowID
  }
}

extension LibraryRecord: Equatable, FetchableRecord {}

extension LibraryRecord: TableRecord {
  static let databaseTableName = "libraries"

  static var databaseSelection: [SQLSelectable] {
    Self.everyColumn
  }

  static var bookmarkAssociation: BelongsToAssociation<Self, BookmarkRecord> {
    self.belongsTo(BookmarkRecord.self, using: ForeignKey([Columns.bookmark]))
  }

  static var tracksAssociation: HasManyAssociation<Self, LibraryTrackRecord> {
    self.hasMany(LibraryTrackRecord.self, using: ForeignKey([LibraryTrackRecord.Columns.library]))
  }

  var bookmarkRequest: QueryInterfaceRequest<BookmarkRecord> {
    self.request(for: Self.bookmarkAssociation)
  }

  var tracksRequest: QueryInterfaceRequest<LibraryTrackRecord> {
    self.request(for: Self.tracksAssociation)
  }
}

enum LibraryTrackAlbumArtworkFormat: Int {
  case png, jpeg
}

extension LibraryTrackAlbumArtworkFormat: Codable {}

struct LibraryTrackAlbumArtworkRecord {
  var rowID: RowID? = nil
  let data: Data?
  let hash: Data?
  let format: LibraryTrackAlbumArtworkFormat?
}

extension LibraryTrackAlbumArtworkRecord: Codable {
  enum CodingKeys: String, CodingKey {
    case rowID = "rowid",
         data, hash, format
  }

  enum Columns {
    static let data = Column(CodingKeys.data)
    static let hash = Column(CodingKeys.hash)
    static let format = Column(CodingKeys.format)
  }
}

extension LibraryTrackAlbumArtworkRecord: MutablePersistableRecord {
  mutating func didInsert(_ inserted: InsertionSuccess) {
    self.rowID = inserted.rowID
  }
}

extension LibraryTrackAlbumArtworkRecord: Equatable, FetchableRecord {}

extension LibraryTrackAlbumArtworkRecord: TableRecord {
  static let databaseTableName = "library_track_album_artworks"

  static var databaseSelection: [SQLSelectable] {
    Self.everyColumn
  }
}

struct LibraryTrackRecord {
  var rowID: RowID? = nil
  let bookmark: RowID?
  let library: RowID?
  let title: String?
  let duration: Double?
  let isLiked: Bool?
  let artistName: String?
  let albumName: String?
  let albumArtistName: String?
  let albumDate: Date?
  // It would be nicer to inline this, but I believe SQLite doesn't normalize BLOBs across the database, meaning it's
  // cheaper in terms of storage to normalize it ourselves.
  let albumArtwork: RowID?
  let trackNumber: Int?
  let trackTotal: Int?
  let discNumber: Int?
  let discTotal: Int?
}

extension LibraryTrackRecord: Codable {
  enum CodingKeys: String, CodingKey {
    case rowID = "rowid",
         bookmark, library, title, duration,
         isLiked = "is_liked",
         artistName = "artist_name",
         albumName = "album_name",
         albumArtistName = "album_artist_name",
         albumDate = "album_date",
         albumArtwork = "album_artwork",
         trackNumber = "track_number",
         trackTotal = "track_total",
         discNumber = "disc_number",
         discTotal = "disc_total"
  }

  enum Columns {
    static let bookmark = Column(CodingKeys.bookmark)
    static let library = Column(CodingKeys.library)
    static let title = Column(CodingKeys.title)
    static let duration = Column(CodingKeys.duration)
    static let isLiked = Column(CodingKeys.isLiked)
    static let artistName = Column(CodingKeys.artistName)
    static let albumName = Column(CodingKeys.albumName)
    static let albumArtistName = Column(CodingKeys.albumArtistName)
    static let albumDate = Column(CodingKeys.albumDate)
    static let albumArtwork = Column(CodingKeys.albumArtwork)
    static let trackNumber = Column(CodingKeys.trackNumber)
    static let trackTotal = Column(CodingKeys.trackTotal)
    static let discNumber = Column(CodingKeys.discNumber)
    static let discTotal = Column(CodingKeys.discTotal)
  }
}

extension LibraryTrackRecord: MutablePersistableRecord {
  mutating func didInsert(_ inserted: InsertionSuccess) {
    self.rowID = inserted.rowID
  }
}

extension LibraryTrackRecord: Equatable, FetchableRecord {}

extension LibraryTrackRecord: TableRecord {
  static let databaseTableName = "library_tracks"

  static var databaseSelection: [SQLSelectable] {
    Self.everyColumn
  }

  static var bookmarkAssociation: BelongsToAssociation<Self, BookmarkRecord> {
    self.belongsTo(BookmarkRecord.self, using: ForeignKey([Columns.bookmark]))
  }

  static var libraryAssociation: BelongsToAssociation<Self, LibraryRecord> {
    self.belongsTo(LibraryRecord.self, using: ForeignKey([Columns.library]))
  }

  static var albumArtworkAssociation: BelongsToAssociation<Self, LibraryTrackAlbumArtworkRecord> {
    self.belongsTo(LibraryTrackAlbumArtworkRecord.self, using: ForeignKey([Columns.albumArtwork]))
  }

  var bookmarkRequest: QueryInterfaceRequest<BookmarkRecord> {
    self.request(for: Self.bookmarkAssociation)
  }

  var libraryRequest: QueryInterfaceRequest<LibraryRecord> {
    self.request(for: Self.libraryAssociation)
  }

  var albumArtworkRequest: QueryInterfaceRequest<LibraryTrackAlbumArtworkRecord> {
    self.request(for: Self.albumArtworkAssociation)
  }
}

struct ConfigurationRecord {
  var rowID: RowID? = nil
  let mainLibrary: RowID?

  static let `default` = Self(rowID: 1, mainLibrary: nil)
}

extension ConfigurationRecord: Codable {
  enum CodingKeys: String, CodingKey {
    case rowID = "rowid",
         mainLibrary = "main_library"
  }

  enum Columns {
    static let mainLibrary = Column(CodingKeys.mainLibrary)
  }
}

extension ConfigurationRecord: MutablePersistableRecord {
  mutating func didInsert(_ inserted: InsertionSuccess) {
    self.rowID = inserted.rowID
  }
}

extension ConfigurationRecord: FetchableRecord {
  static func find(_ db: Database) throws -> Self {
    try self.fetchOne(db) ?? .default
  }
}

extension ConfigurationRecord: TableRecord {
  static let databaseTableName = "configuration"

  static var databaseSelection: [SQLSelectable] {
    Self.everyColumn
  }

  static var mainLibraryAssociation: BelongsToAssociation<Self, LibraryRecord> {
    self.belongsTo(LibraryRecord.self, using: ForeignKey([Columns.mainLibrary]))
  }

  var mainLibraryRequest: QueryInterfaceRequest<LibraryRecord> {
    self.request(for: Self.mainLibraryAssociation)
  }
}
