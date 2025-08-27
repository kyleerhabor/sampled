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


// TODO: Rename.
func read(frame: UnsafePointer<AVFrame>!, pixelFormatDescriptor: UnsafePointer<AVPixFmtDescriptor>!) -> CGImage? {
  // TODO: Figure out how to use a stride instead of reading the buffer directly.
  //
  // This function also carries the assumption that all the data is in the first element (i.e., AV_PIX_FMT_RGBA).
  let buffer = frame.pointee.buf.0!
  let data = Data(bytes: buffer.pointee.data, count: buffer.pointee.size)
  let bitsPerPixel = Int(av_get_bits_per_pixel(pixelFormatDescriptor))

  guard let provider = CGDataProvider(data: data as CFData) else {
    return nil
  }

  return CGImage(
    width: Int(frame.pointee.width),
    height: Int(frame.pointee.height),
    bitsPerComponent: Int(bitsPerPixel / Int(pixelFormatDescriptor.pointee.nb_components)),
    bitsPerPixel: bitsPerPixel,
    bytesPerRow: Int(frame.pointee.linesize.0),
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
    provider: provider,
    decode: nil,
    shouldInterpolate: true,
    intent: .defaultIntent,
  )
}

func read(
  packet: UnsafeMutablePointer<AVPacket>!,
  data: UnsafeMutablePointer<UInt8>!,
  bytes: Int32,
  codec: UnsafePointer<AVCodec>!,
  frame: UnsafeMutablePointer<AVFrame>!,
  scaleFrame: UnsafeMutablePointer<AVFrame>!,
  scaleContext: UnsafeMutablePointer<SwsContext>!,
) throws(FFError) -> CGImage? {
  try packetFromData(packet, data: data, size: bytes)

  let codecContext = FFCodecContext(codec: codec)
  try openCodec(codecContext.context, codec: codec)
  try sendPacket(codecContext.context, packet: packet)
  try receiveFrame(codecContext.context, frame: frame)

  let pixelFormat = AV_PIX_FMT_RGBA
  let pixelFormatDescriptor = av_pix_fmt_desc_get(pixelFormat)
  scaleFrame.pointee.width = frame.pointee.width
  scaleFrame.pointee.height = frame.pointee.height
  scaleFrame.pointee.format = pixelFormat.rawValue

  try SampledFFmpeg.scaleFrame(scaleContext, source: frame, destination: scaleFrame)

  return read(frame: scaleFrame, pixelFormatDescriptor: pixelFormatDescriptor)
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
  var isLiked: Bool
  var artistName: String?
  var albumName: String?
  var albumArtistName: String?
  var albumDate: Date?
  var albumArtworkImage: NSImage?
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
    isLiked: Bool,
    artistName: String?,
    albumName: String?,
    albumArtistName: String?,
    albumDate: Date?,
    albumArtworkImage: NSImage?,
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
    self.isLiked = isLiked
    self.artistName = artistName
    self.albumName = albumName
    self.albumArtistName = albumArtistName
    self.albumDate = albumDate
    self.albumArtworkImage = albumArtworkImage
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

@Observable
@MainActor
final class LibraryModel {
  var tracks = IdentifiedArrayOf<LibraryTrackModel>()
  var likedTrackIDs = Set<LibraryTrackModel.ID>()
  @ObservationIgnored private var eventStream: AsyncStreamContinuationPair<LibraryModelEventStreamElement>?

  func load() async {
    await load2()
  }

  nonisolated private func load2() async {
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
                    LibraryTrackRecord.Columns.library,
                    LibraryTrackRecord.Columns.duration,
                    LibraryTrackRecord.Columns.isLiked,
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
                      .select(
                        Column.rowID,
                        LibraryTrackAlbumArtworkRecord.Columns.data,
                        LibraryTrackAlbumArtworkRecord.Columns.hash,
                        LibraryTrackAlbumArtworkRecord.Columns.format,
                      ),
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
                  isLiked: track.track.track.isLiked,
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

        // TODO: Extract.

        struct ResultsTrack {
          let track: LibraryModelLoadConfigurationMainLibraryTrackInfo
          let source: URLSource
          let albumArtworkImage: NSImage?
        }

        struct Results {
          var tracks: [ResultsTrack]
          var albumArtworkImages: [RowID: NSImage?]
        }

        let results = tracks.reduce(into: Results(tracks: [], albumArtworkImages: [:])) { partialResult, track in
          let image: NSImage?

          if let albumArtwork = track.track.albumArtwork {
            let id = albumArtwork.albumArtwork.rowID!

            if let img = partialResult.albumArtworkImages[id] {
              image = img
            } else {
              let data = albumArtwork.albumArtwork.data!
              let allocatedMemory = allocateMemory(bytes: data.count)
              let allocated = data.withUnsafeBytes { data in
                allocatedMemory!.initializeMemory(
                  as: UInt8.self,
                  from: data.baseAddress!.assumingMemoryBound(to: UInt8.self),
                  count: data.count,
                )
              }

              let packet = FFPacket()
              let frame = FFFrame()
              let scaleFrame = FFFrame()
              let scaleContext = FFScaleContext()
              let cgImage: CGImage?

              do {
                cgImage = try read(
                  packet: packet.packet,
                  data: allocated,
                  // This is safe since it's from AVPacket.size, which is int.
                  bytes: Int32(data.count),
                  codec: avcodec_find_decoder(albumArtwork.albumArtwork.format!.codecID),
                  frame: frame.frame,
                  scaleFrame: scaleFrame.frame,
                  scaleContext: scaleContext.context,
                )
              } catch {
                // TODO: Elaborate.
                Logger.model.error("\(error)")

                // We don't want to retry failures.
                cgImage = nil
              }

              image = cgImage.map { NSImage(cgImage: $0, size: .zero) }
              partialResult.albumArtworkImages[id] = image
            }
          } else {
            image = nil
          }

          partialResult.tracks.append(
            ResultsTrack(
              track: track.track,
              source: track.source,
              albumArtworkImage: image,
            ),
          )
        }

        Task { @MainActor in
          self.tracks = results.tracks.reduce(
            into: IdentifiedArrayOf<LibraryTrackModel>(minimumCapacity: tracks.count)
          ) { partialResult, track in
            let rowID = track.track.track.rowID!
            let duration = track.track.track.duration!
            let isLiked = track.track.track.isLiked!
            let albumArtworkHash = track.albumArtworkImage == nil ? nil : track.track.albumArtwork?.albumArtwork.hash
            let model = self.tracks[id: rowID].map { model in
              model.title = track.track.track.title
              model.source = track.source
              model.duration = Duration.seconds(duration)
              model.isLiked = isLiked
              model.artistName = track.track.track.artistName
              model.albumName = track.track.track.albumName
              model.albumArtistName = track.track.track.albumArtistName
              model.albumDate = track.track.track.albumDate
              model.albumArtworkImage = track.albumArtworkImage
              model.albumArtworkHash = albumArtworkHash
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
              isLiked: isLiked,
              artistName: track.track.track.artistName,
              albumName: track.track.track.albumName,
              albumArtistName: track.track.track.albumArtistName,
              albumDate: track.track.track.albumDate,
              albumArtworkImage: track.albumArtworkImage,
              albumArtworkHash: albumArtworkHash,
              trackNumber: track.track.track.trackNumber,
              trackTotal: track.track.track.trackTotal,
              discNumber: track.track.track.discNumber,
              discTotal: track.track.track.discTotal,
            )

            partialResult.append(model)
          }

          self.likedTrackIDs = Set(self.tracks.filter(\.isLiked).map(\.id))
        }
      }
    } catch {
      Logger.model.error("Could not observe changes to library folder in database: \(error)")

      return
    }
  }
  
  func setLiked(_ flag: Bool, for tracks: [LibraryTrackModel]) async {
    tracks.forEach(setter(flag, on: \.isLiked))
    await setLiked(tracks: tracks.map(\.id), isLiked: flag)
  }

  nonisolated private func setLiked(tracks: [LibraryTrackModel.ID], isLiked: Bool) async {
    let conn: DatabasePool

    do {
      conn = try await connection()
    } catch {
      Logger.model.error("Could not create database connection: \(error)")

      return
    }

    do {
      try await conn.write { db in
        try tracks.forEach { id in
          // TODO: Decide whether or not to fetch and update all columns or update select columns.
          let track = LibraryTrackRecord(
            rowID: id,
            bookmark: nil,
            library: nil,
            title: nil,
            duration: nil,
            isLiked: isLiked,
            artistName: nil,
            albumName: nil,
            albumArtistName: nil,
            albumDate: nil,
            albumArtwork: nil,
            trackNumber: nil,
            trackTotal: nil,
            discNumber: nil,
            discTotal: nil,
          )

          try track.update(db, columns: [LibraryTrackRecord.Columns.isLiked])
        }
      }
    } catch {
      Logger.model.error("Could not write to database: \(error)")
    }
  }
}
