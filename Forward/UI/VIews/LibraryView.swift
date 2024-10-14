//
//  LibraryView.swift
//  Forward
//
//  Created by Kyle Erhabor on 10/7/24.
//

import CFFmpeg
import CoreFFmpeg
import ForwardFFmpeg
import Algorithms
import OSLog
import SwiftUI

struct LibraryTrackPosition {
  let number: Int?
  let total: Int?
}

extension LibraryTrackPosition: Equatable {}

struct LibraryTrack {
  let source: URLSource

  let title: String
  let artist: String
  let album: String
  let albumArtist: String?
  let date: Date?
  let coverImage: NSImage
  let duration: Duration
  let track: LibraryTrackPosition?
  let disc: LibraryTrackPosition?
}

extension LibraryTrack: Equatable {}

extension LibraryTrack: Identifiable {
  var id: URL { source.url }
}

struct LibraryTrackPositionView: View {
  let item: Int?

  var body: some View {
    Text(item ?? 0, format: .number.grouping(.never))
      .monospacedDigit()
      .visible(item != nil)
  }
}

struct LibraryView: View {
  @State private var isFileImporterPresented = false
  @State private var tracks = [LibraryTrack]()
  @State private var selection = Set<LibraryTrack.ID>()
  @State private var popoverTrack: LibraryTrack?

  var body: some View {
    Table(tracks, selection: $selection) {
      TableColumn(Text(verbatim: "Track №")) { track in
        LibraryTrackPositionView(item: track.track?.number)
      }
      .alignment(.numeric)

      TableColumn(Text(verbatim: "Disc №")) { track in
        LibraryTrackPositionView(item: track.disc?.number)
      }
      .alignment(.numeric)

      TableColumn(Text(verbatim: "Title"), value: \.title)
      TableColumn(Text(verbatim: "Artist"), value: \.artist)
      TableColumn(Text(verbatim: "Album"), value: \.album)
      TableColumn(Text(verbatim: "Album Artist")) { track in
        Text(track.albumArtist ?? "")
      }

      TableColumn(Text(verbatim: "Duration")) { track in
        Text(
          track.duration,
          format: .time(pattern: .minuteSecond(padMinuteToLength: 2, roundFractionalSeconds: .towardZero))
        )
        .monospacedDigit()
      }
    }
    .contextMenu { ids in
      Button("Finder.Item.Show") {
        let urls = tracks
          .filter(in: ids, by: \.id)
          .map(\.source.url)

        NSWorkspace.shared.activateFileViewerSelecting(urls)
      }
    }
    .fileImporter(
      isPresented: $isFileImporterPresented,
      allowedContentTypes: [.item],
      allowsMultipleSelection: true
    ) { result in
      let urls: [URL]

      switch result {
        case let .success(items):
          urls = items
        case let .failure(error):
          Logger.ui.error("\(error)")

          return
      }

      guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
        return
      }

      let frame = FFFrame()
      let scaledFrame = FFFrame()

      defer {
        av_frame_unref(frame.frame)
      }

      let packet = FFPacket()

      tracks = urls.compactMap { url in
        let source = URLSource(url: url, options: [.withReadOnlySecurityScope, .withoutImplicitSecurityScope])

        return source.accessingSecurityScopedResource {
          let pathString = url.pathString
          let formatContext = FFFormatContext()

          do {
            let fmtContext = formatContext.context

            return try opening(&formatContext.context, at: pathString) {
              do {
                // Yes, we need this for formats like FLAC.
                try findStreamInfo(fmtContext)
              } catch {
                Logger.ffmpeg.error("\(error)")

                return nil
              }

              let streami: Int32

              do {
                streami = try findBestStream(fmtContext, ofType: .audio, decoder: nil)
              } catch {
                Logger.ffmpeg.error("\(error)")

                return nil
              }

              let stream = fmtContext!.pointee.streams[Int(streami)]!
              let titleKey = "title"
              let artistKey = "artist"
              let albumKey = "album"
              let albumArtistKey = "album-artist"
              let dateKey = "date"
              let trackNumberKey = "track-number"
              let trackTotalKey = "track-total"
              let discNumberKey = "disc-number"
              let discTotalKey = "disc-total"
              let metadata = transform(
                chain(
                  FFDictionaryIterator(fmtContext!.pointee.metadata),
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
                      case 2: // [No.]/[Total]
                        partialResult[totalKey] = Int(components[1])

                        fallthrough
                      case 1: // [No.]
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
                      partialResult[artistKey] = value
                    case "album", "ALBUM":
                      partialResult[albumKey] = value
                    case "album_artist", "ALBUM_ARTIST":
                      partialResult[albumArtistKey] = value
                    case "date", "DATE": // ORIGINALDATE and ORIGINALYEAR exist, but seem specific to MusicBrainz Picard.
                      let date: Date

                      do {
                        // 2024-03-02
                        date = try Date(value, strategy: .iso8601.year())
                      } catch {
                        Logger.ui.error("\(error)")

                        return
                      }

                      partialResult[dateKey] = date

                      break
                    case "track":
                      partialResult = item(partialResult, value: value, numberKey: trackNumberKey, totalKey: trackTotalKey)
                    case "disc", "DISC":
                      partialResult = item(partialResult, value: value, numberKey: discNumberKey, totalKey: discTotalKey)
                    case "TRACKTOTAL": // TOTALTRACKS exists, but seems to always coincide with TRACKTOTAL
                      partialResult[trackTotalKey] = value
                    case "DISCTOTAL": // TOTALDISCS exists, but is the same situation as above.
                      partialResult[discTotalKey] = value
                    default:
                      partialResult[key] = value
                  }
                }
              }

              guard let title = metadata[titleKey] as? String,
                    let artist = metadata[artistKey] as? String,
                    let album = metadata[albumKey] as? String,
                    // Some formats (like Matroska) have the stream duration set to AV_NOPTS_VALUE, while exposing the
                    // real value in the format context.
                    let duration = duration(stream.pointee.duration)
                      .map({ Double($0) * av_q2d(stream.pointee.time_base) })
                      ?? duration(fmtContext!.pointee.duration).map({ Double($0 / FF_TIME_BASE) }) else {
                return nil
              }

              var decoder: UnsafePointer<AVCodec>!
              let videoStreami: Int32

              do {
                videoStreami = try findBestStream(fmtContext, ofType: .video, decoder: &decoder)
              } catch {
                Logger.ffmpeg.error("\(error)")

                return nil
              }

              let videoStream = fmtContext!.pointee.streams[Int(videoStreami)]!
              let videoCodecContext = FFCodecContext(codec: decoder)

              do {
                try copyCodecParameters(videoCodecContext.context, params: videoStream.pointee.codecpar)
                try open(videoCodecContext.context, codec: decoder)
              } catch {
                Logger.ffmpeg.error("\(error)")

                return nil
              }

              var data = Data()
              let format = AV_PIX_FMT_RGBA

              guard let formatDesc = av_pix_fmt_desc_get(format) else {
                return nil
              }

              let bitsPerPixel = Int(av_get_bits_per_pixel(formatDesc))

              do {
                loop:
                while true {
                  switch try iterateReceivePacket(fmtContext, packet: packet.packet) {
                    case .ok:
                      break
                    case .endOfFile:
                      break loop
                  }

                  defer {
                    av_packet_unref(packet.packet)
                  }

                  guard packet.packet.pointee.stream_index == videoStreami else {
                    continue
                  }

                  switch try iterateSendPacket(videoCodecContext.context, packet: packet.packet) {
                    case .ok:
                      break
                  }

                  loop:
                  while true {
                    switch try iterateReceiveFrame(videoCodecContext.context, frame: frame.frame) {
                      case .ok:
                        break
                      case .resourceTemporarilyUnavailable:
                        break loop
                      default:
                        return nil
                    }

                    try Self.write(data: &data, frame: frame.frame, scaledFrame: scaledFrame.frame, format: format)
                  }
                }

                switch try iterateSendPacket(videoCodecContext.context, packet: nil) {
                  case .ok:
                    break
                }

                loop:
                while true {
                  switch try iterateReceiveFrame(videoCodecContext.context, frame: frame.frame) {
                    case .ok:
                      break
                    case .endOfFile:
                      break loop
                    default:
                      return nil
                  }

                  try Self.write(data: &data, frame: frame.frame, scaledFrame: scaledFrame.frame, format: format)
                }
              } catch {
                Logger.ffmpeg.error("\(error)")

                return nil
              }

              let width = Int(videoCodecContext.context.pointee.width)
              let height = Int(videoCodecContext.context.pointee.height)

              guard let provider = CGDataProvider(data: data as CFData),
                    let image = CGImage(
                      width: width,
                      height: height,
                      bitsPerComponent: Int(bitsPerPixel / Int(formatDesc.pointee.nb_components)),
                      bitsPerPixel: bitsPerPixel,
                      bytesPerRow: Int(scaledFrame.frame.pointee.linesize.0),
                      space: colorSpace,
                      // I don't know why, but specifying premultipliedLast makes transparency work (as opposed to
                      // noneSkipLast). In fact, I don't really understand this property at all.
                      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                      provider: provider,
                      decode: nil,
                      shouldInterpolate: true,
                      intent: .defaultIntent
                    ) else {
                return nil
              }

              return LibraryTrack(
                source: source,
                title: title,
                artist: artist,
                album: album,
                albumArtist: metadata[albumArtistKey] as? String,
                date: metadata[dateKey] as? Date,
                coverImage: NSImage(cgImage: image, size: NSSize(width: width, height: height)),
                duration: Duration.seconds(duration),
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
          } catch {
            Logger.ffmpeg.error("\(error)")

            return nil
          }
        }
      }
    }
    .focusedSceneValue(\.open, AppMenuActionItem(identity: .library, isEnabled: true) {
      isFileImporterPresented = true
    })
    // TODO: Replace.
    .focusedSceneValue(\.tracks, tracks.filter(in: selection, by: \.id))
  }

  // TODO: Rename.
  static func write(
    data: inout Data,
    frame: UnsafePointer<AVFrame>!,
    scaledFrame: UnsafeMutablePointer<AVFrame>!,
    format: AVPixelFormat
  ) throws(FFError) {
    let width = frame.pointee.width
    let height = frame.pointee.height

    guard let scaleContext = FFScaleContext(
      srcWidth: width,
      srcHeight: height,
      srcFormat: frame.pointee.pixelFormat!,
      dstWidth: width,
      dstHeight: height,
      dstFormat: format
    ) else {
      Logger.ffmpeg.error("Could not create swscale context")

      throw FFError(code: FFError.Code.unknown)
    }

    try scale(scaleContext.context, source: frame, destination: scaledFrame)

    let buffer = scaledFrame.pointee.buf.0!
    data.append(buffer.pointee.data, count: buffer.pointee.size)
  }
}
