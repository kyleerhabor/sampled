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

struct LibraryTrack {
  let source: URLSource

  let title: String
  let duration: Duration
  let artist: String?
  let artists: [String]
  let album: String?
  let albumArtist: String?
  let date: Date?
  let coverImage: NSImage?
  let track: LibraryTrackPosition?
  let disc: LibraryTrackPosition?
}

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

struct LibraryTrackArtistsView: View {
  let artists: [String]

  var body: some View {
    Text(artists, format: .list(type: .and, width: .short))
  }
}

struct LibraryTrackArtistContentView: View {
  @AppStorage(StorageKeys.preferArtistsDisplay.name) private var preferArtistsDisplay = StorageKeys.preferArtistsDisplay.defaultValue

  let artists: [String]
  let artist: String?

  var body: some View {
    if preferArtistsDisplay {
      LibraryTrackArtistsView(artists: artists)
    } else {
      Text(artist ?? "")
    }
  }
}

struct LibraryTrackDurationView: View {
  let duration: Duration

  var body: some View {
    Text(
      duration,
      format: .time(
        pattern: duration >= .hour
        ? .hourMinuteSecond(padHourToLength: 2, roundFractionalSeconds: .towardZero)
        : .minuteSecond(padMinuteToLength: 2, roundFractionalSeconds: .towardZero)
      )
    )
    .monospacedDigit()
  }
}

struct LibraryView: View {
  @AppStorage(StorageKeys.preferArtistsDisplay.name) private var preferArtistsDisplay = StorageKeys.preferArtistsDisplay.defaultValue
  @State private var isFileImporterPresented = false
  @State private var tracks = [LibraryTrack]()
  @State private var selection = Set<LibraryTrack.ID>()
  @State private var popoverTrack: LibraryTrack?

  var body: some View {
    Table(tracks, selection: $selection) {
      TableColumn("Track.Column.Track") { track in
        LibraryTrackPositionView(item: track.track?.number)
      }
      .alignment(.numeric)

      TableColumn("Track.Column.Disc") { track in
        LibraryTrackPositionView(item: track.disc?.number)
      }
      .alignment(.numeric)

      TableColumn("Track.Column.Duration") { track in
        LibraryTrackDurationView(duration: track.duration)
      }
      .alignment(.numeric)

      TableColumn("Track.Column.Title", value: \.title)
      TableColumn(preferArtistsDisplay ? "Track.Column.Artists" : "Track.Column.Artist") { track in
        LibraryTrackArtistContentView(artists: track.artists, artist: track.artist)
      }

      TableColumn("Track.Column.Album") { track in
        Text(track.album ?? "")
      }

      TableColumn("Track.Column.AlbumArtist") { track in
        Text(track.albumArtist ?? "")
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
//    .safeAreaInset(edge: .bottom, spacing: 0) {
//      VStack {
//        Divider()
//
//        Text("...")
//          .padding()
//      }
//      .background(in: .rect)
//    }
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

      Task {
        tracks = await Self.process(urls: urls)
      }
    }
    .focusedSceneValue(\.open, AppMenuActionItem(identity: .library, isEnabled: true) {
      isFileImporterPresented = true
    })
    // TODO: Replace.
    .focusedSceneValue(\.tracks, tracks.filter(in: selection, by: \.id))
  }

  // TODO: Rename.
  static private func write(
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

  static private func readImage(
    formatContext: UnsafeMutablePointer<AVFormatContext>!,
    packet: UnsafeMutablePointer<AVPacket>!,
    frame: UnsafeMutablePointer<AVFrame>!,
    scaledFrame: UnsafeMutablePointer<AVFrame>!
  ) -> CGImage? {
    var decoder: UnsafePointer<AVCodec>!
    let streami: Int32

    do {
      streami = try findBestStream(formatContext, ofType: .video, decoder: &decoder)
    } catch {
      Logger.ffmpeg.error("\(error)")

      return nil
    }

    let stream = formatContext!.pointee.streams[Int(streami)]!
    let codecContext = FFCodecContext(codec: decoder)

    do {
      try copyCodecParameters(codecContext.context, params: stream.pointee.codecpar)
      try open(codecContext.context, codec: decoder)
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
        switch try iterateReceivePacket(formatContext, packet: packet) {
          case .ok:
            break
          case .endOfFile:
            break loop
        }

        defer {
          av_packet_unref(packet)
        }

        guard packet.pointee.stream_index == streami else {
          continue
        }

        switch try iterateSendPacket(codecContext.context, packet: packet) {
          case .ok:
            break
        }

        loop2:
        while true {
          switch try iterateReceiveFrame(codecContext.context, frame: frame) {
            case .ok:
              break
            case .resourceTemporarilyUnavailable:
              break loop2
            default:
              return nil
          }

          try Self.write(data: &data, frame: frame, scaledFrame: scaledFrame, format: format)
        }
      }

      switch try iterateSendPacket(codecContext.context, packet: nil) {
        case .ok:
          break
      }

      loop:
      while true {
        switch try iterateReceiveFrame(codecContext.context, frame: frame) {
          case .ok:
            break
          case .endOfFile:
            break loop
          default:
            return nil
        }

        try Self.write(data: &data, frame: frame, scaledFrame: frame, format: format)
      }
    } catch {
      Logger.ffmpeg.error("\(error)")

      return nil
    }

    let width = Int(codecContext.context.pointee.width)
    let height = Int(codecContext.context.pointee.height)

    guard let provider = CGDataProvider(data: data as CFData) else {
      return nil
    }

    return CGImage(
      width: width,
      height: height,
      bitsPerComponent: Int(bitsPerPixel / Int(formatDesc.pointee.nb_components)),
      bitsPerPixel: bitsPerPixel,
      bytesPerRow: Int(scaledFrame.pointee.linesize.0),
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      // I don't know why, but specifying premultipliedLast makes transparency work (as opposed to
      // noneSkipLast). In fact, I don't really understand this property at all.
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: provider,
      decode: nil,
      shouldInterpolate: true,
      intent: .defaultIntent
    )
  }

  static private func process(urls: [URL]) async -> [LibraryTrack] {
    let frame = FFFrame()

    defer {
      av_frame_unref(frame.frame)
    }

    let scaledFrame = FFFrame()
    let packet = FFPacket()

    return urls.compactMap { url in
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
            let artistsKey = "artists"
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
                    partialResult[artistKey] = value
                  case "ARTISTS": // This may be specific to MusicBrainz.
                    partialResult[artistsKey] = value
                      .split(separator: ";")
                      .map { $0.trimmingCharacters(in: .whitespaces) }
                  case "album", "ALBUM":
                    partialResult[albumKey] = value
                  case "album_artist", "ALBUM_ARTIST":
                    partialResult[albumArtistKey] = value
                  case "date", "DATE": // ORIGINALDATE and ORIGINALYEAR exist, but seem specific to MusicBrainz.
                    let date: Date

                    do {
                      date = try Date(value, strategy: .iso8601.year())
                    } catch {
                      Logger.ui.error("\(error)")

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
            //
            // TODO: Consider calculating duration from audio stream.
            //
            // This would involve performing arithmetic on the sample count.
            guard let duration = duration(stream.pointee.duration)
              .map({ Double($0) * av_q2d(stream.pointee.time_base) })
                    ?? duration(fmtContext!.pointee.duration).map({ Double($0 / FF_TIME_BASE) }) else {
              return nil
            }

            let artist = metadata[artistKey] as? String
            let image = Self.readImage(
              formatContext: fmtContext,
              packet: packet.packet,
              frame: frame.frame,
              scaledFrame: scaledFrame.frame
            )

            return LibraryTrack(
              source: source,
              title: metadata[titleKey] as? String ?? url.lastPath,
              duration: Duration.seconds(duration),
              artist: metadata[artistKey] as? String,
              artists: metadata[artistsKey] as? [String] ?? artist.map { [$0] } ?? [],
              album: metadata[albumKey] as? String,
              albumArtist: metadata[albumArtistKey] as? String,
              date: metadata[dateKey] as? Date,
              coverImage: image.map { NSImage(cgImage: $0, size: .zero) },
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
}
