//
//  Data+Core.swift
//  Sampled
//
//  Created by Kyle Erhabor on 8/17/25.
//

import CFFmpeg
import SampledCore
import Algorithms
import Foundation
import GRDB
import OSLog

// MARK: - Foundation

extension URL {
  static let dataDirectory = Self.applicationSupportDirectory.appending(
    components: Bundle.appID,
    directoryHint: .isDirectory,
  )

  static let databaseFile = Self.dataDirectory
    .appending(components: "Database", "Data", directoryHint: .notDirectory)
    .appendingPathExtension("sqlite3")
}

// MARK: -

extension Logger {
  static let data = Self(subsystem: Bundle.appID, category: "Data")
}

actor Once<Value, each Argument> where Value: Sendable {
  private let body: (repeat each Argument) async throws -> Value
  private var task: Task<Value, any Error>?

  init(_ body: @escaping (repeat each Argument) async throws -> Value) {
    self.body = body
  }

  func callAsFunction(_ args: repeat each Argument) async throws -> Value {
    if let task = self.task {
      return try await task.value
    }

    let task = Task {
      try await self.body(repeat each args)
    }

    self.task = task

    do {
      return try await task.value
    } catch {
      // Try again on the next call.
      self.task = nil

      throw error
    }
  }
}

extension DatabaseValueConvertible {
  static func fetchAll(_ db: Database, literal: SQL) throws -> [Self] {
    let (sql, arguments) = try literal.build(db)
    let results = try Self.fetchAll(db, sql: sql, arguments: arguments)

    return results
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
    try readFrame(context, packet: packet)

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
  let codecContext = CodecContext(codec: decoder)
  try copyCodecParameters(codecContext.context, parameters: stream.pointee.codecpar)
  try openCodec(codecContext.context, codec: decoder)

  let attachedPicture = try readAttachedPicturePacket(formatContext, stream: stream, packet: packet)
  let codecID = CodecID(stream.pointee.codecpar.pointee.codec_id)

  guard let format = LibraryTrackAlbumArtworkFormat(codecID: codecID) else {
    Logger.model.log("Could not create library track album artwork format from codec ID \(codecID.rawValue) (\(String(cString: codecID.name))))")

    return nil
  }

  let data = UnsafeBufferPointer(start: attachedPicture.pointee.data, count: Int(attachedPicture.pointee.size))
  let hash = hash(data: data)

  return LibraryTrackAlbumArtworkRecord(data: Data(data), hash: hash, format: format)
}

struct LoadTrack {
  let track: LibraryTrackRecord
  let bookmark: BookmarkRecord
  let artwork: LibraryTrackAlbumArtworkRecord
}

struct LoadPosition {
  let number: Int
  let total: Int?
}

nonisolated(nonsending) private func load(contents: some Sequence<URL>, relativeTo relative: URL) async -> [URLBookmark] {
  var urbs = [URLBookmark]()

  for content in contents {
    do {
      urbs.append(try await URLBookmark(url: content, options: [.withoutImplicitSecurityScope], relativeTo: relative))
    } catch {
      // TODO: Elaborate.
      Logger.model.error("\(error)")

      continue
    }
  }

  return urbs
}

private func load(connection: some DatabaseWriter) async {
  let observation = ValueObservation
    .trackingConstantRegion { db in
      try ConfigurationRecord
        .select(.rowID)
        .including(
          required: ConfigurationRecord.mainLibrary
            .forKey(DatabaseLoadConfigurationInfo.CodingKeys.mainLibrary)
            .select(.rowID)
            .including(
              required: LibraryRecord.fileBookmark
                .forKey(DatabaseLoadConfigurationMainLibraryInfo.CodingKeys.fileBookmark)
                .select(.rowID)
                .including(
                  required: FileBookmarkRecord.bookmark
                    .forKey(DatabaseLoadConfigurationMainLibraryFileBookmarkInfo.CodingKeys.bookmark)
                    .select(.rowID, BookmarkRecord.Columns.data, BookmarkRecord.Columns.options),
                )
            ),
        )
        .asRequest(of: DatabaseLoadConfigurationInfo.self)
        .fetchOne(db)
    }

  var stream = AsyncStream<LibraryModelEventStreamElement>.makeStream()

  do {
    for try await configuration in observation.values(in: connection) {
      guard let configuration else {
        continue
      }

      let id = configuration.mainLibrary.library.rowID!
      let options = configuration.mainLibrary.fileBookmark.bookmark.bookmark.options!
      let assigned: AssignedBookmark

      do {
        assigned = try await AssignedBookmark(
          data: configuration.mainLibrary.fileBookmark.bookmark.bookmark.data!,
          options: options,
          relativeTo: nil,
        )
      } catch {
        // TODO: Elaborate.
        Logger.model.error("\(error)")

        continue
      }

      UserDefaults.standard.set(assigned.resolved.url, forKey: StorageKeys.libraryFolder.name)

      guard !assigned.resolved.isStale else {
        do {
          try await connection.write { db in
            let bookmark = BookmarkRecord(
              rowID: configuration.mainLibrary.fileBookmark.bookmark.bookmark.rowID,
              data: assigned.data,
              options: nil,
            )

            // Is it possible for this to throw?
            try bookmark.update(db, columns: [BookmarkRecord.Columns.data])
          }
        } catch {
          // TODO: Log.
          Logger.model.error("Could not write to database: \(error)")
        }

        continue
      }

      // I'm surprised file system events does not require a security scope.
      stream.continuation.finish()

      stream = AsyncStream<LibraryModelEventStreamElement>.makeStream()
      stream.continuation.yield(.initial)

      let eventStream = EventStream()
      let eventStreamCreated = eventStream.create(forFileAt: assigned.resolved.url, latency: 1) { events in
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
          let source = URLSource(url: assigned.resolved.url, options: options)
          let tracks = await source.accessingSecurityScopedResource {
            let directoryEnumerationOptions: FileManager.DirectoryEnumerationOptions = [
              .skipsHiddenFiles,
              .skipsPackageDescendants,
            ]

            var urbs = [URLBookmark]()

            switch element {
              case .initial:
                guard let contents = FileManager.default.enumerate(
                        at: source.url,
                        options: directoryEnumerationOptions,
                      ) else {
                  // TODO: Log.
                  break
                }

                urbs.append(contentsOf: await load(contents: contents, relativeTo: source.url))
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
                  var options = directoryEnumerationOptions

                  if !flags.contains(.mustScanSubdirectories) {
                    options.insert(.skipsSubdirectoryDescendants)
                  }

                  guard let contents = FileManager.default.enumerate(at: source.url, options: options) else {
                    // TODO: Log.
                    continue
                  }

                  urbs.append(contentsOf: await load(contents: contents, relativeTo: source.url))
                }
            }

            return urbs.compactMap { urb -> LoadTrack? in
              let formatContext = FormatContext()

              do {
                return try formatContext.openingInput(at: urb.url.pathString) { formatContext -> LoadTrack? in
                  do {
                    // We need this for formats like FLAC.
                    try findStreamInfo(formatContext.context)
                  } catch {
                    Logger.model.log("Could not find stream information from file at URL '\(urb.url.pathString)': \(error)")

                    return nil
                  }

                  var decoder: UnsafePointer<AVCodec>!
                  let streami: Int32

                  do {
                    streami = try findBestStream(formatContext.context, type: .audio, decoder: &decoder)
                  } catch {
                    Logger.model.log("Could not find best stream from file at URL '\(urb.url.pathString)': \(error)")

                    return nil
                  }

                  let stream = formatContext.context.pointee.streams[Int(streami)]!

                  guard let duration = duration(stream: stream, formatContext: formatContext.context) else {
                    Logger.model.log("Could not parse duration of stream \(stream.pointee.index) from file at URL '\(urb.url.pathString)'")

                    return nil
                  }

                  var title: String?
                  var artistName: String?
                  var albumName: String?
                  var albumArtistName: String?
                  var albumDate: Date?
                  var track: LoadPosition?
                  var trackTotal: Int?
                  var disc: LoadPosition?
                  var discTotal: Int?

                  chain(
                    FFDictionaryIterator(formatContext.context.pointee.metadata),
                    FFDictionaryIterator(stream.pointee.metadata),
                  )
                  .uniqued(on: \.pointee.key)
                  .forEach { tag in
                    func position(from value: String) -> LoadPosition? {
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

                      return LoadPosition(number: number, total: total)
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

                  let packet = Packet()
                  let artwork: LibraryTrackAlbumArtworkRecord?

                  do {
                    artwork = try read(formatContext.context, packet: packet.packet)
                  } catch {
                    // TODO: Elaborate.
                    Logger.model.error("\(error)")

                    return nil
                  }

                  guard let artwork else {
                    // TODO: Log.
                    return nil
                  }

                  return LoadTrack(
                    track: LibraryTrackRecord(
                      fileBookmark: nil,
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
                  fileBookmark: bookmark.rowID,
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
    Logger.model.error("Could not read from database: \(error)")

    return
  }
}

func createFileBookmarkSchemaAction(_ db: Database) throws {
  try db.execute(
    literal: """
      CREATE TRIGGER \(sql: "\(FileBookmarkRecord.databaseTableName)_ad".quotedDatabaseIdentifier)
      AFTER DELETE ON \(FileBookmarkRecord.self)
      FOR EACH ROW
      BEGIN
        DELETE FROM \(BookmarkRecord.self)
        WHERE \(BookmarkRecord.self).\(.rowID) = OLD.\(FileBookmarkRecord.Columns.bookmark);
      END
      """,
  )
}

func createSchema(_ connection: some DatabaseWriter) async throws {
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
    }

    try db.create(table: FileBookmarkRecord.databaseTableName) { table in
      table.primaryKey(Column.rowID.name, .integer)
      table
        .column(FileBookmarkRecord.Columns.bookmark.name, .integer)
        .notNull()
        .unique()
        .references(BookmarkRecord.databaseTableName)

      table
        .column(FileBookmarkRecord.Columns.relative.name, .integer)
        .references(BookmarkRecord.databaseTableName)
        .indexed()
    }

    try createFileBookmarkSchemaAction(db)
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
        .column(LibraryTrackRecord.Columns.fileBookmark.name, .integer)
        .notNull()
        .unique()
        .references(FileBookmarkRecord.databaseTableName)

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
        .column(LibraryQueueItemRecord.Columns.position.name, .text)
        .notNull()
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
        .column(LibraryRecord.Columns.fileBookmark.name, .integer)
        .notNull()
        .unique()
        .references(FileBookmarkRecord.databaseTableName)

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

    try db.execute(
      literal: """
      CREATE TRIGGER unique_library_queue_item_position \
      BEFORE INSERT ON \(ItemLibraryQueueRecord.self) \
      FOR EACH ROW \
      WHEN EXISTS (\
      SELECT 1 FROM \(ItemLibraryQueueRecord.self) \
      INNER JOIN \(LibraryQueueItemRecord.self) AS item ON item.\(Column.rowID) = \(ItemLibraryQueueRecord.self).\(ItemLibraryQueueRecord.Columns.item) \
      INNER JOIN \(LibraryQueueItemRecord.self) AS new_item ON new_item.\(Column.rowID) = new.\(ItemLibraryQueueRecord.Columns.item) \
      WHERE \(ItemLibraryQueueRecord.self).\(ItemLibraryQueueRecord.Columns.queue) = new.\(ItemLibraryQueueRecord.Columns.queue) AND item.\(LibraryQueueItemRecord.Columns.position) = new_item.\(LibraryQueueItemRecord.Columns.position)\
      ) \
      BEGIN \
      SELECT RAISE(ABORT, '\(ItemLibraryQueueRecord.self).\(ItemLibraryQueueRecord.Columns.item).\(LibraryQueueItemRecord.Columns.position) already exists'); \
      END;
      """,
    )

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

    // It's a little annoying that we're letting defaults leak into data, which is for UI.
    UserDefaults.standard.removeObject(forKey: StorageKeys.libraryFolder.name)
  }

  #endif

  try migrator.migrate(connection)
}

extension GRDB.Configuration {
  static var standard: Self {
    var configuration = Self()

    #if DEBUG
    configuration.publicStatementArguments = true

    #endif

    configuration.prepareDatabase { db in
      #if DEBUG
      db.trace(options: .profile) { trace in
        Logger.data.debug("SQL> \(trace)")
      }

      #endif

      guard !db.configuration.readonly else {
        return
      }

      // This will execute twice: once for creating the database connection, and another for schema migration.
      try db.execute(literal: "VACUUM")
    }

    return configuration
  }
}

func createDatabaseConnection(at url: URL, configuration: GRDB.Configuration) throws -> DatabasePool {
  let path = url.pathString

  do {
    return try DatabasePool(path: path, configuration: configuration)
  } catch let error as DatabaseError where error.resultCode == .SQLITE_CANTOPEN {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

    return try DatabasePool(path: path, configuration: configuration)
  }
}

let databaseConnection = Once {
  let url = URL.databaseFile
  let configuration = GRDB.Configuration.standard
  let connection = try createDatabaseConnection(at: url, configuration: configuration)
  try await createSchema(connection)

  Task {
    await load(connection: connection)
  }

  return connection
}
