//
//  Data+Core.swift
//  Sampled
//
//  Created by Kyle Erhabor on 8/17/25.
//

import CFFmpeg
import SampledFFmpeg
import Algorithms
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

extension DatabaseValueConvertible {
  static func fetchAll(_ db: Database, literal: SQL) throws -> [Self] {
    let (sql, arguments) = try literal.build(db)
    let results = try Self.fetchAll(db, sql: sql, arguments: arguments)

    return results
  }
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

private func readAttachedPicturePacket(
  _ context: UnsafeMutablePointer<AVFormatContext>!,
  stream: UnsafeMutablePointer<AVStream>!,
  packet: UnsafeMutablePointer<AVPacket>!,
) throws(FFError) -> UnsafePointer<AVPacket> {
  if stream.pointee.streamDisposition.contains(.attachedPicture) {
    return stream.pointer(to: \.attached_pic)!
  }

  streams(context).forEach { stream in
    stream!.pointee.discard = AVDISCARD_ALL
  }

  stream.pointee.discard = AVDISCARD_NONE

  while true {
    try readFrame(context, into: packet)

    if packet.pointee.stream_index == stream.pointee.index {
      break
    }
  }

  return UnsafePointer(packet)
}

// TODO: Rename.
private func read(
  _ formatContext: UnsafeMutablePointer<AVFormatContext>!,
  packet: UnsafeMutablePointer<AVPacket>!,
) throws(FFError) -> LibraryTrackAlbumArtworkRecord? {
  var decoder: UnsafePointer<AVCodec>!
  let streami: Int32

  do {
    streami = try findBestStream(formatContext, type: .video, decoder: &decoder)
  } catch let error where error.code == .streamNotFound {
    Logger.model.error("Could not find best video stream for attached picture")

    return nil
  }

  let stream = formatContext.pointee.streams[Int(streami)]!
  let codecContext = FFCodecContext(codec: decoder)
  try copyCodecParameters(codecContext.context, params: stream.pointee.codecpar)
  try openCodec(codecContext.context, codec: decoder)

  let attachedPicture = try readAttachedPicturePacket(formatContext, stream: stream, packet: packet)
  let codecID = stream.pointee.codecpar.pointee.codec_id

  guard let format = LibraryTrackAlbumArtworkFormat(codecID: codecID) else {
    Logger.model.log("Could not create library track album artwork format from codec ID \(codecID.rawValue) (\(String(cString: avcodec_get_name(codecID))))")

    return nil
  }

  let data = UnsafeBufferPointer(start: attachedPicture.pointee.data, count: Int(attachedPicture.pointee.size))
  let hash = hash(data: data)

  return LibraryTrackAlbumArtworkRecord(data: Data(data), hash: hash, format: format)
}

struct DatabaseLoadConfigurationMainLibraryBookmarkInfo {
  let bookmark: BookmarkRecord
}

extension DatabaseLoadConfigurationMainLibraryBookmarkInfo: Equatable, Decodable, FetchableRecord {}

struct DatabaseLoadConfigurationMainLibraryInfo {
  let library: LibraryRecord
  let bookmark: DatabaseLoadConfigurationMainLibraryBookmarkInfo
}

extension DatabaseLoadConfigurationMainLibraryInfo: Decodable {
  enum CodingKeys: String, CodingKey {
    case library,
         bookmark = "_bookmark"
  }
}

extension DatabaseLoadConfigurationMainLibraryInfo: Equatable, FetchableRecord {}

struct DatabaseLoadConfigurationInfo {
  let mainLibrary: DatabaseLoadConfigurationMainLibraryInfo
}

extension DatabaseLoadConfigurationInfo: Decodable {
  enum CodingKeys: CodingKey {
    case mainLibrary
  }
}

extension DatabaseLoadConfigurationInfo: Equatable, FetchableRecord {}

private func load(enumerator: FileManager.DirectoryEnumerator, relativeTo relative: URL) -> [URLBookmark] {
  var contents = [URLBookmark]()

  for case let content as URL in enumerator {
    do {
      contents.append(try URLBookmark(url: content, options: [], relativeTo: relative))
    } catch {
      // TODO: Elaborate.
      Logger.model.error("\(error)")

      continue
    }
  }

  return contents
}

private func load(connection: DatabasePool) async {
  let observation = ValueObservation
    .trackingConstantRegion { db in
      try ConfigurationRecord
        .select(ConfigurationRecord.Columns.mainLibrary)
        .including(
          required: ConfigurationRecord.mainLibraryAssociation
            .forKey(DatabaseLoadConfigurationInfo.CodingKeys.mainLibrary)
            .select(Column.rowID, LibraryRecord.Columns.bookmark)
            .including(
              required: LibraryRecord.bookmarkAssociation
                .forKey(DatabaseLoadConfigurationMainLibraryInfo.CodingKeys.bookmark)
                .select(
                  Column.rowID,
                  BookmarkRecord.Columns.data,
                  BookmarkRecord.Columns.options,
                  BookmarkRecord.Columns.hash,
                ),
            ),
        )
        .asRequest(of: DatabaseLoadConfigurationInfo.self)
        .fetchOne(db)
    }
    .removeDuplicates()

  var stream = AsyncStream<LibraryModelEventStreamElement>.makeStream()

  do {
    for try await configuration in observation.values(in: connection) {
      guard let configuration else {
        continue
      }

      let id = configuration.mainLibrary.library.rowID!
      let bookmarkOptions = configuration.mainLibrary.bookmark.bookmark.options!
      let assigned: AssignedBookmark

      do {
        assigned = try AssignedBookmark(
          data: configuration.mainLibrary.bookmark.bookmark.data!,
          options: URL.BookmarkResolutionOptions(bookmarkOptions),
          relativeTo: nil,
        ) { url in
          let source = URLSource(url: url, options: bookmarkOptions)
          let data = try source.accessingSecurityScopedResource {
            try source.url.bookmarkData(options: source.options)
          }

          return data
        }
      } catch {
        // TODO: Elaborate.
        Logger.model.error("\(error)")

        continue
      }

      let hashed = hash(data: assigned.data)

      guard hashed == configuration.mainLibrary.bookmark.bookmark.hash! else {
        do {
          try await connection.write { db in
            var bookmark = BookmarkRecord(
              data: assigned.data,
              options: bookmarkOptions,
              hash: hashed,
              relative: nil,
            )

            try bookmark.upsert(db)

            let library = LibraryRecord(
              rowID: id,
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

      // I'm surprised file system events does not require a security scope.
      stream.continuation.finish()

      stream = AsyncStream<LibraryModelEventStreamElement>.makeStream()
      stream.continuation.yield(.initial)

      let eventStream = EventStream()
      let eventStreamCreated = eventStream.create(forFileAt: assigned.url, latency: 1) { events in
        stream.continuation.yield(.events(events))
      }

      guard eventStreamCreated,
            eventStream.start() else {
        continue
      }

      stream.continuation.onTermination = { _ in
        eventStream.stop()
      }

      let stream = stream

      Task {
        // TODO: Handle tracks that are removed from the library.
        for await element in stream.stream {
          // TODO: Extract.
          struct Track {
            let track: LibraryTrackRecord
            let bookmark: BookmarkRecord
            let artwork: LibraryTrackAlbumArtworkRecord
          }

          let source = URLSource(url: assigned.url, options: bookmarkOptions)
          let tracks = source.accessingSecurityScopedResource {
            var urbs = [URLBookmark]()

            switch element {
              case .initial:
                guard let enumerator = FileManager.default.enumerator(
                  at: source.url,
                  includingPropertiesForKeys: nil,
                ) else {
                  // TODO: Log.
                  break
                }

                urbs.append(contentsOf: load(enumerator: enumerator, relativeTo: source.url))
              case let .events(events):
                // TODO: Coalesce.
                //
                // All this callback does is give us a means of subscribing to file system events in an increasing order.
                // The paths and flags given in a batch could be used to form a configuration on how best to scan the file
                // system. This should take into consideration flags like kFSEventStreamEventFlagMustScanSubDirs which
                // carry implications on what paths to scan.
                for i in 0..<events.count {
                  let url = events.paths[i]
                  let flags = events.flags[i]
                  var options = FileManager.DirectoryEnumerationOptions()

                  if flags.contains(.mustScanSubdirectories) {
                    options.insert(.skipsSubdirectoryDescendants)
                  }

                  guard let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: nil,
                    options: options,
                  ) else {
                    // TODO: Log.
                    continue
                  }

                  urbs.append(contentsOf: load(enumerator: enumerator, relativeTo: source.url))
                }
            }

            return urbs.compactMap { urb -> Track? in
              let formatContext = FFFormatContext()

              do {
                return try openingInput(
                  &formatContext.context,
                  at: urb.url.pathString,
                ) { formatContext -> Track? in
                  do {
                    // We need this for formats like FLAC.
                    try findStreamInfo(formatContext)
                  } catch {
                    Logger.model.log("Could not find stream information from file at URL '\(urb.url.pathString)': \(error)")

                    return nil
                  }

                  let streami: Int32

                  do {
                    streami = try findBestStream(formatContext, type: .audio, decoder: nil)
                  } catch {
                    Logger.model.log("Could not find best stream from file at URL '\(urb.url.pathString)': \(error)")

                    return nil
                  }

                  let stream = formatContext!.pointee.streams[Int(streami)]!

                  guard let duration = duration(stream: stream, formatContext: formatContext) else {
                    Logger.model.log("Could not parse duration of stream \(stream.pointee.index) from file at URL '\(urb.url.pathString)'")

                    return nil
                  }

                  // TODO: Extract.
                  struct Position {
                    let number: Int
                    let total: Int?
                  }

                  var title: String?
                  var artistName: String?
                  var albumName: String?
                  var albumArtistName: String?
                  var albumDate: Date?
                  var track: Position?
                  var trackTotal: Int?
                  var disc: Position?
                  var discTotal: Int?

                  chain(
                    FFDictionaryIterator(formatContext!.pointee.metadata),
                    FFDictionaryIterator(stream.pointee.metadata),
                  )
                  .uniqued(on: \.pointee.key)
                  .forEach { tag in
                    func position(from value: String) -> Position? {
                      let components = value.split(separator: "/", maxSplits: 1)
                      let number: Int
                      let total: Int?

                      switch components.count {
                        case 2: // [Number]/[Total]
                          guard let first = Int(components[0]),
                                let second = Int(components[1]) else {
                            return nil
                          }

                          number = first
                          total = second
                        case 1: // [Number]
                          guard let first = Int(components[0]) else {
                            return nil
                          }

                          number = first
                          total = nil
                        default:
                          unreachable()
                      }

                      return Position(number: number, total: total)
                    }

                    let key = String(cString: tag.pointee.key)
                    let value = String(cString: tag.pointee.value)

                    switch key {
                      case "title", "TITLE":
                        title = value
                      case "artist", "ARTIST":
                        artistName = value
                      case "album", "ALBUM":
                        albumName = value
                      case "album_artist", "ALBUM_ARTIST":
                        albumArtistName = value
                      case "date", "DATE": // ORIGINALDATE and ORIGINALYEAR exist, but seem specific to MusicBrainz.
                        do {
                          albumDate = try Date(value, strategy: .iso8601.year())
                        } catch {
                          Logger.model.log("Could not parse album date from stream \(stream.pointee.index) in file at URL '\(urb.url.pathString)': \(error)")
                        }
                      case "track":
                        track = position(from: value)
                      case "disc", "DISC":
                        disc = position(from: value)
                      case "TRACKTOTAL": // TOTALTRACKS exists, but seems to always coincide with TRACKTOTAL.
                        trackTotal = Int(value)
                      case "DISCTOTAL": // TOTALDISCS exists, but is in the same situation as above.
                        discTotal = Int(value)
                      default:
                        break
                    }
                  }

                  let packet = FFPacket()
                  let artwork: LibraryTrackAlbumArtworkRecord?

                  do {
                    artwork = try read(formatContext, packet: packet.packet)
                  } catch {
                    // TODO: Elaborate.
                    Logger.model.error("\(error)")

                    return nil
                  }

                  guard let artwork else {
                    // TODO: Log.
                    return nil
                  }

                  return Track(
                    track: LibraryTrackRecord(
                      bookmark: nil,
                      title: title,
                      duration: duration,
                      isLiked: false,
                      artistName: artistName,
                      albumName: albumName,
                      albumArtistName: albumArtistName,
                      albumDate: albumDate,
                      albumArtwork: nil,
                      trackNumber: track?.number,
                      trackTotal: track?.total ?? trackTotal,
                      discNumber: disc?.number,
                      discTotal: disc?.total ?? discTotal,
                    ),
                    bookmark: BookmarkRecord(
                      data: urb.bookmark.data,
                      options: urb.bookmark.options,
                      hash: hash(data: urb.bookmark.data),
                      relative: configuration.mainLibrary.bookmark.bookmark.rowID,
                    ),
                    artwork: artwork,
                  )
                }
              } catch let error as FFError where error.code == .invalidData {
                Logger.model.log("Could not open input stream for file at URL '\(urb.url.pathString)' because the stream contains invalid data")

                return nil
              } catch let error as FFError where error.code == .isDirectory {
                Logger.model.log("Could not open input stream for file at URL '\(urb.url.pathString)' because the file is a directory")

                return nil
              } catch {
                Logger.model.error("Could not open input stream for file at URL '\(urb.url.pathString)': \(error)")

                return nil
              }
            }
          }

          do {
            try await connection.write { db in
              try tracks.forEach { track in
                var bookmark = track.bookmark
                try bookmark.upsert(db)

                var albumArtwork = track.artwork
                try albumArtwork.upsert(db)

                var track = LibraryTrackRecord(
                  rowID: track.track.rowID,
                  bookmark: bookmark.rowID,
                  title: track.track.title,
                  duration: track.track.duration,
                  isLiked: track.track.isLiked,
                  artistName: track.track.artistName,
                  albumName: track.track.albumName,
                  albumArtistName: track.track.albumArtistName,
                  albumDate: track.track.albumDate,
                  albumArtwork: albumArtwork.rowID,
                  trackNumber: track.track.trackNumber,
                  trackTotal: track.track.trackTotal,
                  discNumber: track.track.discNumber,
                  discTotal: track.track.discTotal,
                )

                try track.upsert(db)

                var trackLibrary = TrackLibraryRecord(
                  rowID: nil,
                  library: id,
                  track: track.rowID,
                )

                try trackLibrary.upsert(db)
              }

              // If we wanted to optimize the above, we could use the following code, which sidesteps GRDB's slow
              // records. This loader is passive, so it's not essential that it's the most performant. The code is much
              // faster, however (1.61 GB for 172 items on my 2019 MacBook Pro performs 850 ms -> 250 ms).

//              let bookmarksQuery: SQL = """
//                INSERT INTO \(BookmarkRecord.self) \
//                (\(BookmarkRecord.CodingKeys.rowID),\
//                  \(BookmarkRecord.CodingKeys.data),\
//                  \(BookmarkRecord.CodingKeys.options),\
//                  \(BookmarkRecord.CodingKeys.hash),\
//                  \(BookmarkRecord.CodingKeys.relative)) \
//                VALUES
//                """
//              + tracks
//                .map { track in
//                  """
//                  (\(track.bookmark.rowID), \
//                   \(track.bookmark.data),\
//                   \(track.bookmark.options?.rawValue),\
//                   \(track.bookmark.hash),\
//                   \(track.bookmark.relative))
//                  """
//                }
//                .joined(separator: ", ")
//              + """
//                ON CONFLICT DO UPDATE SET \
//                \(BookmarkRecord.CodingKeys.data) = "excluded".\(BookmarkRecord.CodingKeys.data), \
//                \(BookmarkRecord.CodingKeys.options) = "excluded".\(BookmarkRecord.CodingKeys.options), \
//                \(BookmarkRecord.CodingKeys.hash) = "excluded".\(BookmarkRecord.CodingKeys.hash), \
//                \(BookmarkRecord.CodingKeys.relative) = "excluded".\(BookmarkRecord.CodingKeys.relative) \
//                RETURNING \(BookmarkRecord.CodingKeys.rowID)
//                """
//
//              let bookmarks = try RowID.fetchAll(db, literal: bookmarksQuery)
//              let albumArtworksQuery: SQL = """
//                INSERT INTO \(LibraryTrackAlbumArtworkRecord.self) \
//                (\(LibraryTrackAlbumArtworkRecord.CodingKeys.rowID),\
//                 \(LibraryTrackAlbumArtworkRecord.CodingKeys.data),\
//                 \(LibraryTrackAlbumArtworkRecord.CodingKeys.hash),\
//                 \(LibraryTrackAlbumArtworkRecord.CodingKeys.format)) \
//                VALUES
//                """
//              + tracks
//                .map { track in
//                  """
//                  (\(track.artwork.rowID),\
//                   \(track.artwork.data),
//                   \(track.artwork.hash),
//                   \(track.artwork.format?.rawValue))
//                  """
//                }
//                .joined(separator: ", ")
//              + """
//                ON CONFLICT DO UPDATE SET \
//                \(LibraryTrackAlbumArtworkRecord.CodingKeys.data) = "excluded".\(LibraryTrackAlbumArtworkRecord.CodingKeys.data), \
//                \(LibraryTrackAlbumArtworkRecord.CodingKeys.hash) = "excluded".\(LibraryTrackAlbumArtworkRecord.CodingKeys.hash), \
//                \(LibraryTrackAlbumArtworkRecord.CodingKeys.format) = "excluded".\(LibraryTrackAlbumArtworkRecord.CodingKeys.format) \
//                RETURNING \(LibraryTrackAlbumArtworkRecord.CodingKeys.rowID)
//                """
//
//              let albumArtworks = try RowID.fetchAll(db, literal: albumArtworksQuery)
//              let tracksQuery: SQL = """
//                INSERT INTO \(LibraryTrackRecord.self) \
//                (\(LibraryTrackRecord.CodingKeys.rowID),\
//                 \(LibraryTrackRecord.CodingKeys.bookmark),\
//                 \(LibraryTrackRecord.CodingKeys.library),\
//                 \(LibraryTrackRecord.CodingKeys.title),\
//                 \(LibraryTrackRecord.CodingKeys.duration),\
//                 \(LibraryTrackRecord.CodingKeys.isLiked),\
//                 \(LibraryTrackRecord.CodingKeys.artistName),\
//                 \(LibraryTrackRecord.CodingKeys.albumName),\
//                 \(LibraryTrackRecord.CodingKeys.albumArtistName),\
//                 \(LibraryTrackRecord.CodingKeys.albumDate),\
//                 \(LibraryTrackRecord.CodingKeys.albumArtwork),\
//                 \(LibraryTrackRecord.CodingKeys.trackNumber),\
//                 \(LibraryTrackRecord.CodingKeys.trackTotal),\
//                 \(LibraryTrackRecord.CodingKeys.discNumber),\
//                 \(LibraryTrackRecord.CodingKeys.discTotal)) \
//                VALUES
//                """
//              + zip(zip(tracks, albumArtworks), bookmarks)
//                .map { items in
//                  let track = items.0.0
//                  let albumArtwork = items.0.1
//                  let bookmark = items.1
//                  
//                  return """
//                  (\(track.track.rowID),\
//                   \(bookmark),\
//                   \(track.track.library),\
//                   \(track.track.title),\
//                   \(track.track.duration),\
//                   \(track.track.isLiked),\
//                   \(track.track.artistName),\
//                   \(track.track.albumName),\
//                   \(track.track.albumArtistName),\
//                   \(track.track.albumDate),\
//                   \(albumArtwork),\
//                   \(track.track.trackNumber),\
//                   \(track.track.trackTotal),\
//                   \(track.track.discNumber),\
//                   \(track.track.discTotal))
//                  """
//                }
//                .joined(separator: ", ")
//              + """
//                ON CONFLICT DO UPDATE SET
//                \(LibraryTrackRecord.CodingKeys.bookmark) = "excluded".\(LibraryTrackRecord.CodingKeys.bookmark), \
//                \(LibraryTrackRecord.CodingKeys.library) = "excluded".\(LibraryTrackRecord.CodingKeys.library), \
//                \(LibraryTrackRecord.CodingKeys.title) = "excluded".\(LibraryTrackRecord.CodingKeys.title), \
//                \(LibraryTrackRecord.CodingKeys.duration) = "excluded".\(LibraryTrackRecord.CodingKeys.duration), \
//                \(LibraryTrackRecord.CodingKeys.artistName) = "excluded".\(LibraryTrackRecord.CodingKeys.artistName), \
//                \(LibraryTrackRecord.CodingKeys.albumName) = "excluded".\(LibraryTrackRecord.CodingKeys.albumName), \
//                \(LibraryTrackRecord.CodingKeys.albumArtistName) = "excluded".\(LibraryTrackRecord.CodingKeys.albumArtistName), \
//                \(LibraryTrackRecord.CodingKeys.albumDate) = "excluded".\(LibraryTrackRecord.CodingKeys.albumDate), \
//                \(LibraryTrackRecord.CodingKeys.albumArtwork) = "excluded".\(LibraryTrackRecord.CodingKeys.albumArtwork), \
//                \(LibraryTrackRecord.CodingKeys.trackNumber) = "excluded".\(LibraryTrackRecord.CodingKeys.trackNumber), \
//                \(LibraryTrackRecord.CodingKeys.trackTotal) = "excluded".\(LibraryTrackRecord.CodingKeys.trackTotal), \
//                \(LibraryTrackRecord.CodingKeys.discNumber) = "excluded".\(LibraryTrackRecord.CodingKeys.discNumber), \
//                \(LibraryTrackRecord.CodingKeys.discTotal) = "excluded".\(LibraryTrackRecord.CodingKeys.discTotal)
//                """
//
//              try db.execute(literal: tracksQuery)
            }
          } catch {
            Logger.model.error("Could not write library tracks to database: \(error)")
          }
        }
      }
    }
  } catch {
    Logger.model.error("Could not observe changes to library folder in database: \(error)")

    return
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
    // TODO: Clarify uniqueness constraints and their affects on associated tables.

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
        .indexed()
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

      table
        .column(LibraryTrackAlbumArtworkRecord.Columns.format.name, .integer)
        .notNull()
    }

    try db.create(table: LibraryTrackRecord.databaseTableName) { table in
      table.primaryKey(Column.rowID.name, .integer)
      table
        .column(LibraryTrackRecord.Columns.bookmark.name, .integer)
        .notNull()
        .unique()
        .references(BookmarkRecord.databaseTableName)

      table.column(LibraryTrackRecord.Columns.title.name, .text)

      table
        .column(LibraryTrackRecord.Columns.duration.name, .integer)
        .notNull()

      table
        .column(LibraryTrackRecord.Columns.isLiked.name, .boolean)
        .notNull()

      table.column(LibraryTrackRecord.Columns.artistName.name, .text)
      table.column(LibraryTrackRecord.Columns.albumName.name, .text)
      table.column(LibraryTrackRecord.Columns.albumArtistName.name, .text)
      table.column(LibraryTrackRecord.Columns.albumDate.name, .text)

      table
        .column(LibraryTrackRecord.Columns.albumArtwork.name, .integer)
        .references(LibraryTrackAlbumArtworkRecord.databaseTableName)
        .indexed()

      table.column(LibraryTrackRecord.Columns.trackNumber.name, .integer)
      table.column(LibraryTrackRecord.Columns.trackTotal.name, .integer)
      table.column(LibraryTrackRecord.Columns.discNumber.name, .integer)
      table.column(LibraryTrackRecord.Columns.discTotal.name, .integer)
    }

    try db.create(virtualTable: LibraryTrackFTRecord.databaseTableName, using: FTS5()) { table in
      table.synchronize(withTable: LibraryTrackRecord.databaseTableName)
      table.column(LibraryTrackFTRecord.Columns.title.name)
      table.column(LibraryTrackFTRecord.Columns.artistName.name)
      table.column(LibraryTrackFTRecord.Columns.albumName.name)
      table.column(LibraryTrackFTRecord.Columns.albumArtistName.name)
    }

    try db.create(table: LibraryQueueItemRecord.databaseTableName) { table in
      table.primaryKey(Column.rowID.name, .integer)
      table
        .column(LibraryQueueItemRecord.Columns.track.name, .integer)
        .notNull()
        .references(LibraryTrackRecord.databaseTableName)
        .indexed()

      table
        .column(LibraryQueueItemRecord.Columns.position.name, .integer)
        .notNull()

//      table.uniqueKey([LibraryQueueItemRecord.Columns.queue.name, LibraryQueueItemRecord.Columns.position.name])
    }

    try db.create(table: LibraryQueueRecord.databaseTableName) { table in
      table.primaryKey(Column.rowID.name, .integer)
      // Should this be unique?
      table
        .column(LibraryQueueRecord.Columns.currentItem.name, .integer)
        .references(LibraryQueueItemRecord.databaseTableName)
        .indexed()
    }

    try db.create(table: LibraryRecord.databaseTableName) { table in
      table.primaryKey(Column.rowID.name, .integer)
      table
        .column(LibraryRecord.Columns.bookmark.name, .integer)
        .notNull()
        .unique()
        .references(BookmarkRecord.databaseTableName)

      // TODO: Check that this exists in queue_libraries and corresponds to the library.
      table
        .column(LibraryRecord.Columns.currentQueue.name, .integer)
        .references(LibraryQueueRecord.databaseTableName)
        .indexed()
    }

    try db.create(table: TrackLibraryRecord.databaseTableName) { table in
      table.primaryKey(Column.rowID.name, .integer)
      table
        .column(TrackLibraryRecord.Columns.library.name, .integer)
        .notNull()
        .references(LibraryRecord.databaseTableName)
        .indexed()

      table
        .column(TrackLibraryRecord.Columns.track.name, .integer)
        .notNull()
        .unique()
        .references(LibraryTrackRecord.databaseTableName)
    }

    try db.create(table: ItemLibraryQueueRecord.databaseTableName) { table in
      table.primaryKey(Column.rowID.name, .integer)
      table
        .column(ItemLibraryQueueRecord.Columns.queue.name, .integer)
        .notNull()
        .references(LibraryQueueRecord.databaseTableName)
        .indexed()

      table
        .column(ItemLibraryQueueRecord.Columns.item.name, .integer)
        .notNull()
        .unique()
        .references(LibraryQueueItemRecord.databaseTableName)
    }

    try db.create(table: QueueLibraryRecord.databaseTableName) { table in
      table.primaryKey(Column.rowID.name, .integer)
      table
        .column(QueueLibraryRecord.Columns.library.name, .integer)
        .notNull()
        .references(LibraryRecord.databaseTableName)
        .indexed()

      table
        .column(QueueLibraryRecord.Columns.queue.name, .integer)
        .notNull()
        .unique()
        .references(LibraryQueueRecord.databaseTableName)
    }

//    try db.execute(
//      literal: """
//      CREATE TRIGGER BEFORE INSERT ON \(ItemLibraryQueueRecord.self) FOR EACH ROW WHEN \
//      (SELECT EXISTS (\
//      SELECT 1 FROM \(ItemLibraryQueueRecord.self) \
//      
//      WHERE \(ItemLibraryQueueRecord.Columns.queue) = new.\(ItemLibraryQueueRecord.Columns.queue)
//      INNER JOIN \(LibraryQueueItemRecord.self) ON \(LibraryQueueItemRecord.Columns.position) = \(ItemLibraryQueueRecord.self) WHERE \(ItemLibraryQueueRecord.Columns.queue) = new.\(ItemLibraryQueueRecord.Columns.queue)))
//      """,
//    )

    try db.create(table: ConfigurationRecord.databaseTableName) { table in
      table
        .primaryKey(Column.rowID.name, .integer)
        .check { $0 == ConfigurationRecord.default.rowID }

      table
        .column(ConfigurationRecord.Columns.mainLibrary.name, .integer)
        .references(LibraryRecord.databaseTableName)
        .indexed()
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

  Task {
    await load(connection: connection)
  }

  return connection
}
