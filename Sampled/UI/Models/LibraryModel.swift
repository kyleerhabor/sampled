//
//  LibraryModel.swift
//  Sampled
//
//  Created by Kyle Erhabor on 11/6/24.
//

import CFFmpeg
import CoreFFmpeg
import SampledCore
import Algorithms
import AppKit
import CoreGraphics
import FractionalIndex
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
  let bitsPerPixel = Int(AVPixFmtDescriptor.bitsPerPixel(pixelFormatDescriptor))

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

// TODO: Rename.
func read(
  packet: UnsafeMutablePointer<AVPacket>,
  data: UnsafeMutablePointer<UInt8>,
  bytes: Int32,
  codec: UnsafePointer<AVCodec>,
  frame: UnsafeMutablePointer<AVFrame>,
) throws(FFError) {
  try packetFromData(packet, data: data, size: bytes)

  let codecContext = CodecContext(codec: codec)
  try openCodec(codecContext.context, codec: codec)
  try sendPacket(codecContext.context, packet: packet)
  try receiveFrame(codecContext.context, frame: frame)
}

// TODO: Rename.
func read(
  frame: UnsafeMutablePointer<AVFrame>!,
  scaleFrame: UnsafeMutablePointer<AVFrame>!,
  scaleContext: UnsafeMutablePointer<SwsContext>,
) throws(FFError) -> CGImage? {
  // TODO: Add note about kCVPixelFormatType_32RGBA potentially not being supported as rationale for scaling.
  let pixelFormat = PixelFormat.rgba
  let pixelFormatDescriptor = AVPixelFormat.descriptor(AVPixelFormat(pixelFormat))
  scaleFrame.pointee.format = pixelFormat.rawValue
  try Sampled.scaleFrame(scaleContext, source: frame, destination: scaleFrame)

  let image = read(frame: scaleFrame, pixelFormatDescriptor: pixelFormatDescriptor)

  return image
}

enum LibraryModelEventStreamElement {
  case initial, events(EventStreamEvents)
}

@Observable
@MainActor
final class LibraryTrackModel {
  private let rowID: RowID
  fileprivate var albumArtworkData: Data?
  fileprivate var albumArtworkFormat: LibraryTrackAlbumArtworkFormat?
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
    albumArtworkData: Data?,
    albumArtworkFormat: LibraryTrackAlbumArtworkFormat?,
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
    self.albumArtworkData = albumArtworkData
    self.albumArtworkFormat = albumArtworkFormat
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

@Observable
@MainActor
final class LibraryQueueItemModel {
  private let rowID: RowID
  let track: LibraryTrackModel

  init(rowID: RowID, track: LibraryTrackModel) {
    self.rowID = rowID
    self.track = track
  }
}

extension LibraryQueueItemModel: @MainActor Identifiable {
  var id: RowID {
    self.rowID
  }
}

@Observable
@MainActor
final class LibrarySearchTrackModel {
  private let rowID: RowID
  var source: URLSource
  var title: String?
  var artistName: String?
  var albumArtworkImage: NSImage?

  init(
    rowID: RowID,
    source: URLSource,
    title: String?,
    artistName: String?,
    albumArtworkImage: NSImage?,
  ) {
    self.rowID = rowID
    self.source = source
    self.title = title
    self.artistName = artistName
    self.albumArtworkImage = albumArtworkImage
  }
}

extension LibrarySearchTrackModel: @MainActor Identifiable {
  var id: RowID {
    self.rowID
  }
}

struct LibraryModelQueueTrackLibraryCurrentQueueItemInfo {
  let item: LibraryQueueItemRecord
}

extension LibraryModelQueueTrackLibraryCurrentQueueItemInfo: Equatable, Decodable, FetchableRecord {}

struct LibraryModelQueueTrackLibraryCurrentQueueInfo {
  let queue: LibraryQueueRecord
  let items: [LibraryModelQueueTrackLibraryCurrentQueueItemInfo]
}

extension LibraryModelQueueTrackLibraryCurrentQueueInfo: Decodable {
  enum CodingKeys: String, CodingKey {
    case queue, items
  }
}

extension LibraryModelQueueTrackLibraryCurrentQueueInfo: Equatable, FetchableRecord {}

struct LibraryModelQueueTrackLibraryInfo {
  let library: LibraryRecord
  let currentQueue: LibraryModelQueueTrackLibraryCurrentQueueInfo?
}

extension LibraryModelQueueTrackLibraryInfo: Decodable {
  enum CodingKeys: String, CodingKey {
    case library, currentQueue
  }
}

extension LibraryModelQueueTrackLibraryInfo: Equatable, FetchableRecord {}

struct LibraryModelQueueTrackInfo {
  let track: LibraryTrackRecord
  let library: LibraryModelQueueTrackLibraryInfo
}

extension LibraryModelQueueTrackInfo: Decodable {
  enum CodingKeys: String, CodingKey {
    case track, library
  }
}

extension LibraryModelQueueTrackInfo: Equatable, FetchableRecord {}

struct LibraryModelSearchConfigurationMainLibraryBookmarkInfo {
  let bookmark: BookmarkRecord
}

extension LibraryModelSearchConfigurationMainLibraryBookmarkInfo: Equatable, Decodable, FetchableRecord {}

struct LibraryModelSearchConfigurationMainLibraryTrackFullTextInfo {
  let fullText: LibraryTrackFTRecord
}

extension LibraryModelSearchConfigurationMainLibraryTrackFullTextInfo: Equatable, Decodable, FetchableRecord {}

struct LibraryModelSearchConfigurationMainLibraryTrackBookmarkInfo {
  let bookmark: BookmarkRecord
}

extension LibraryModelSearchConfigurationMainLibraryTrackBookmarkInfo: Equatable, Decodable, FetchableRecord {}

struct LibraryModelSearchConfigurationMainLibraryTrackAlbumArtworkInfo {
  let albumArtwork: LibraryTrackAlbumArtworkRecord
}

extension LibraryModelSearchConfigurationMainLibraryTrackAlbumArtworkInfo: Equatable, Decodable, FetchableRecord {}

struct LibraryModelSearchConfigurationMainLibraryTrackInfo {
  let track: LibraryTrackRecord
  let fullText: LibraryModelSearchConfigurationMainLibraryTrackFullTextInfo
  let bookmark: LibraryModelSearchConfigurationMainLibraryTrackBookmarkInfo
  let albumArtwork: LibraryModelSearchConfigurationMainLibraryTrackAlbumArtworkInfo?
}

extension LibraryModelSearchConfigurationMainLibraryTrackInfo: Decodable {
  enum CodingKeys: String, CodingKey {
    case track,
         fullText,
         bookmark = "_bookmark",
         albumArtwork
  }
}

extension LibraryModelSearchConfigurationMainLibraryTrackInfo: Equatable, FetchableRecord {}

struct LibraryModelSearchConfigurationMainLibraryInfo {
  let library: LibraryRecord
  let bookmark: LibraryModelSearchConfigurationMainLibraryBookmarkInfo
  let tracks: [LibraryModelSearchConfigurationMainLibraryTrackInfo]
}

extension LibraryModelSearchConfigurationMainLibraryInfo: Decodable {
  enum CodingKeys: String, CodingKey {
    case library,
         bookmark = "_bookmark",
         tracks
  }
}

extension LibraryModelSearchConfigurationMainLibraryInfo: Equatable, FetchableRecord {}

struct LibraryModelSearchConfigurationInfo {
  let mainLibrary: LibraryModelSearchConfigurationMainLibraryInfo
}

extension LibraryModelSearchConfigurationInfo: Decodable {
  enum CodingKeys: String, CodingKey {
    case mainLibrary
  }
}

extension LibraryModelSearchConfigurationInfo: Equatable, FetchableRecord {}

@Observable
@MainActor
final class LibraryModel {
  var tracks: IdentifiedArrayOf<LibraryTrackModel>
  var likedTrackIDs: Set<LibraryTrackModel.ID>
  var queuedItems: IdentifiedArrayOf<LibraryQueueItemModel>
  var searchTracks: IdentifiedArrayOf<LibrarySearchTrackModel>

  init() {
    self.tracks = []
    self.likedTrackIDs = []
    self.queuedItems = []
    self.searchTracks = []
  }

  func load() async {
    await self._load()
  }

  func setLiked(_ flag: Bool, for tracks: [LibraryTrackModel]) async {
    tracks.forEach(setter(flag, on: \.isLiked))
    await setLiked(tracks: tracks.map(\.id), isLiked: flag)
  }

  func queue(tracks: Set<LibraryTrackModel.ID>) async {
    await _queue(tracks: tracks)
  }

  func search(text: String, imageSize: Int32) async {
    await _search(text: text, imageSize: imageSize)
  }

  func resampleImage(track: LibraryTrackModel, length: Double) async -> NSImage? {
    guard let albumArtworkData = track.albumArtworkData,
          let albumArtworkFormat = track.albumArtworkFormat else {
      return nil
    }

    return await resampleImage(data: albumArtworkData, format: albumArtworkFormat, length: length)
  }

  nonisolated private func readLoadPacket(data: Data, codecID: CodecID) -> CGImage? {
    guard let allocated = Allocation(bytes: data.count).initialize(span: data.span) else {
      return nil
    }

    defer {
      allocated.deinitialize(count: data.count)
    }

    let packet = Packet()
    let frame = Frame()

    do {
      try Sampled.read(
        packet: packet.packet,
        data: allocated,
        // This is safe since it's from AVPacket.size, which is int.
        bytes: Int32(data.count),
        codec: findDecoder(id: AVCodecID(codecID))!,
        frame: frame.frame,
      )
    } catch {
      // TODO: Elaborate.
      Logger.model.error("\(error)")

      return nil
    }

    let scaleContext = ScaleContext()
    let scaleFrame = Frame()
    scaleFrame.frame.pointee.width = frame.frame.pointee.width
    scaleFrame.frame.pointee.height = frame.frame.pointee.height

    do {
      return try Sampled.read(
        frame: frame.frame,
        scaleFrame: scaleFrame.frame,
        scaleContext: scaleContext.context,
      )
    } catch {
      // TODO: Elaborate.
      Logger.model.error("\(error)")

      return nil
    }
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

  nonisolated private func load(
    _ connection: some DatabaseWriter,
    configuration: LibraryModelLoadConfigurationInfo?,
  ) async {
    guard let configuration else {
      return
    }

//    let fileBookmarks = configuration.mainLibrary.tracks.map { track in
//      BookmarkAssignmentFileBookmark(
//        bookmark: BookmarkAssignmentFileBookmarkBookmark(bookmark: track.fileBookmark.bookmark.bookmark),
//        relative: BookmarkAssignmentFileBookmarkRelative(
//          bookmark: configuration.mainLibrary.fileBookmark.bookmark.bookmark,
//        ),
//      )
//    }
//
//    var assignment = BookmarkAssignment()
//    await assignment.assign(fileBookmarks: fileBookmarks)
//
//    guard fileBookmarks.allSatisfy(assignment.isSatisfied(fileBookmark:)) else {
//      do {
//        try await Task { [assignment] in
//          try await connection.write { db in
//            try assignment.write(db, fileBookmarks: fileBookmarks)
//          }
//        }.value
//      } catch {
//        Logger.model.error("Could not write to database: \(error)")
//      }
//
//      return
//    }
//
//    let results = tracks.reduce(into: Results(tracks: [], albumArtworkImages: [:])) { partialResult, track in
//      let image: NSImage?
//
//      if let albumArtwork = track.track.albumArtwork {
//        let id = albumArtwork.albumArtwork.rowID!
//
//        if let img = partialResult.albumArtworkImages[id] {
//          image = img
//        } else {
//          let img = readLoadPacket(
//            data: albumArtwork.albumArtwork.data!,
//            codecID: albumArtwork.albumArtwork.format!.codecID,
//          ).map { NSImage(cgImage: $0, size: .zero) }
//
//          partialResult.albumArtworkImages[id] = img
//          image = img
//        }
//      } else {
//        image = nil
//      }
//
//      partialResult.tracks.append(
//        ResultsTrack(
//          track: track.track,
//          source: track.source,
//          albumArtworkImage: image,
//        ),
//      )
//    }
//
//    let likedTrackIDs = Set(
//      results.tracks
//        .filter { $0.track.track.isLiked! }
//        .map { $0.track.track.rowID! },
//    )
//
//    Task { @MainActor in
//      self.tracks = results.tracks.reduce(
//        into: IdentifiedArrayOf<LibraryTrackModel>(reservingCapacity: tracks.count)
//      ) { partialResult, track in
//        let rowID = track.track.track.rowID!
//        let duration = track.track.track.duration!
//        let isLiked = track.track.track.isLiked!
//        let albumArtworkHash = track.albumArtworkImage == nil ? nil : track.track.albumArtwork?.albumArtwork.hash
//        let model = self.tracks[id: rowID].map { model in
//          model.albumArtworkData = track.track.albumArtwork?.albumArtwork.data
//          model.albumArtworkFormat = track.track.albumArtwork?.albumArtwork.format
//          model.source = track.source
//          model.title = track.track.track.title
//          model.duration = Duration.seconds(duration)
//          model.isLiked = isLiked
//          model.artistName = track.track.track.artistName
//          model.albumName = track.track.track.albumName
//          model.albumArtistName = track.track.track.albumArtistName
//          model.albumDate = track.track.track.albumDate
//          model.albumArtworkImage = track.albumArtworkImage
//          model.albumArtworkHash = albumArtworkHash
//          model.trackNumber = track.track.track.trackNumber
//          model.trackTotal = track.track.track.trackTotal
//          model.discNumber = track.track.track.discNumber
//          model.discTotal = track.track.track.discTotal
//
//          return model
//        } ?? LibraryTrackModel(
//          rowID: rowID,
//          albumArtworkData: track.track.albumArtwork?.albumArtwork.data,
//          albumArtworkFormat: track.track.albumArtwork?.albumArtwork.format,
//          source: track.source,
//          title: track.track.track.title,
//          duration: Duration.seconds(duration),
//          isLiked: isLiked,
//          artistName: track.track.track.artistName,
//          albumName: track.track.track.albumName,
//          albumArtistName: track.track.track.albumArtistName,
//          albumDate: track.track.track.albumDate,
//          albumArtworkImage: track.albumArtworkImage,
//          albumArtworkHash: albumArtworkHash,
//          trackNumber: track.track.track.trackNumber,
//          trackTotal: track.track.track.trackTotal,
//          discNumber: track.track.track.discNumber,
//          discTotal: track.track.track.discTotal,
//        )
//
//        partialResult.append(model)
//      }
//
//      // We're not dedicating a method to this since it opens another opportunity for the data to get out of sync.
//      self.likedTrackIDs = likedTrackIDs
//      self.queuedItems = configuration.mainLibrary.currentQueue.map { currentQueue in
//        IdentifiedArray(uniqueElements: currentQueue.items.compactMap { item in
//          let id = item.item.rowID!
//
//          if let item = self.queuedItems[id: id] {
//            return item
//          }
//
//          guard let track = self.tracks[id: item.item.track!] else {
//            return nil
//          }
//
//          return LibraryQueueItemModel(rowID: id, track: track)
//        })
//      } ?? IdentifiedArray()
//    }
  }

  nonisolated private func _load() async {
    let observation = ValueObservation
      .trackingConstantRegion { db in
        try ConfigurationRecord
          .including(
            required: ConfigurationRecord.mainLibrary
              .forKey(LibraryModelLoadConfigurationInfo.CodingKeys.mainLibrary)
              .select(Column.rowID)
              .including(
                required: LibraryRecord.fileBookmark
                  .forKey(LibraryModelLoadConfigurationMainLibraryInfo.CodingKeys.fileBookmark)
                  .select(.rowID)
                  .including(
                    required: FileBookmarkRecord.bookmark
                      .forKey(LibraryModelLoadConfigurationMainLibraryFileBookmarkInfo.CodingKeys.bookmark)
                      .select(.rowID, BookmarkRecord.Columns.data, BookmarkRecord.Columns.options),
                  )
              )
              .including(
                optional: LibraryRecord.currentQueue
                  .forKey(LibraryModelLoadConfigurationMainLibraryInfo.CodingKeys.currentQueue)
                  .select(.rowID)
                  .including(
                    all: LibraryQueueRecord.items
                      .forKey(LibraryModelLoadConfigurationMainLibraryCurrentQueueInfo.CodingKeys.items)
                      .select(Column.rowID)
                      .order(LibraryQueueItemRecord.Columns.position)
                      .including(
                        required: LibraryQueueItemRecord.track
                          .forKey(LibraryModelLoadConfigurationMainLibraryCurrentQueueItemInfo.CodingKeys.track)
                          .select(.rowID),
                      ),
                  ),
              )
              .including(
                all: LibraryRecord.tracks
                  .forKey(LibraryModelLoadConfigurationMainLibraryInfo.CodingKeys.tracks)
                  .select(
                    .rowID,
                    LibraryTrackRecord.Columns.title,
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
                    required: LibraryTrackRecord.fileBookmark
                      .forKey(LibraryModelLoadConfigurationMainLibraryTrackInfo.CodingKeys.fileBookmark)
                      .select(.rowID)
                      .including(
                        required: FileBookmarkRecord.bookmark
                          .forKey(LibraryModelLoadConfigurationMainLibraryTrackFileBookmarkInfo.CodingKeys.bookmark)
                          .select(.rowID, BookmarkRecord.Columns.data, BookmarkRecord.Columns.options),
                      ),
                  )
                  .including(
                    optional: LibraryTrackRecord.albumArtwork
                      .forKey(LibraryModelLoadConfigurationMainLibraryTrackInfo.CodingKeys.albumArtwork)
                      .select(
                        .rowID,
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

    let connection: DatabasePool

    do {
      connection = try await databaseConnection()
    } catch {
      Logger.model.error("Could not create database connection: \(error)")

      return
    }

    do {
      for try await configuration in observation.values(in: connection) {
        await self.load(connection, configuration: configuration)
      }
    } catch {
      Logger.model.error("Could not read from database: \(error)")

      return
    }
  }

  nonisolated private func _queue(tracks: Set<LibraryTrackModel.ID>) async {
//    let conn: DatabasePool
//
//    do {
//      conn = try await databaseConnection()
//    } catch {
//      Logger.model.error("Could not create database connection: \(error)")
//
//      return
//    }
//
//    do {
//      try await conn.write { db in
//        let tracks = try LibraryTrackRecord
//          .select(Column.rowID)
//          .filter(keys: tracks)
//          .including(
//            required: LibraryTrackRecord.library
//              .forKey(LibraryModelQueueTrackInfo.CodingKeys.library)
//              .select(Column.rowID, LibraryRecord.Columns.currentQueue),
//          )
//          .asRequest(of: LibraryModelQueueTrackInfo.self)
//          .fetchAll(db)
//
//        // For sake of convenience, we're going to assume all libraries are the same. This should apply to the rest of
//        // this class.
//        var iterator = tracks.makeIterator()
//
//        if let track = iterator.next() {
//          // Get the latest position from the current queue if it exists
//          let latestPosition: String? = if let queueID = track.library.library.currentQueue {
//            // Query for the item with the highest position in this queue using a SQL join
//            try String.fetchOne(
//              db,
//              sql: """
//                SELECT library_queue_items.position
//                FROM library_queue_items
//                JOIN item_library_queues ON item_library_queues.item = library_queue_items.rowid
//                WHERE item_library_queues.queue = ?
//                ORDER BY library_queue_items.position DESC
//                LIMIT 1
//                """,
//              arguments: [queueID]
//            )
//          } else {
//            nil
//          }
//          
//          var position = try generateKeyBetween(a: latestPosition, b: nil)
//          var item = LibraryQueueItemRecord(
//            rowID: nil,
//            track: track.track.rowID,
//            position: position,
//          )
//
//          try item.insert(db)
//
//          // Create or use existing queue
//          var queue = LibraryQueueRecord(rowID: track.library.library.currentQueue, currentItem: item.rowID)
//          try queue.upsert(db)
//
//          var itemLibraryQueue = ItemLibraryQueueRecord(
//            rowID: nil,
//            queue: queue.rowID,
//            item: item.rowID,
//          )
//
//          try itemLibraryQueue.insert(db)
//
//          var queueLibrary = QueueLibraryRecord(
//            rowID: nil,
//            library: track.library.library.rowID,
//            queue: queue.rowID,
//          )
//
//          try queueLibrary.upsert(db)
//
//          let library = LibraryRecord(
//            rowID: track.library.library.rowID,
//            bookmark: nil,
//            currentQueue: queue.rowID,
//          )
//
//          try library.update(db, columns: [LibraryRecord.Columns.currentQueue])
//
//          for track in iterator {
//            position = try generateKeyBetween(a: position, b: nil)
//
//            var item = LibraryQueueItemRecord(
//              rowID: nil,
//              track: track.track.rowID,
//              position: position,
//            )
//
//            try item.insert(db)
//
//            var itemLibraryQueue = ItemLibraryQueueRecord(
//              rowID: nil,
//              queue: queue.rowID,
//              item: item.rowID,
//            )
//
//            try itemLibraryQueue.insert(db)
//          }
//        }
//      }
//    } catch {
//      // TODO: Elaborate.
//      Logger.model.error("\(error)")
//    }
  }

  nonisolated private func readImagePacket(
    data: Data,
    codecID: CodecID,
    imageLength: Int32,
  ) -> CGImage? {
    guard let allocated = Allocation(bytes: data.count).initialize(span: data.span) else {
      return nil
    }

    defer {
      allocated.deinitialize(count: data.count)
    }

    let packet = Packet()
    let frame = Frame()
    let scaleFrame = Frame()
    let scaleContext = ScaleContext()

    do {
      try Sampled.read(
        packet: packet.packet,
        data: allocated,
        // This is safe since it's from AVPacket.size, which is int.
        bytes: Int32(data.count),
        codec: findDecoder(id: AVCodecID(codecID))!,
        frame: frame.frame,
      )
    } catch {
      // TODO: Elaborate.
      Logger.model.error("\(error)")

      return nil
    }

    let width = Float(frame.frame.pointee.width)
    let height = Float(frame.frame.pointee.height)
    let scale = min(1, Float(imageLength) / max(width, height))
    scaleFrame.frame.pointee.width = Int32(width * scale)
    scaleFrame.frame.pointee.height = Int32(height * scale)

    do {
      return try Sampled.read(
        frame: frame.frame,
        scaleFrame: scaleFrame.frame,
        scaleContext: scaleContext.context,
      )
    } catch {
      // TODO: Elaborate.
      Logger.model.error("\(error)")

      return nil
    }
  }

  nonisolated private func _search(text: String, imageSize: Int32) async {
//    let observation = ValueObservation
//      .trackingConstantRegion { db in
//        try ConfigurationRecord
//          .select(Column.rowID, ConfigurationRecord.Columns.mainLibrary)
//          .including(
//            required: ConfigurationRecord.mainLibraryAssociation
//              .forKey(LibraryModelSearchConfigurationInfo.CodingKeys.mainLibrary)
//              .select(Column.rowID, LibraryRecord.Columns.bookmark)
//              .including(
//                required: LibraryRecord.bookmarkAssociation
//                  .forKey(LibraryModelSearchConfigurationMainLibraryInfo.CodingKeys.bookmark)
//                  .select(BookmarkRecord.Columns.data, BookmarkRecord.Columns.options, BookmarkRecord.Columns.hash),
//              )
//              .including(
//                all: LibraryRecord.tracks
//                  .forKey(LibraryModelSearchConfigurationMainLibraryInfo.CodingKeys.tracks)
//                  .select(
//                    Column.rowID,
//                    LibraryTrackRecord.Columns.bookmark,
//                    LibraryTrackRecord.Columns.title,
//                    LibraryTrackRecord.Columns.artistName,
//                    LibraryTrackRecord.Columns.albumArtwork,
//                  )
//                  .including(
//                    required: LibraryTrackRecord.fullTextAssociation
//                      .forKey(LibraryModelSearchConfigurationMainLibraryTrackInfo.CodingKeys.fullText)
//                      .select(Column.rowID)
//                      .matching(FTS5Pattern(matchingAllPrefixesIn: text))
//                      .order(Column.rank),
//                  )
//                  .including(
//                    required: LibraryTrackRecord.bookmarkAssociation
//                      .forKey(LibraryModelSearchConfigurationMainLibraryTrackInfo.CodingKeys.bookmark)
//                      .select(BookmarkRecord.Columns.data, BookmarkRecord.Columns.options, BookmarkRecord.Columns.hash),
//                  )
//                  .including(
//                    optional: LibraryTrackRecord.albumArtworkAssociation
//                      .forKey(LibraryModelSearchConfigurationMainLibraryTrackInfo.CodingKeys.albumArtwork)
//                      .select(
//                        Column.rowID,
//                        LibraryTrackAlbumArtworkRecord.Columns.data,
//                        LibraryTrackAlbumArtworkRecord.Columns.format,
//                      ),
//                  ),
//              ),
//          )
//          .asRequest(of: LibraryModelSearchConfigurationInfo.self)
//          .fetchOne(db)
//      }
//      .removeDuplicates()
//
//    let conn: DatabasePool
//
//    do {
//      conn = try await databaseConnection()
//    } catch {
//      Logger.model.error("Could not create database connection: \(error)")
//
//      return
//    }
//
//    do {
//      for try await configuration in observation.values(in: conn) {
//        guard let configuration else {
//          continue
//        }
//
//        let options = configuration.mainLibrary.bookmark.bookmark.options!
//        let assigned: AssignedBookmark
//
//        do {
//          assigned = try await AssignedBookmark(
//            data: configuration.mainLibrary.bookmark.bookmark.data!,
//            options: options,
//            relativeTo: nil,
//          )
//        } catch {
//          // TODO: Elaborate.
//          Logger.model.error("\(error)")
//
//          continue
//        }
//
//        // We could probably compare the bookmark data directly.
//        let hashed = hash(data: assigned.data)
//
//        guard hashed == configuration.mainLibrary.bookmark.bookmark.hash! else {
//          do {
//            try await conn.write { db in
//              var bookmark = BookmarkRecord(
//                data: assigned.data,
//                options: options,
//                hash: hashed,
//                relative: nil,
//              )
//
//              try bookmark.upsert(db)
//
//              let library = LibraryRecord(
//                rowID: configuration.mainLibrary.library.rowID,
//                bookmark: bookmark.rowID,
//                currentQueue: nil,
//              )
//
//              try library.update(db, columns: [LibraryRecord.Columns.bookmark])
//            }
//          } catch {
//            // TODO: Elaborate.
//            Logger.model.error("\(error)")
//          }
//
//          continue
//        }
//
//        struct Track {
//          let track: LibraryModelSearchConfigurationMainLibraryTrackInfo
//          let bookmark: BookmarkRecord
//          let source: URLSource
//        }
//
//        var tracks = [Track](reservingCapacity: configuration.mainLibrary.tracks.count)
//
//        for track in configuration.mainLibrary.tracks {
//          let options = track.bookmark.bookmark.options!
//          let bookmark: AssignedBookmark
//
//          do {
//            bookmark = try await AssignedBookmark(
//              data: track.bookmark.bookmark.data!,
//              options: options,
//              relativeTo: assigned.resolved.url,
//            )
//          } catch {
//            // TODO: Elaborate.
//            Logger.model.error("\(error)")
//
//            continue
//          }
//
//          tracks.append(
//            Track(
//              track: track,
//              bookmark: BookmarkRecord(
//                data: bookmark.data,
//                options: options,
//                hash: hash(data: bookmark.data),
//                relative: configuration.mainLibrary.library.rowID,
//              ),
//              source: URLSource(url: bookmark.resolved.url, options: options),
//            ),
//          )
//        }
//
//        guard tracks.allSatisfy({ $0.track.bookmark.bookmark.hash == $0.bookmark.hash }) else {
//          do {
//            try await conn.write { [tracks] db in
//              try tracks.forEach { track in
//                var bookmark = track.bookmark
//                try bookmark.upsert(db)
//
//                let track = LibraryTrackRecord(
//                  rowID: track.track.track.rowID,
//                  bookmark: bookmark.rowID,
//                  title: track.track.track.title,
//                  duration: track.track.track.duration,
//                  isLiked: track.track.track.isLiked,
//                  artistName: track.track.track.artistName,
//                  albumName: track.track.track.albumName,
//                  albumArtistName: track.track.track.albumArtistName,
//                  albumDate: track.track.track.albumDate,
//                  albumArtwork: track.track.albumArtwork?.albumArtwork.rowID,
//                  trackNumber: track.track.track.trackNumber,
//                  trackTotal: track.track.track.trackTotal,
//                  discNumber: track.track.track.discNumber,
//                  discTotal: track.track.track.discTotal,
//                )
//
//                try track.update(db)
//              }
//            }
//          } catch {
//            // TODO: Elaborate.
//            Logger.model.error("\(error)")
//          }
//
//          continue
//        }
//
//        struct ResultsTrack {
//          let track: LibraryModelSearchConfigurationMainLibraryTrackInfo
//          let source: URLSource
//          let albumArtworkImage: NSImage?
//        }
//
//        struct Results {
//          var tracks: [ResultsTrack]
//          var albumArtworkImages: [RowID: NSImage?]
//        }
//
//        let results = tracks.reduce(into: Results(tracks: [], albumArtworkImages: [:])) { partialResult, track in
//          let image: NSImage?
//
//          if let albumArtwork = track.track.albumArtwork {
//            let id = albumArtwork.albumArtwork.rowID!
//
//            if let img = partialResult.albumArtworkImages[id] {
//              image = img
//            } else {
//              let img = readImagePacket(
//                data: albumArtwork.albumArtwork.data!,
//                codecID: albumArtwork.albumArtwork.format!.codecID,
//                imageLength: imageSize,
//              ).map { NSImage(cgImage: $0, size: .zero) }
//
//              partialResult.albumArtworkImages[id] = img
//              image = img
//            }
//          } else {
//            image = nil
//          }
//
//          partialResult.tracks.append(
//            ResultsTrack(
//              track: track.track,
//              source: track.source,
//              albumArtworkImage: image,
//            ),
//          )
//        }
//
//        Task { @MainActor in
//          self.searchTracks = results.tracks.reduce(
//            into: IdentifiedArrayOf<LibrarySearchTrackModel>(reservingCapacity: tracks.count)
//          ) { partialResult, track in
//            let rowID = track.track.track.rowID!
//            let model = self.searchTracks[id: rowID].map { model in
//              model.source = track.source
//              model.title = track.track.track.title
//              model.artistName = track.track.track.artistName
//              model.albumArtworkImage = track.albumArtworkImage
//
//              return model
//            } ?? LibrarySearchTrackModel(
//              rowID: rowID,
//              source: track.source,
//              title: track.track.track.title,
//              artistName: track.track.track.artistName,
//              albumArtworkImage: track.albumArtworkImage,
//            )
//
//            partialResult.append(model)
//          }
//        }
//      }
//    } catch {
//      // TODO: Elaborate.
//      Logger.model.error("\(error)")
//
//      return
//    }
  }

  nonisolated private func setLiked(tracks: [LibraryTrackModel.ID], isLiked: Bool) async {
    let conn: DatabasePool

    do {
      conn = try await databaseConnection()
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
            fileBookmark: nil,
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

  nonisolated private func resampleImage(
    data: Data,
    format: LibraryTrackAlbumArtworkFormat,
    length: Double,
  ) async -> NSImage? {
    guard let image = readImagePacket(
      data: data,
      codecID: format.codecID,
      imageLength: Int32(min(length.rounded(.up), Double(Int32.max))),
    ) else {
      return nil
    }

    return NSImage(cgImage: image, size: .zero)
  }
}
