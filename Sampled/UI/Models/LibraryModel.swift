//
//  LibraryModel.swift
//  Sampled
//
//  Created by Kyle Erhabor on 11/6/24.
//

import CFFmpeg
import CoreFFmpeg
import SampledFFmpeg
import Algorithms
import AppKit
import CoreGraphics
import Foundation
import GRDB
import IdentifiedCollections
import Observation
import OSLog

private func duration(
  _ context: UnsafePointer<AVFormatContext>!,
  stream: UnsafePointer<AVStream>!,
) -> Double? {
  // Some formats (like Matroska) have the stream duration set to AV_NOPTS_VALUE, while exposing the real
  // value in the format context.

  if let duration = duration(stream.pointee.duration) {
    return Double(duration) * av_q2d(stream.pointee.time_base)
  }

  if let duration = duration(context.pointee.duration) {
    return Double(duration * Int64(AV_TIME_BASE))
  }

  return nil
}

private func readAttachedPicturePacket(
  _ context: UnsafeMutablePointer<AVFormatContext>!,
  stream: UnsafeMutablePointer<AVStream>,
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

private func readAttachedPicture(
  _ context: UnsafeMutablePointer<AVFormatContext>!,
  packet: UnsafeMutablePointer<AVPacket>!,
) throws(FFError) -> UnsafePointer<AVPacket>? {
  var decoder: UnsafePointer<AVCodec>!
  let streami: Int32

  do {
    streami = try findBestStream(context, type: .video, decoder: &decoder)
  } catch let error where error.code == .streamNotFound {
    Logger.model.error("Could not find best video stream for attached picture")

    return nil
  }

  let stream = context.pointee.streams[Int(streami)]!
  let codecContext = FFCodecContext(codec: decoder)
  try copyCodecParameters(codecContext.context, params: stream.pointee.codecpar)
  try openCodec(codecContext.context, codec: decoder)

  return try readAttachedPicturePacket(context, stream: stream, packet: packet)
}

struct LibraryModelTrackInfo {
  let track: LibraryTrackRecord
  let bookmark: BookmarkRecord
  let artwork: LibraryTrackAlbumArtworkRecord
}

// TODO: Rename.
private func read(
  _ formatContext: UnsafeMutablePointer<AVFormatContext>!,
  packet: UnsafeMutablePointer<AVPacket>!,
) throws(FFError) -> LibraryTrackAlbumArtworkRecord? {
  guard let packet = try readAttachedPicture(formatContext, packet: packet) else {
    return nil
  }

  let data = UnsafeBufferPointer(start: packet.pointee.data, count: Int(packet.pointee.size))
  let hash = hash(data: data)

  return LibraryTrackAlbumArtworkRecord(data: Data(data), hash: hash)
}

struct EventStreamEventFlags: OptionSet {
  var rawValue: Int

  static let mustScanSubdirectories = Self(rawValue: kFSEventStreamEventFlagMustScanSubDirs)
}


struct EventStreamEvents {
  let count: Int
  let paths: [URL]
  let flags: [EventStreamEventFlags]
}

final class EventStream {
  typealias Action = (EventStreamEvents) -> Void

  private let queue = DispatchQueue(label: "\(Bundle.appID).EventStream", target: .global())
  private var stream: FSEventStreamRef?
  private var action: Action?

  deinit {
    queue.sync {
      guard let stream else {
        return
      }

      FSEventStreamInvalidate(stream)
    }
  }

  func create(forFileAt fileURL: URL, latency: Double, _ action: @escaping Action) -> Bool {
    queue.sync {
      self.action = action

      var context = FSEventStreamContext(
        version: 0,
        info: Unmanaged.passUnretained(self).toOpaque(),
        retain: { info in
          _ = Unmanaged<EventStream>.fromOpaque(info!).retain()

          return info
        },
        release: { info in
          Unmanaged<EventStream>.fromOpaque(info!).release()
        },
        copyDescription: nil,
      )

      guard let stream = FSEventStreamCreate(
        nil,
        { eventStream, info, eventCount, eventPaths, eventFlags, eventIDs in
          let this = Unmanaged<EventStream>.fromOpaque(info!).takeUnretainedValue()
          let eventPaths = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
          this.action!(
            EventStreamEvents(
              count: eventCount,
              paths: UnsafeBufferPointer(start: eventPaths, count: eventCount)
                .map { URL(fileURLWithFileSystemRepresentation: $0, isDirectory: true, relativeTo: nil) },
              flags: UnsafeBufferPointer(start: eventFlags, count: eventCount)
                .map { EventStreamEventFlags(rawValue: Int($0)) },
            ),
          )
        },
        &context,
        [fileURL.pathString] as CFArray,
        // TODO: Accept as a parameter.
        //
        // If we replace the event stream, we want to start at the last event ID, rather than the current one.
        FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
        latency,
        // We could use kFSEventStreamCreateFlagFileEvents to subscribe to individual files, but we're already notified
        // about changes to the directory, and we need to check it for flags like kFSEventStreamEventFlagMustScanSubDirs,
        // so we may as well eat the cost of enumerating directories.
        FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot),
      ) else {
        return false
      }

      // Should we let the user set the dispatch queue?
      FSEventStreamSetDispatchQueue(stream, .global())

      self.stream = stream

      return true
    }
  }

  func start() -> Bool {
    queue.sync {
      guard let stream else {
        return false
      }

      return FSEventStreamStart(stream)
    }
  }

  func stop() {
    queue.sync {
      guard let stream else {
        return
      }

      FSEventStreamStop(stream)
    }
  }
}

extension EventStream: @unchecked Sendable {}

enum LibraryModelEventStreamElement {
  case initial, events(EventStreamEvents)
}

@Observable
@MainActor
final class LibraryTrackModel {
  private let rowID: RowID
  var source: URLSource
  var title: String?
  var duration: Duration
  var artistName: String?
  var albumName: String?
  var albumArtistName: String?
  var albumDate: Date?
  var albumArtworkData: Data?
  var albumArtworkHash: Data?
  var trackNumber: Int?
  var trackTotal: Int?
  var discNumber: Int?
  var discTotal: Int?

  init(
    rowID: RowID,
    source: URLSource,
    title: String?,
    duration: Duration,
    artistName: String?,
    albumName: String?,
    albumArtistName: String?,
    albumDate: Date?,
    albumArtworkData: Data?,
    albumArtworkHash: Data?,
    trackNumber: Int?,
    trackTotal: Int?,
    discNumber: Int?,
    discTotal: Int?,
  ) {
    self.rowID = rowID
    self.source = source
    self.title = title
    self.duration = duration
    self.artistName = artistName
    self.albumName = albumName
    self.albumArtistName = albumArtistName
    self.albumDate = albumDate
    self.albumArtworkData = albumArtworkData
    self.albumArtworkHash = albumArtworkHash
    self.trackNumber = trackNumber
    self.trackTotal = trackTotal
    self.discNumber = discNumber
    self.discTotal = discTotal
  }
}

extension LibraryTrackModel: @MainActor Identifiable {
  var id: RowID {
    self.rowID
  }
}

struct LibraryModelLoadConfigurationMainLibraryBookmarkInfo {
  let bookmark: BookmarkRecord
}

extension LibraryModelLoadConfigurationMainLibraryBookmarkInfo: Equatable, Decodable, FetchableRecord {}

struct LibraryModelLoadConfigurationMainLibraryTrackBookmarkInfo {
  let bookmark: BookmarkRecord
}

extension LibraryModelLoadConfigurationMainLibraryTrackBookmarkInfo: Equatable, Decodable, FetchableRecord {}

struct LibraryModelLoadConfigurationMainLibraryTrackAlbumArtworkInfo {
  let albumArtwork: LibraryTrackAlbumArtworkRecord
}

extension LibraryModelLoadConfigurationMainLibraryTrackAlbumArtworkInfo: Equatable, Decodable, FetchableRecord {}

struct LibraryModelLoadConfigurationMainLibraryTrackInfo {
  let track: LibraryTrackRecord
  let bookmark: LibraryModelLoadConfigurationMainLibraryTrackBookmarkInfo
  let albumArtwork: LibraryModelLoadConfigurationMainLibraryTrackAlbumArtworkInfo?
}

extension LibraryModelLoadConfigurationMainLibraryTrackInfo: Decodable {
  enum CodingKeys: String, CodingKey {
    case track,
         bookmark = "_bookmark",
         albumArtwork
  }
}

extension LibraryModelLoadConfigurationMainLibraryTrackInfo: Equatable, FetchableRecord {}

struct LibraryModelLoadConfigurationMainLibraryInfo {
  let library: LibraryRecord
  let bookmark: LibraryModelLoadConfigurationMainLibraryBookmarkInfo
  let tracks: [LibraryModelLoadConfigurationMainLibraryTrackInfo]
}

extension LibraryModelLoadConfigurationMainLibraryInfo: Decodable {
  enum CodingKeys: String, CodingKey {
    case library,
         bookmark = "_bookmark",
         tracks
  }
}

extension LibraryModelLoadConfigurationMainLibraryInfo: Equatable, FetchableRecord {}

struct LibraryModelLoadConfigurationInfo {
  let mainLibrary: LibraryModelLoadConfigurationMainLibraryInfo
}

extension LibraryModelLoadConfigurationInfo: Decodable {
  enum CodingKeys: CodingKey {
    case mainLibrary
  }
}

extension LibraryModelLoadConfigurationInfo: Equatable, FetchableRecord {}

struct LibraryModelLoadDataConfigurationMainLibraryBookmarkInfo {
  let bookmark: BookmarkRecord
}

extension LibraryModelLoadDataConfigurationMainLibraryBookmarkInfo: Equatable, Decodable, FetchableRecord {}

struct LibraryModelLoadDataConfigurationMainLibraryInfo {
  let library: LibraryRecord
  let bookmark: LibraryModelLoadDataConfigurationMainLibraryBookmarkInfo
}

extension LibraryModelLoadDataConfigurationMainLibraryInfo: Decodable {
  enum CodingKeys: String, CodingKey {
    case library,
         bookmark = "_bookmark"
  }
}

extension LibraryModelLoadDataConfigurationMainLibraryInfo: Equatable, FetchableRecord {}

struct LibraryModelLoadDataConfigurationInfo {
  let mainLibrary: LibraryModelLoadDataConfigurationMainLibraryInfo
}

extension LibraryModelLoadDataConfigurationInfo: Decodable {
  enum CodingKeys: CodingKey {
    case mainLibrary
  }
}

extension LibraryModelLoadDataConfigurationInfo: Equatable, FetchableRecord {}

@Observable
@MainActor
final class LibraryModel {
  var tracks = IdentifiedArrayOf<LibraryTrackModel>()
  @ObservationIgnored private var eventStream: AsyncStreamContinuationPair<LibraryModelEventStreamElement>?

  func load() async {
    let observation = ValueObservation
      .trackingConstantRegion { db in
        try ConfigurationRecord
          .including(
            required: ConfigurationRecord.mainLibraryAssociation
              .forKey(LibraryModelLoadConfigurationInfo.CodingKeys.mainLibrary)
              .including(
                required: LibraryRecord.bookmarkAssociation
                  .forKey(LibraryModelLoadConfigurationMainLibraryInfo.CodingKeys.bookmark)
                  .select(BookmarkRecord.Columns.data, BookmarkRecord.Columns.options, BookmarkRecord.Columns.hash),
              )
              .including(
                all: LibraryRecord.tracksAssociation
                  .forKey(LibraryModelLoadConfigurationMainLibraryInfo.CodingKeys.tracks)
                  .select(
                    Column.rowID,
                    LibraryTrackRecord.Columns.title,
                    LibraryTrackRecord.Columns.duration,
                    LibraryTrackRecord.Columns.artistName,
                    LibraryTrackRecord.Columns.albumName,
                    LibraryTrackRecord.Columns.albumArtistName,
                    LibraryTrackRecord.Columns.albumDate,
                    LibraryTrackRecord.Columns.trackNumber,
                    LibraryTrackRecord.Columns.trackTotal,
                    LibraryTrackRecord.Columns.discNumber,
                    LibraryTrackRecord.Columns.discTotal,
                  )
                  .including(
                    required: LibraryTrackRecord.bookmarkAssociation
                      .forKey(LibraryModelLoadConfigurationMainLibraryTrackInfo.CodingKeys.bookmark)
                      .select(BookmarkRecord.Columns.data, BookmarkRecord.Columns.options, BookmarkRecord.Columns.hash),
                  )
                  .including(
                    optional: LibraryTrackRecord.albumArtworkAssociation
                      .forKey(LibraryModelLoadConfigurationMainLibraryTrackInfo.CodingKeys.albumArtwork)
                      .select(LibraryTrackAlbumArtworkRecord.Columns.data, LibraryTrackAlbumArtworkRecord.Columns.hash),
                  ),
              ),
          )
          .asRequest(of: LibraryModelLoadConfigurationInfo.self)
          .fetchOne(db)
      }
      .removeDuplicates()

    let conn: DatabasePool

    do {
      conn = try await connection()
    } catch {
      Logger.model.error("Could not create database connection: \(error)")

      return
    }

    do {
      for try await configuration in observation.values(in: conn) {
        guard let configuration else {
          continue
        }

        let options = configuration.mainLibrary.bookmark.bookmark.options!
        let assigned: AssignedBookmark

        do {
          assigned = try AssignedBookmark(
            data: configuration.mainLibrary.bookmark.bookmark.data!,
            options: URL.BookmarkResolutionOptions(options),
            relativeTo: nil,
          ) { url in
            let source = URLSource(url: url, options: options)

            return try source.accessingSecurityScopedResource {
              try source.url.bookmarkData(options: source.options)
            }
          }
        } catch {
          // TODO: Elaborate.
          Logger.model.error("\(error)")

          continue
        }

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
              )

              try library.update(db)
            }
          } catch {
            // TODO: Log.
            Logger.model.error("\(error)")
          }

          continue
        }

        // TODO: Extract.
        struct Track {
          let track: LibraryModelLoadConfigurationMainLibraryTrackInfo
          let bookmark: BookmarkRecord
          let source: URLSource
        }

        let tracks = configuration.mainLibrary.tracks.compactMap { track -> Track? in
          let options = track.bookmark.bookmark.options!
          let bookmark: AssignedBookmark

          do {
            bookmark = try AssignedBookmark(
              data: track.bookmark.bookmark.data!,
              options: URL.BookmarkResolutionOptions(options),
              relativeTo: assigned.url,
            ) { url in
              let source = URLSource(url: url, options: options)
              let data = try source.accessingSecurityScopedResource {
                try url.bookmarkData(options: options, relativeTo: assigned.url)
              }

              return data
            }
          } catch {
            // TODO: Elaborate.
            Logger.model.error("\(error)")

            return nil
          }

          return Track(
            track: track,
            bookmark: BookmarkRecord(
              rowID: nil,
              data: bookmark.data,
              options: options,
              hash: hash(data: bookmark.data),
              relative: configuration.mainLibrary.library.rowID,
            ),
            source: URLSource(url: bookmark.url, options: options),
          )
        }

        guard tracks.allSatisfy({ $0.track.bookmark.bookmark.hash == $0.bookmark.hash }) else {
          do {
            try await conn.write { db in
              try tracks.forEach { track in
                var bookmark = track.bookmark
                try bookmark.upsert(db)

                let track = LibraryTrackRecord(
                  rowID: track.track.track.rowID,
                  bookmark: bookmark.rowID,
                  library: track.track.track.library,
                  title: track.track.track.title,
                  duration: track.track.track.duration,
                  artistName: track.track.track.artistName,
                  albumName: track.track.track.albumName,
                  albumArtistName: track.track.track.albumArtistName,
                  albumDate: track.track.track.albumDate,
                  albumArtwork: track.track.albumArtwork?.albumArtwork.rowID,
                  trackNumber: track.track.track.trackNumber,
                  trackTotal: track.track.track.trackTotal,
                  discNumber: track.track.track.discNumber,
                  discTotal: track.track.track.discTotal,
                )

                try track.update(db)
              }
            }
          } catch {
            // TODO: Log.
            Logger.model.error("\(error)")
          }

          continue
        }

        self.tracks = tracks.reduce(
          into: IdentifiedArrayOf<LibraryTrackModel>(minimumCapacity: tracks.count)
        ) { partialResult, track in
          let rowID = track.track.track.rowID!
          let duration = track.track.track.duration!
          let model = self.tracks[id: rowID].map { model in
            model.title = track.track.track.title
            model.duration = Duration.seconds(duration)
            model.artistName = track.track.track.artistName
            model.albumName = track.track.track.albumName
            model.albumArtistName = track.track.track.albumArtistName
            model.albumDate = track.track.track.albumDate
            model.albumArtworkData = track.track.albumArtwork?.albumArtwork.data
            model.albumArtworkHash = track.track.albumArtwork?.albumArtwork.hash
            model.trackNumber = track.track.track.trackNumber
            model.trackTotal = track.track.track.trackTotal
            model.discNumber = track.track.track.discNumber
            model.discTotal = track.track.track.discTotal

            return model
          } ?? LibraryTrackModel(
            rowID: rowID,
            source: track.source,
            title: track.track.track.title,
            duration: Duration.seconds(duration),
            artistName: track.track.track.artistName,
            albumName: track.track.track.albumName,
            albumArtistName: track.track.track.albumArtistName,
            albumDate: track.track.track.albumDate,
            albumArtworkData: track.track.albumArtwork?.albumArtwork.data,
            albumArtworkHash: track.track.albumArtwork?.albumArtwork.hash,
            trackNumber: track.track.track.trackNumber,
            trackTotal: track.track.track.trackTotal,
            discNumber: track.track.track.discNumber,
            discTotal: track.track.track.discTotal,
          )

          partialResult.append(model)
        }
      }
    } catch {
      Logger.model.error("Could not observe changes to library folder in database: \(error)")

      return
    }
  }

  // TODO: Rename.
  func load(enumerator: FileManager.DirectoryEnumerator, relativeTo relative: URL) -> [URLBookmark] {
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

  // TODO: Detach from UI.
  //
  // This is for data, so it makes no sense that it's called from the task modifier in SwiftUI. This should either run
  // at startup or database initialization.
  func loadData() async {
    let observation = ValueObservation
      .trackingConstantRegion { db in
        try ConfigurationRecord
          .including(
            required: ConfigurationRecord.mainLibraryAssociation
              .forKey(LibraryModelLoadDataConfigurationInfo.CodingKeys.mainLibrary)
              .select(Column.rowID, LibraryRecord.Columns.bookmark)
              .including(
                required: LibraryRecord.bookmarkAssociation
                  .forKey(LibraryModelLoadDataConfigurationMainLibraryInfo.CodingKeys.bookmark)
                  .select(
                    Column.rowID,
                    BookmarkRecord.Columns.data,
                    BookmarkRecord.Columns.options,
                    BookmarkRecord.Columns.hash,
                  ),
              ),
          )
          .asRequest(of: LibraryModelLoadDataConfigurationInfo.self)
          .fetchOne(db)
      }
      .removeDuplicates()

    let conn: DatabasePool

    do {
      conn = try await connection()
    } catch {
      Logger.model.error("Could not create database connection: \(error)")

      return
    }

    do {
      for try await configuration in observation.values(in: conn) {
        guard let configuration else {
          continue
        }

        let id = configuration.mainLibrary.library.rowID!
        let bookmarkID = configuration.mainLibrary.bookmark.bookmark.rowID!
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
            try await conn.write { db in
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
              )

              try library.update(db)
            }
          } catch {
            // TODO: Log.
            Logger.model.error("\(error)")
          }

          continue
        }

        // I'm surprised file system events does not require a security scope.
        if let stream = eventStream {
          stream.continuation.finish()
        }

        let stream = AsyncStream<LibraryModelEventStreamElement>.makeStream()
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

        self.eventStream = stream

        Task {
          for await element in stream.stream {
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

              return urbs.compactMap { urb -> LibraryModelTrackInfo? in
                let formatContext = FFFormatContext()

                do {
                  return try openingInput(
                    &formatContext.context,
                    at: urb.url.pathString
                  ) { formatContext -> LibraryModelTrackInfo? in
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

                    guard let duration = duration(formatContext, stream: stream) else {
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
                            fatalError("Reached supposedly unreachable code")
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

                    return LibraryModelTrackInfo(
                      track: LibraryTrackRecord(
                        bookmark: nil,
                        library: id,
                        title: title,
                        duration: duration,
                        artistName: artistName,
                        albumName: albumName,
                        albumArtistName: albumArtistName,
                        albumDate: albumDate,
                        albumArtwork: nil,
                        trackNumber: track?.number,
                        trackTotal: track?.total ?? trackTotal,
                        discNumber: disc?.number,
                        discTotal: track?.total ?? discTotal,
                      ),
                      bookmark: BookmarkRecord(
                        data: urb.bookmark.data,
                        options: urb.bookmark.options,
                        hash: hash(data: urb.bookmark.data),
                        relative: bookmarkID,
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
              try await conn.write { db in
                try tracks.forEach { track in
                  var bookmark = track.bookmark
                  try bookmark.upsert(db)

                  var artwork = track.artwork
                  try artwork.upsert(db)

                  var track = LibraryTrackRecord(
                    bookmark: bookmark.rowID,
                    library: track.track.library,
                    title: track.track.title,
                    duration: track.track.duration,
                    artistName: track.track.artistName,
                    albumName: track.track.albumName,
                    albumArtistName: track.track.albumArtistName,
                    albumDate: track.track.albumDate,
                    albumArtwork: artwork.rowID,
                    trackNumber: track.track.trackNumber,
                    trackTotal: track.track.trackTotal,
                    discNumber: track.track.discNumber,
                    discTotal: track.track.discTotal,
                  )

                  try track.upsert(db)
                }
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
}
