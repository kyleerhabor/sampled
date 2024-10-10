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
  let number: Int
  let total: Int
}

struct LibraryTrack {
  let url: URL

  let title: String
  let artist: String
  let album: String
  let coverImage: NSImage
  let duration: Duration
  let albumArtist: String?
  let track: LibraryTrackPosition?
  let disc: LibraryTrackPosition?
}

extension LibraryTrack: Identifiable {
  var id: URL { url }
}

struct LibraryTrackPositionView: View {
  let pos: LibraryTrackPosition

  var body: some View {
    Text(verbatim: "\(pos.number) of \(pos.total)")
      .monospacedDigit()
  }
}

struct LibraryView: View {
  @State private var isFileImporterPresented = false
  @State private var tracks = [LibraryTrack]()
  @State private var popoverTrack: LibraryTrack?

  var body: some View {
    Table(of: LibraryTrack.self) {
      TableColumn(Text(verbatim: "Track №")) { track in
        Text(track.track.map { String($0.number) } ?? "")
          .monospacedDigit()
          .visible(track.track != nil)
      }
      .alignment(.numeric)

      TableColumn(Text(verbatim: "Disc №")) { track in
        Text(track.disc.map { String($0.number) } ?? "")
          .monospacedDigit()
          .visible(track.disc != nil)
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
    } rows: {
      ForEach(tracks) { track in
        TableRow(track)
          .contextMenu {
            Button("Show Information") {
              popoverTrack = track
            }
          }
      }
    }
    .popover(item: $popoverTrack, attachmentAnchor: .point(.top)) { track in
      Image(nsImage: track.coverImage)
        .resizable()
        .frame(width: 256, height: 256)
        .scaledToFit()
        .clipShape(.rect(cornerRadius: 8))
        .padding()
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
        url.accessingSecurityScopedResource {
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
              let trackNumberKey = "track-number"
              let trackTotalKey = "track-total"
              let discNumberKey = "disc-number"
              let discTotalKey = "disc-total"
              let metadata = chain(
                FFDictionaryIterator(fmtContext!.pointee.metadata),
                FFDictionaryIterator(stream.pointee.metadata)
              )
              .uniqued(on: \.pointee.key)
              .reduce(into: [String: String]()) { partialResult, tag in
                let key = String(cString: tag.pointee.key)
                let value = String(cString: tag.pointee.value)

                func item(
                  _ metadata: [String: String],
                  value: String,
                  numberKey: String,
                  totalKey: String
                ) -> [String: String] {
                  let components = value.split(separator: "/", maxSplits: 1)

                  switch components.count {
                    case 2: // [No.]/[Total]
                      partialResult[totalKey] = String(components[1])

                      fallthrough
                    case 1: // [No.]
                      partialResult[numberKey] = String(components[0])
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

              guard let title = metadata[titleKey],
                    let artist = metadata[artistKey],
                    let album = metadata[albumKey],
                    // Some formats (like Matroska) have the stream duration set to AV_NOPTS_VALUE, while exposing the
                    // real value in the format context.
                    let duration = duration(stream.pointee.duration).map({ duration in
                      av_q2d(
                        av_mul_q(
                          av_make_q(Int32(duration), 1),
                          stream.pointee.time_base
                        )
                      )
                    })
                    ?? duration(fmtContext!.pointee.duration).map({ Double($0 / FFAV_TIME_BASE) }) else {
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

                    let width = frame.frame.pointee.width
                    let height = frame.frame.pointee.height

                    guard let scaleContext = FFScaleContext(
                      srcWidth: width,
                      srcHeight: height,
                      srcFormat: frame.frame.pointee.pixelFormat!,
                      dstWidth: width,
                      dstHeight: height,
                      dstFormat: format
                    ) else {
                      Logger.ffmpeg.error("Could not create swscale context")

                      return nil
                    }

                    try scale(scaleContext.context, source: frame.frame, destination: scaledFrame.frame)

                    let buffer = scaledFrame.frame.pointee.buf.0!
                    data.append(buffer.pointee.data, count: buffer.pointee.size)
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

                  let width = frame.frame.pointee.width
                  let height = frame.frame.pointee.height

                  guard let scaleContext = FFScaleContext(
                    srcWidth: width,
                    srcHeight: height,
                    srcFormat: frame.frame.pointee.pixelFormat!,
                    dstWidth: width,
                    dstHeight: height,
                    dstFormat: format
                  ) else {
                    Logger.ffmpeg.error("Could not create swscale context")

                    return nil
                  }

                  try scale(scaleContext.context, source: frame.frame, destination: scaledFrame.frame)

                  let buffer = scaledFrame.frame.pointee.buf.0!
                  data.append(buffer.pointee.data, count: buffer.pointee.size)
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

              func position(_ metadata: [String: String], numberKey: String, totalKey: String) -> LibraryTrackPosition? {
                guard let numberValue = metadata[numberKey],
                      let number = Int(numberValue),
                      let totalValue = metadata[totalKey],
                      let total = Int(totalValue) else {
                  return nil
                }

                return LibraryTrackPosition(number: number, total: total)
              }

              return LibraryTrack(
                url: url,
                title: title,
                artist: artist,
                album: album,
                coverImage: NSImage(cgImage: image, size: NSSize(width: width, height: height)),
                duration: Duration.seconds(duration),
                albumArtist: metadata[albumArtistKey],
                track: position(metadata, numberKey: trackNumberKey, totalKey: trackTotalKey),
                disc: position(metadata, numberKey: discNumberKey, totalKey: discTotalKey)
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
  }
}
