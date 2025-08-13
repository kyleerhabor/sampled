//
//  LibraryView.swift
//  Sampled
//
//  Created by Kyle Erhabor on 10/7/24.
//

import CFFmpeg
import SampledFFmpeg
import Algorithms
import AVFoundation
import OSLog
import SwiftUI
import Synchronization

let libraryContentTypes: [UTType] = [.item]

struct LibraryTrackPosition {
  let number: Int?
  let total: Int?
}

struct LibraryTrackArtwork {
  let image: NSImage
  let hash: Data
}

extension LibraryTrackArtwork: Equatable {
  static func ==(lhs: Self, rhs: Self) -> Bool {
    return lhs.hash == rhs.hash
  }
}

struct LibraryTrack {
  let source: URLSource
  let title: String
  let duration: Duration
  let artistName: String?
  let albumTitle: String?
  let albumArtistName: String?
  // When this is inevitably persisted, only the year should be stored since it's the only time information.
  let yearDate: Date?
  let artwork: LibraryTrackArtwork?
  let track: LibraryTrackPosition?
  let disc: LibraryTrackPosition?
}

extension LibraryTrack: Identifiable {
  var id: URL {
    source.url
  }
}

struct LibraryTrackPositionItemView: View {
  let item: Int

  var body: some View {
    Text(item, format: .number.grouping(.never))
      .monospacedDigit()
  }
}

struct LibraryTrackArtistsView: View {
  let artists: [String]

  var body: some View {
    Text(artists, format: .list(type: .and, width: .short))
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

// TODO: Replace with dispatch queue or some other lock
//
// Actors are just not it.
actor AudioPlayerItem {
  private let url: URL
  private let formatContext: FFFormatContext
  private var codecContext: FFCodecContext?
  private let resampleContext: FFResampleContext
  private let packet: FFPacket
  private let frame: FFFrame
  private let resampleFrame: FFFrame
  private var streami: Int32?

  init(url: URL) {
    self.url = url
    self.formatContext = FFFormatContext()
    self.resampleContext = FFResampleContext()
    self.packet = FFPacket()
    self.frame = FFFrame()
    self.resampleFrame = FFFrame()
  }

  func install() {
    do {
      try openInput(&formatContext.context, at: url.pathString)
    } catch {
      Logger.ffmpeg.error("\(error)")

      return
    }

    do {
      try findStreamInfo(formatContext.context)
    } catch {
      Logger.ffmpeg.error("\(error)")

      return
    }

    var decoder: UnsafePointer<AVCodec>!
    let streami: Int32

    do {
      streami = try findBestStream(formatContext.context, type: .audio, decoder: &decoder)
    } catch {
      Logger.ffmpeg.error("\(error)")

      return
    }

    self.streami = streami

    let stream = formatContext.context.pointee.streams[Int(streami)]!
    let codecContext = FFCodecContext(codec: decoder)
    codecContext.context.pointee.pkt_timebase = stream.pointee.time_base

    self.codecContext = codecContext

    do {
      try copyCodecParameters(codecContext.context, params: stream.pointee.codecpar)
    } catch {
      Logger.ffmpeg.error("\(error)")

      return
    }

    do {
      try openCodec(codecContext.context, codec: decoder)
    } catch {
      Logger.ffmpeg.error("\(error)")

      return
    }

    streams(formatContext.context).forEach { $0!.pointee.discard = AVDISCARD_ALL }

    stream.pointee.discard = AVDISCARD_NONE
  }

  var info: Info {
    let context = codecContext!.context!
    let channelLayout = context.pointee.ch_layout
    let sampleRate = context.pointee.sample_rate

    return Info(channelLayout: Self.channelLayout(from: channelLayout), sampleRate: Double(sampleRate))
  }

  nonisolated static func channelLayout(from channelLayout: AVChannelLayout) -> AudioChannelLayout {
    struct Item {
      let channel: AVChannel
      let bitmap: AudioChannelBitmap
    }

    let items = [
      Item(channel: AV_CHAN_FRONT_LEFT, bitmap: .bit_Left),
      Item(channel: AV_CHAN_FRONT_RIGHT, bitmap: .bit_Right),
      Item(channel: AV_CHAN_FRONT_CENTER, bitmap: .bit_Center),
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

    return layout
  }

  func resampleReadFrame(
    source frame: UnsafePointer<AVFrame>!,
    channelLayout: AVChannelLayout,
    sampleRate: Int32,
    format: AVSampleFormat,
    buffers: inout [Data]
  ) throws(FFError) {
    try SampledFFmpeg.resampleFrame(
      resampleContext.context,
      source: frame,
      destination: resampleFrame.frame,
      channelLayout: channelLayout,
      sampleRate: sampleRate,
      sampleFormat: format.rawValue
    )

    let stride = resampleFrame.frame.pointee.nb_samples * av_get_bytes_per_sample(format)
    let bufferCount = bufferCount(sampleFormat: format, channelCount: channelLayout.nb_channels)
    let range = 0..<Int(bufferCount)

    range.forEach { i in
      buffers[i].append(resampleFrame.frame.pointee.extended_data[i]!, count: Int(stride))
    }
  }

  func readFrame(
    channelLayout: AVChannelLayout,
    sampleRate: Int32,
    format: AVSampleFormat,
    buffers: inout [Data]
  ) throws(FFError) {
    try configureResampler(resampleContext.context, source: frame.frame, destination: resampleFrame.frame)
    try resampleReadFrame(
      source: frame.frame,
      channelLayout: channelLayout,
      sampleRate: sampleRate,
      format: format,
      buffers: &buffers
    )

    av_frame_unref(resampleFrame.frame)

    do {
      // I *believe* this is how you retrieve the remaining samples in the FIFO buffer.
      try resampleReadFrame(
        source: nil,
        channelLayout: channelLayout,
        sampleRate: sampleRate,
        format: format,
        buffers: &buffers
      )
    } catch let error where error.code == .outputChanged {
      Logger.ffmpeg.info("Dropped.")
      // Fallthough
      //
      // Resampling WAVE seems to always produce this error. I assume no data is in the FIFO buffer, and therefore it
      // appears the output has (somehow) changed. I'm not exactly sure why, but I am sure this fallthrough produces no
      // known issues.
    }
  }

  func read() throws(FFError) -> [Data] {
    let format = AV_SAMPLE_FMT_FLTP
    let bytesPerSample = av_get_bytes_per_sample(format)
    let context = codecContext!.context!
    let channelLayout = context.pointee.ch_layout
    let sampleRate = context.pointee.sample_rate
    let channelCount = channelLayout.nb_channels
    // Longer is better for energy impact
    let seconds = 4
    let capacity = Int(context.pointee.sample_rate * bytesPerSample * channelCount) * seconds
    let bufferCount = bufferCount(sampleFormat: format, channelCount: channelCount)
    var buffers = [Data](
      repeating: Data(capacity: capacity / Int(bufferCount)),
      count: Int(bufferCount)
    )

    while true {
      do {
        try SampledFFmpeg.readFrame(formatContext.context, into: packet.packet)
      } catch let error where error.code == .endOfFile {
        break
      }

      defer {
        av_packet_unref(packet.packet)
      }

      guard packet.packet.pointee.stream_index == streami else {
        continue
      }

      try sendPacket(context, packet: packet.packet)

      while true {
        do {
          try receiveFrame(context, frame: frame.frame)
        } catch let error where error.code == .resourceTemporarilyUnavailable {
          break
        }

        try readFrame(channelLayout: channelLayout, sampleRate: sampleRate, format: format, buffers: &buffers)
      }

      if buffers.map(\.count).sum() >= capacity {
        return buffers
      }
    }

    // This is likely to eventually throw an end of file error.
    try sendPacket(context, packet: nil)

    while true {
      do {
        try receiveFrame(context, frame: frame.frame)
      } catch let error where error.code == .endOfFile {
        return buffers
      }

      try readFrame(channelLayout: channelLayout, sampleRate: sampleRate, format: format, buffers: &buffers)
    }
  }

  struct Info {
    let channelLayout: AudioChannelLayout
    let sampleRate: Double

    var format: AVAudioFormat {
      AVAudioFormat(
        standardFormatWithSampleRate: Double(sampleRate),
        channelLayout: withUnsafePointer(to: channelLayout) { pointer in
          AVAudioChannelLayout(layout: pointer)
        }
      )
    }
  }
}

func race(_ this: @escaping () async -> Void, other: @escaping () async -> Void) async -> Void {
  await withTaskGroup(of: Void.self) { group in
    await withCheckedContinuation { continuation in
      group.addTask {
        continuation.resume()
        await this()
      }
    }

    group.addTask {
      await Task.yield()
      await other()
    }

    await group.waitForAll()
  }
}

actor AudioPlayer {
  private let engine: AVAudioEngine
  private var players: Set<AVAudioPlayerNode>

  init() {
    self.engine = AVAudioEngine()
    self.players = []
  }

  static private func read(info: AudioPlayerItem.Info, buffers: inout [Data]) -> AVAudioPCMBuffer? {
    let stride = MemoryLayout<Float>.stride
    let frameCount = AVAudioFrameCount(buffers[0].count / stride)

    guard let buffer = AVAudioPCMBuffer(pcmFormat: info.format, frameCapacity: frameCount) else {
      return nil
    }

    for bufferi in buffers.indices {
      buffers[bufferi].withUnsafeMutableBytes { pointer in
        pointer.withMemoryRebound(to: Float.self) { pointer in
          buffer.floatChannelData![bufferi].moveUpdate(from: pointer.baseAddress!, count: pointer.count)
        }
      }
    }

    buffer.frameLength = frameCount

    return buffer
  }

  nonisolated static private func read(item: AudioPlayerItem, info: AudioPlayerItem.Info) async -> AVAudioPCMBuffer? {
    var buffers: [Data]

    do {
      buffers = try await item.read()
    } catch {
      Logger.ffmpeg.error("\(error)")

      return nil
    }

    guard let buffer = Self.read(info: info, buffers: &buffers) else {
      return nil
    }

    #if DEBUG
    let url = URL.applicationSupportDirectory.appending(
      components: Bundle.appID, "audio.raw",
      directoryHint: .notDirectory
    )

    do {
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

      let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
      let buffer = buffers.reduce(into: Data()) { partialResult, buffer in
        let count = Int(buffer.mDataByteSize)

        partialResult.append(UnsafePointer(buffer.mData!.bindMemory(to: UInt8.self, capacity: count)), count: count)
      }

      try buffer.write(to: url)
    } catch {
      Logger.model.error("\(error)")
    }

    #endif

    return buffer
  }

  nonisolated private func playItem(
    player: AVAudioPlayerNode,
    item: AudioPlayerItem,
    info: AudioPlayerItem.Info
  ) async {
    while let buffer = await Self.read(item: item, info: info) {
      await player.scheduleBuffer(buffer)
    }
  }

  nonisolated private func play(
    player: AVAudioPlayerNode,
    item: AudioPlayerItem,
    info: AudioPlayerItem.Info
  ) async {
    // Yeah, we probably shouldn't implement a literal race condition as our algorithm for queueless playback.
    await race { [weak self] in
      await self?.playItem(player: player, item: item, info: info)
    } other: { [weak self] in
      await self?.playItem(player: player, item: item, info: info)
    }
  }

  func play(item: AudioPlayerItem) async {
    let info = await item.info
    let player = AVAudioPlayerNode()
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: info.format)

    Task {
      await play(player: player, item: item, info: info)
    }

    do {
      try engine.start()
    } catch {
      Logger.model.error("\(error)")

      return
    }

    player.play()
  }
}

let player = AudioPlayer()

//extension Mutex where Value == Void {
//  init() {
//    self.init(())
//  }
//
//  borrowing func withLock<Result, E>(
//    _ body: () throws(E) -> sending Result
//  ) throws(E) -> sending Result where E: Error, Result: ~Copyable {
//    try self.withLock(body)
//  }
//}
//
//struct MusicPlayerItem {
//  private let url: URL
//
//  private let formatContext: FFFormatContext
//  private var codecContext: FFCodecContext?
//  private let resampleContext: FFResampleContext
//  private let packet: FFPacket
//  private let frame: FFFrame
//  private let resampleFrame: FFFrame
//  private var streami: Int32?
//
//  init(url: URL) {
//    self.url = url
//    self.formatContext = FFFormatContext()
//    self.resampleContext = FFResampleContext()
//    self.packet = FFPacket()
//    self.frame = FFFrame()
//    self.resampleFrame = FFFrame()
//  }
//
//  func open() {
//    do {
//      try openInput(&formatContext.context, at: url.pathString)
//    } catch {
//      Logger.ffmpeg.error("\(error)")
//
//      return
//    }
//
//    do {
//      try findStreamInfo(formatContext.context)
//    } catch {
//      Logger.ffmpeg.error("\(error)")
//
//      return
//    }
//
//    var decoder: UnsafePointer<AVCodec>!
//    let streami: Int32
//
//    do {
//      streami = try findBestStream(formatContext.context, type: .audio, decoder: &decoder)
//    } catch {
//      Logger.ffmpeg.error("\(error)")
//
//      return
//    }
//
//    self.streami = streami
//
//    let stream = formatContext.context.pointee.streams[Int(streami)]!
//    let codecContext = FFCodecContext(codec: decoder)
//    codecContext.context.pointee.pkt_timebase = stream.pointee.time_base
//
//    self.codecContext = codecContext
//
//    do {
//      try copyCodecParameters(codecContext.context, params: stream.pointee.codecpar)
//    } catch {
//      Logger.ffmpeg.error("\(error)")
//
//      return
//    }
//
//    do {
//      try openCodec(codecContext.context, codec: decoder)
//    } catch {
//      Logger.ffmpeg.error("\(error)")
//
//      return
//    }
//
//    streams(formatContext.context).forEach { $0!.pointee.discard = AVDISCARD_ALL }
//
//    stream.pointee.discard = AVDISCARD_NONE
//  }
//
//  func close() {
//    avformat_close_input(&formatContext.context)
//  }
//}

//struct MusicPlayer {
//  static private let lock = Mutex()
//  static private let engine = AVAudioEngine()
//  static private let player = AVAudioPlayerNode()
//
//  static func play() {
//    lock.withLock {
//
//    }
//  }
//}

struct LibraryView: View {
  @Environment(LibraryModel.self) private var library
  @State private var isFileImporterPresented = false
  @State private var selection = Set<LibraryTrack.ID>()
  @State private var selectedTracks = [LibraryTrack]()
  @State private var trackModel = LibraryInfoTrackModel()

  var body: some View {
    Table(library.tracks, selection: $selection) {
      TableColumn("Track.Column.Track") { track in
        LibraryTrackPositionItemView(item: track.track?.number ?? 0)
          .visible(track.track?.number != nil)
      }
      .alignment(.numeric)

      TableColumn("Track.Column.Disc") { track in
        LibraryTrackPositionItemView(item: track.disc?.number ?? 0)
          .visible(track.disc?.number != nil)
      }
      .alignment(.numeric)

      TableColumn("Track.Column.Title", value: \.title)
      TableColumn("Track.Column.Artist") { track in
        Text(track.artistName ?? "")
      }

      TableColumn("Track.Column.Album") { track in
        Text(track.albumTitle ?? "")
      }

      TableColumn("Track.Column.AlbumArtist") { track in
        Text(track.albumArtistName ?? "")
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
    .safeAreaInset(edge: .bottom, spacing: 0) {
      VStack(spacing: 0) {
        Divider()

        Text("...")
          .padding()
      }
      .background(in: .rect)
    }
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
    .focusedSceneValue(trackModel)
    .onChange(of: selection) {
      trackModel.title = .empty
      trackModel.artistName = .empty
      trackModel.albumName = .empty
      trackModel.albumArtistName = .empty
      trackModel.yearDate = .empty
      trackModel.trackNumber = .empty
      trackModel.trackTotal = .empty
      trackModel.discNumber = .empty
      trackModel.discTotal = .empty
      trackModel.artwork = .empty

      let tracks = library.tracks.filter(in: selection, by: \.id)
      // Would reducing optimize the performance?
      trackModel.title = LibraryInfoTrackProperty(values: tracks.map(\.title))
      trackModel.artistName = LibraryInfoTrackProperty(values: tracks.map(\.artistName))
      trackModel.albumName = LibraryInfoTrackProperty(values: tracks.map(\.albumTitle))
      trackModel.albumArtistName = LibraryInfoTrackProperty(values: tracks.map(\.albumArtistName))
      trackModel.yearDate = LibraryInfoTrackProperty(values: tracks.map(\.yearDate))
      trackModel.trackNumber = LibraryInfoTrackProperty(values: tracks.map(\.track?.number))
      trackModel.trackTotal = LibraryInfoTrackProperty(values: tracks.map(\.track?.total))
      trackModel.discNumber = LibraryInfoTrackProperty(values: tracks.map(\.disc?.number))
      trackModel.discTotal = LibraryInfoTrackProperty(values: tracks.map(\.disc?.total))
      trackModel.duration = LibraryInfoTrackProperty(values: tracks.map(\.duration))
      trackModel.artwork = LibraryInfoTrackProperty(values: tracks.map(\.artwork))
    }
  }

  nonisolated static private func load(urls: [URL]) async -> [LibraryTrack] {
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

  nonisolated static private func play(track: LibraryTrack) async {
    let source = track.source
    let item = AudioPlayerItem(url: source.url)

    await source.accessingSecurityScopedResource {
      await item.install()
      await player.play(item: item)
    }
  }
}
