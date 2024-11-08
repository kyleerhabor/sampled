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
import AVFoundation
import MediaPlayer
import OSLog
import SwiftUI

let libraryContentTypes: [UTType] = [.item]

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
  let coverImage: CGImage?
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

actor AudioPlayer {
  private let engine: AVAudioEngine
  private var players: Set<AVAudioPlayerNode>

  init(engine: AVAudioEngine) {
    self.engine = engine
    self.players = []
  }

  func play(buffer: AVAudioPCMBuffer) throws {
    let player = AVAudioPlayerNode()
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: buffer.format)

    Task {
      await player.scheduleBuffer(buffer)

      players.remove(player)

      if players.isEmpty {
        engine.stop()
      }
    }

    try engine.start()
    players.forEach { $0.stop() }
    players.insert(player)

    player.play()
  }
}

let player = AudioPlayer(engine: AVAudioEngine())

struct LibraryView: View {
  @AppStorage(StorageKeys.preferArtistsDisplay.name) private var preferArtistsDisplay = StorageKeys.preferArtistsDisplay.defaultValue
  @Environment(LibraryModel.self) private var library
  @State private var isFileImporterPresented = false
  @State private var selection = Set<LibraryTrack.ID>()

  var body: some View {
    Table(library.tracks, selection: $selection) {
      TableColumn("Track.Column.Track") { track in
        LibraryTrackPositionView(item: track.track?.number)
      }
      .alignment(.numeric)

      TableColumn("Track.Column.Disc") { track in
        LibraryTrackPositionView(item: track.disc?.number)
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

      TableColumn("Track.Column.Duration") { track in
        LibraryTrackDurationView(duration: track.duration)
      }
      .alignment(.numeric)
    }
    .contextMenu { ids in
      Button("Finder.Item.Show") {
        let urls = library.tracks
          .filter(in: ids, by: \.id)
          .map(\.source.url)

        NSWorkspace.shared.activateFileViewerSelecting(urls)
      }
    } primaryAction: { ids in
      guard let track = library.tracks.filter(in: ids, by: \.id).first else {
        return
      }

      Task {
        await Self.play(track: track)
      }
    }
//    .safeAreaInset(edge: .bottom, spacing: 0) {
//      VStack(spacing: 0) {
//        Divider()
//
//        Text("...")
//          .padding()
//      }
//      .background(in: .rect)
//    }
    .fileImporter(
      isPresented: $isFileImporterPresented,
      allowedContentTypes: libraryContentTypes,
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
        library.tracks = await Self.load(urls: urls)
      }
    }
    .focusedSceneValue(\.importTracks, AppMenuActionItem(identity: library.id, isEnabled: true) {
      isFileImporterPresented = true
    })
    // TODO: Replace.
    .focusedSceneValue(\.tracks, library.tracks.filter(in: selection, by: \.id))
  }

  static private func load(urls: [URL]) async -> [LibraryTrack] {
    urls.compactMap { url in
      let source = URLSource(url: url, options: [.withReadOnlySecurityScope, .withoutImplicitSecurityScope])

      return source.accessingSecurityScopedResource {
        do {
          return try LibraryModel.read(source: source)
        } catch {
          Logger.ffmpeg.error("\(error)")

          return nil
        }
      }
    }
  }

  nonisolated static private func resampleFrame(
    _ context: OpaquePointer!,
    source: UnsafePointer<AVFrame>!,
    destination: UnsafeMutablePointer<AVFrame>!,
    channelLayout: AVChannelLayout,
    sampleRate: Int32,
    sampleFormat: AVSampleFormat,
    buffers: inout [Data]
  ) throws(FFError) {
    try ForwardFFmpeg.resampleFrame(
      context,
      source: source,
      destination: destination,
      channelLayout: channelLayout,
      sampleRate: sampleRate,
      sampleFormat: sampleFormat.rawValue
    )

    let stride = destination.pointee.nb_samples * av_get_bytes_per_sample(AVSampleFormat(rawValue: destination.pointee.format))
    let bufferCount = bufferCount(sampleFormat: sampleFormat, channelCount: channelLayout.nb_channels)

    for channeli in 0..<Int(bufferCount) {
      buffers[channeli].append(destination.pointee.extended_data[channeli]!, count: Int(stride))
    }
  }

  nonisolated static private func play(track: LibraryTrack) async {
    let source = track.source
    let buffer: AVAudioPCMBuffer? = source.accessingSecurityScopedResource {
      let pathString = source.url.pathString
      let formatContext = FFFormatContext()

      do {
        return try openingInput(&formatContext.context, at: pathString) { formatContext in
          do {
            try findStreamInfo(formatContext)
          } catch {
            Logger.ffmpeg.error("\(error)")

            return nil
          }

          var decoder: UnsafePointer<AVCodec>!
          let streami: Int32

          do {
            streami = try findBestStream(formatContext, type: .audio, stream: -1, decoder: &decoder)
          } catch {
            Logger.ffmpeg.error("\(error)")

            return nil
          }

          let stream = formatContext!.pointee.streams[Int(streami)]!
          let codecContext = FFCodecContext(codec: decoder)

          do {
            try copyCodecParameters(codecContext.context, params: stream.pointee.codecpar)
            try openCodec(codecContext.context, codec: decoder)
          } catch {
            Logger.ffmpeg.error("\(error)")

            return nil
          }

          let packet = FFPacket()
          let frame = FFFrame()
          let resampleContext = FFResampleContext()
          let resampled = FFFrame()
          let channelLayout = codecContext.context.pointee.ch_layout
          let sampleRate = codecContext.context.pointee.sample_rate
          let sampleFormat = AV_SAMPLE_FMT_FLTP
          let bufferCount = bufferCount(sampleFormat: sampleFormat, channelCount: channelLayout.nb_channels)
          var buffers = [Data](
            repeating: Data(),
            count: Int(bufferCount)
          )

          do {
            func action() throws(FFError) {
              try configureResampler(resampleContext.context, source: frame.frame, destination: resampled.frame)
              try resampleFrame(
                resampleContext.context,
                source: frame.frame,
                destination: resampled.frame,
                channelLayout: channelLayout,
                sampleRate: sampleRate,
                sampleFormat: sampleFormat,
                buffers: &buffers
              )

              av_frame_unref(resampled.frame)

              do {
                // I *believe* this is how you retrieve the remaining samples in the FIFO buffer.
                try resampleFrame(
                  resampleContext.context,
                  source: nil,
                  destination: resampled.frame,
                  channelLayout: channelLayout,
                  sampleRate: sampleRate,
                  sampleFormat: sampleFormat,
                  buffers: &buffers
                )
              } catch let error where error.code == .outputChanged {
                // Fallthough
                //
                // Resampling WAVE seems to always produce this error. I assume no data is in the FIFO buffer, and
                // therefore it appears the output has (somehow) changed. I'm not exactly sure, but I am sure that this
                // fallthrough produces no known issues.
              }
            }

            loop:
            while true {
              switch try iterateReadFrame(formatContext, into: packet.packet) {
                case .ok:
                  break
                case .endOfFile:
                  break loop
              }

              guard packet.packet.pointee.stream_index == streami else {
                continue
              }

              switch try iterateSendPacket(codecContext.context, packet: packet.packet) {
                case .ok:
                  break
                default:
                  return nil
              }

              loop:
              while true {
                switch try iterateReceiveFrame(codecContext.context, frame: frame.frame) {
                  case .ok:
                    break
                  case .resourceTemporarilyUnavailable:
                    break loop
                  default:
                    return nil
                }

                do {
                  try action()
                } catch {
                  Logger.ffmpeg.error("\(error)")

                  return nil
                }
              }
            }

            switch try iterateSendPacket(codecContext.context, packet: nil) {
              case .ok:
                break
              default:
                return nil
            }

            loop:
            while true {
              switch try iterateReceiveFrame(codecContext.context, frame: frame.frame) {
                case .ok:
                  break
                case .endOfFile:
                  break loop
                default:
                  return nil
              }

              do {
                try action()
              } catch {
                Logger.ffmpeg.error("\(error)")

                return nil
              }
            }
          } catch {
            Logger.ffmpeg.error("\(error)")

            return nil
          }

          struct S {
            let channel: AVChannel
            let bitmap: AudioChannelBitmap
          }

          let items = [
            S(channel: AV_CHAN_FRONT_LEFT, bitmap: .bit_Left),
            S(channel: AV_CHAN_FRONT_RIGHT, bitmap: .bit_Right),
            S(channel: AV_CHAN_FRONT_CENTER, bitmap: .bit_Center),
//            S(channel: AV_CHAN_LOW_FREQUENCY, bitmap: .bit_LFEScreen),
//            S(channel: AV_CHAN_BACK_LEFT, bitmap: .bit_TopBackLeft),
//            S(channel: AV_CHAN_BACK_RIGHT, bitmap: .bit_TopBackRight),
            S(channel: AV_CHAN_FRONT_LEFT_OF_CENTER, bitmap: .bit_LeftCenter),
            S(channel: AV_CHAN_FRONT_RIGHT_OF_CENTER, bitmap: .bit_RightCenter),
//            S(channel: AV_CHAN_BACK_CENTER, bitmap: .bit_TopBackCenter),
            S(channel: AV_CHAN_TOP_FRONT_LEFT, bitmap: .bit_LeftTopFront),
            S(channel: AV_CHAN_TOP_FRONT_CENTER, bitmap: .bit_CenterTopFront),
            S(channel: AV_CHAN_TOP_FRONT_RIGHT, bitmap: .bit_RightTopFront),
            S(channel: AV_CHAN_TOP_BACK_LEFT, bitmap: .bit_TopBackLeft),
            S(channel: AV_CHAN_TOP_BACK_CENTER, bitmap: .bit_TopBackCenter),
            S(channel: AV_CHAN_TOP_BACK_RIGHT, bitmap: .bit_TopBackRight)
          ]

          let chLayout = if channelLayout.order == AV_CHANNEL_ORDER_UNSPEC {
            channelLayout.default
          } else {
            channelLayout
          }

          var layout = AudioChannelLayout()
          layout.mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelBitmap
          layout.mChannelBitmap = items.reduce(AudioChannelBitmap()) { partialResult, item in
            if chLayout.u.mask & (1 << item.channel.rawValue) == 0 {
              return partialResult
            }

            return partialResult.union(item.bitmap)
          }

          let stride = MemoryLayout<Float>.stride
          let frameCount = AVAudioFrameCount(buffers[0].count / stride)

          guard let audioBuffer = AVAudioPCMBuffer(
            pcmFormat: AVAudioFormat(
              standardFormatWithSampleRate: Double(sampleRate),
              channelLayout: AVAudioChannelLayout(layout: &layout)
            ),
            frameCapacity: frameCount
          ) else {
            return nil
          }

          for bufferi in buffers.indices {
            buffers[bufferi].withUnsafeMutableBytes { pointer in
              let count = pointer.count / stride
              let pointer = pointer.baseAddress!.bindMemory(to: Float.self, capacity: count)

              audioBuffer.floatChannelData![bufferi].moveUpdate(from: pointer, count: count)
            }
          }

          audioBuffer.frameLength = frameCount

          #if DEBUG
          let url = URL.applicationSupportDirectory.appending(
            components: Bundle.appID, "audio.raw",
            directoryHint: .notDirectory
          )

          do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: audioBuffer.audioBufferList))
            let buffer = buffers.reduce(into: Data()) { partialResult, buffer in
              let count = Int(buffer.mDataByteSize)

              partialResult.append(UnsafePointer(buffer.mData!.bindMemory(to: UInt8.self, capacity: count)), count: count)
            }

            try buffer.write(to: url)
          } catch {
            Logger.ui.error("\(error)")

            return nil
          }

          #endif

          return audioBuffer
        }
      } catch {
        Logger.ffmpeg.error("\(error)")

        return nil
      }
    }

    guard let buffer else {
      return
    }

    do {
      try await player.play(buffer: buffer)
    } catch {
      Logger.model.error("\(error)")

      return
    }
  }
}
