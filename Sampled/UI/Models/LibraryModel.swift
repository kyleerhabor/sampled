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
import Observation
import OSLog

enum LibraryModelID {
  case main, scene(UUID)
}

extension LibraryModelID: Hashable, Codable {}

@Observable
final class LibraryModel {
  let id: LibraryModelID
  var tracks: [LibraryTrack]

  init(id: LibraryModelID) {
    self.id = id
    self.tracks = []
  }

  // MARK: - FFmpeg

  static func duration(
    _ context: UnsafePointer<AVFormatContext>!,
    stream: UnsafePointer<AVStream>!
  ) -> Double? {
    // Some formats (like Matroska) have the stream duration set to AV_NOPTS_VALUE, while exposing the real
    // value in the format context.

    if let duration = SampledFFmpeg.duration(stream.pointee.duration) {
      return Double(duration) * av_q2d(stream.pointee.time_base)
    }

    if let duration = SampledFFmpeg.duration(context.pointee.duration) {
      return Double(duration * Int64(AV_TIME_BASE))
    }

    return nil
  }

  static func read(
    _ context: UnsafeMutablePointer<AVFormatContext>!,
    stream: UnsafeMutablePointer<AVStream>,
    packet: UnsafeMutablePointer<AVPacket>!,
  ) throws(FFError) -> UnsafePointer<AVPacket> {
    if stream.pointee.disposition & AV_DISPOSITION_ATTACHED_PIC != 0 {
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

  static func read(
    formatContext: UnsafeMutablePointer<AVFormatContext>!,
    scaleContext: UnsafeMutablePointer<SwsContext>!,
    packet: UnsafeMutablePointer<AVPacket>!,
    frame: UnsafeMutablePointer<AVFrame>!,
    scaleFrame: UnsafeMutablePointer<AVFrame>!,
    pixelFormat: AVPixelFormat,
  ) throws(FFError) -> CGImage? {
    // TODO: Log failures

    guard let pixelFormatDescription = av_pix_fmt_desc_get(pixelFormat) else {
      return nil
    }

    var decoder: UnsafePointer<AVCodec>!
    let streami: Int32

    do {
      streami = try findBestStream(formatContext, type: .video, decoder: &decoder)
    } catch let error where error.code == .streamNotFound {
      return nil
    }

    let stream = formatContext.pointee.streams[Int(streami)]!
    let codecContext = FFCodecContext(codec: decoder)
    try copyCodecParameters(codecContext.context, params: stream.pointee.codecpar)
    try openCodec(codecContext.context, codec: decoder)

    let packet = try Self.read(formatContext, stream: stream, packet: packet)
    try sendPacket(codecContext.context, packet: packet)
    try receiveFrame(codecContext.context, frame: frame)

    let width = frame.pointee.width
    let height = frame.pointee.height
    scaleFrame.pointee.width = width
    scaleFrame.pointee.height = height
    scaleFrame.pointee.format = pixelFormat.rawValue

    try SampledFFmpeg.scaleFrame(scaleContext, source: frame, destination: scaleFrame)

    // TODO: Figure out how to use a stride instead of reading the buffer directly.
    let buffer = scaleFrame.pointee.buf.0!
    let data = Data(bytes: buffer.pointee.data, count: buffer.pointee.size)
    let bitsPerPixel = Int(av_get_bits_per_pixel(pixelFormatDescription))

    guard let provider = CGDataProvider(data: data as CFData) else {
      return nil
    }

    return CGImage(
      width: Int(width),
      height: Int(height),
      bitsPerComponent: Int(bitsPerPixel / Int(pixelFormatDescription.pointee.nb_components)),
      bitsPerPixel: bitsPerPixel,
      bytesPerRow: Int(scaleFrame.pointee.linesize.0),
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: provider,
      decode: nil,
      shouldInterpolate: true,
      intent: .defaultIntent,
    )
  }

  static func read(source: URLSource) throws -> LibraryTrack? {
    let formatContext = FFFormatContext()

    return try openingInput(&formatContext.context, at: source.url.pathString) { formatContext -> LibraryTrack? in
      // We need this for formats like FLAC.
      try findStreamInfo(formatContext)

      let streami = try findBestStream(formatContext, type: .audio, decoder: nil)
      let stream = formatContext!.pointee.streams[Int(streami)]!
      let titleKey = "title"
      let artistNameKey = "artist-name"
      let artistNamesKey = "artist-names"
      let albumTitleKey = "album-title"
      let albumArtistNameKey = "album-artist-name"
      let dateKey = "date"
      let trackNumberKey = "track-number"
      let trackTotalKey = "track-total"
      let discNumberKey = "disc-number"
      let discTotalKey = "disc-total"
      let metadata = transform(
        chain(
          FFDictionaryIterator(formatContext!.pointee.metadata),
          FFDictionaryIterator(stream.pointee.metadata)
        )
        .uniqued(on: \.pointee.key)
      ) { metadata in
        metadata.reduce(into: [String: Any](minimumCapacity: metadata.count)) { partialResult, tag in
          let key = String(cString: tag.pointee.key)
          let value = String(cString: tag.pointee.value)

          func item(
            _ metadata: [String: Any],
            value: String,
            numberKey: String,
            totalKey: String
          ) -> [String: Any] {
            let components = value.split(separator: "/", maxSplits: 1)

            switch components.count {
              case 2: // [Number]/[Total]
                partialResult[totalKey] = Int(components[1])

                fallthrough
              case 1: // [Number]
                partialResult[numberKey] = Int(components[0])
              default:
                fatalError("unreachable")
            }

            return partialResult
          }

          switch key {
            case "title", "TITLE":
              partialResult[titleKey] = value
            case "artist", "ARTIST":
              partialResult[artistNameKey] = value
            case "ARTISTS": // This may be specific to MusicBrainz.
              partialResult[artistNamesKey] = value
                .split(separator: ";")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            case "album", "ALBUM":
              partialResult[albumTitleKey] = value
            case "album_artist", "ALBUM_ARTIST":
              partialResult[albumArtistNameKey] = value
            case "date", "DATE": // ORIGINALDATE and ORIGINALYEAR exist, but seem specific to MusicBrainz.
              let date: Date

              do {
                date = try Date(value, strategy: .iso8601.year())
              } catch {
                Logger.model.error("\(error)")

                return
              }

              partialResult[dateKey] = date
            case "track":
              partialResult = item(partialResult, value: value, numberKey: trackNumberKey, totalKey: trackTotalKey)
            case "disc", "DISC":
              partialResult = item(partialResult, value: value, numberKey: discNumberKey, totalKey: discTotalKey)
            case "TRACKTOTAL": // TOTALTRACKS exists, but seems to always coincide with TRACKTOTAL.
              partialResult[trackTotalKey] = Int(value)
            case "DISCTOTAL": // TOTALDISCS exists, but is in the same situation as above.
              partialResult[discTotalKey] = Int(value)
            default:
              partialResult[key] = value
          }
        }
      }

      // Some formats (like Matroska) have the stream duration set to AV_NOPTS_VALUE, while exposing the real
      // value in the format context.
      guard let duration = Self.duration(formatContext, stream: stream) else {
        return nil
      }

      let packet = FFPacket()
      let frame = FFFrame()
      let scaleFrame = FFFrame()
      let scaleContext = FFScaleContext()
      let pixelFormat = AV_PIX_FMT_RGBA
      let coverImage = try Self.read(
        formatContext: formatContext,
        scaleContext: scaleContext.context,
        packet: packet.packet,
        frame: frame.frame,
        scaleFrame: scaleFrame.frame,
        pixelFormat: pixelFormat,
      )

      return LibraryTrack(
        source: source,
        title: metadata[titleKey] as? String ?? source.url.lastPath,
        duration: Duration.seconds(duration),
        artistName: metadata[artistNameKey] as? String,
        artistNames: metadata[artistNamesKey] as? [String] ?? (metadata[artistNameKey] as? String).map { [$0] } ?? [],
        albumTitle: metadata[albumTitleKey] as? String,
        albumArtistName: metadata[albumArtistNameKey] as? String,
        date: metadata[dateKey] as? Date,
        coverImage: coverImage,
        track: LibraryTrackPosition(
          number: metadata[trackNumberKey] as? Int,
          total: metadata[trackTotalKey] as? Int
        ),
        disc: LibraryTrackPosition(
          number: metadata[discNumberKey] as? Int,
          total: metadata[discTotalKey] as? Int
        )
      )
    }
  }
}

extension LibraryModel: Equatable {
  static func ==(lhs: LibraryModel, rhs: LibraryModel) -> Bool {
    lhs.id == rhs.id
  }
}

extension LibraryModel: Hashable {
  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

extension LibraryModel: Codable {
  convenience init(from decoder: any Decoder) throws {
    let id: LibraryModelID

    do {
      // If this method throws when restoring a SwiftUI scene, instead of the runtime using a default value, it crashes
      // the application. This workaround is yucky since it makes it possible to have multiple main library windows.
      let container = try decoder.singleValueContainer()
      id = try container.decode(LibraryModelID.self)
    } catch {
      id = .main
    }

    self.init(id: id)
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(id)
  }
}
