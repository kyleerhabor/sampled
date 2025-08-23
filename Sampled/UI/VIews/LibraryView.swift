//
//  LibraryView.swift
//  Sampled
//
//  Created by Kyle Erhabor on 10/7/24.
//

import CFFmpeg
import SampledFFmpeg
import Algorithms
@preconcurrency import AVFoundation
import OSLog
import SwiftUI
import Synchronization

// item is documented as:
//
//   A generic base type for most objects, such as files or directories.
//
// In spite of this, file importers don't recognize selecting folders. folder works around this by making it explicit.
let libraryContentTypes: [UTType] = [.item, .folder]

struct LibraryTrackPositionItemView: View {
  let item: Int

  var body: some View {
    Text(item, format: .number.grouping(.never))
      .monospacedDigit()
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

func race(
  _ this: @Sendable @escaping () async -> Void,
  other: @Sendable @escaping () async -> Void
) async -> Void {
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

struct LibraryYearView: View {
  let yearDate: Date

  var body: some View {
    Text(yearDate, format: .dateTime.year())
      .monospacedDigit()
      .environment(\.timeZone, .gmt)
  }
}

struct LibraryView: View {
  @Environment(LibraryModel.self) private var library
  @State private var selection = Set<LibraryTrackModel.ID>()
  @State private var selectedTracks = [LibraryTrackModel]()
  @State private var infoTrack = LibraryInfoTrackModel()
  @State private var sortOrder: [KeyPathComparator<LibraryTrackModel>] = [
//    KeyPathComparator(\.albumName),
//    KeyPathComparator(\.discNumber),
//    KeyPathComparator(\.trackNumber),
//    KeyPathComparator(\.title),
  ]

  var body: some View {
    Table(library.tracks, selection: $selection, sortOrder: $sortOrder) {
      TableColumn("Library.Column.TrackNumber.Name"/*, sortUsing: KeyPathComparator(\.trackNumber)*/) { track in
        LibraryTrackPositionItemView(item: track.trackNumber ?? 0)
          .visible(track.trackNumber != nil)
      }
      .alignment(.numeric)

      TableColumn("Library.Column.DiscNumber.Name"/*, sortUsing: KeyPathComparator(\.discNumber)*/) { track in
        LibraryTrackPositionItemView(item: track.discNumber ?? 0)
          .visible(track.discNumber != nil)
      }
      .alignment(.numeric)

      TableColumn("Library.Column.Title.Name") { track in
        Text(track.title ?? "")
      }

      TableColumn("Library.Column.Artist.Name"/*, sortUsing: KeyPathComparator(\.artistName)*/) { track in
        Text(track.artistName ?? "")
      }

      TableColumn("Library.Column.Album.Name"/*, sortUsing: KeyPathComparator(\.albumName)*/) { track in
        Text(track.albumName ?? "")
      }

      TableColumn("Library.Column.AlbumArtist.Name"/*, sortUsing: KeyPathComparator(\.albumArtistName)*/) { track in
        Text(track.albumArtistName ?? "")
      }

      TableColumn("Library.Column.AlbumYear.Name"/*, sortUsing: KeyPathComparator(\.yearDate)*/) { track in
        LibraryYearView(yearDate: track.albumDate ?? .distantFuture)
          .visible(track.albumDate != nil)
      }
      .alignment(.numeric)

      TableColumn("Library.Column.Duration.Name"/*, sortUsing: KeyPathComparator(\.duration)*/) { track in
        LibraryTrackDurationView(duration: track.duration)
      }
      .alignment(.numeric)
    }
    .contextMenu { ids in
      Button("Finder.Item.Show") {
        let urls = library.tracks.filter(ids: ids).map(\.source.url)

        NSWorkspace.shared.activateFileViewerSelecting(urls)
      }
    } primaryAction: { ids in
      guard let track = library.tracks.filter(ids: ids).first else {
        return
      }

//      Task {
//        await Self.play(track: track)
//      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      VStack(spacing: 0) {
        Divider()

        // TODO: Replace with current track
        let track = library.tracks.first

        VStack {
          Text(track?.title ?? "")
          Text(track?.albumName ?? "")
            .foregroundStyle(.secondary)
        }
        .padding()
      }
      .background(in: .rect)
    }
    .focusedSceneValue(infoTrack)
    .task {
      await library.loadData()
    }
    .task {
      await library.load()
    }
    .onChange(of: selection) {
      let tracks = library.tracks.filter(ids: selection)
      // Would reducing once optimize the performance?
      //
      // TODO: Handle infoTrack.albumArtwork.
      infoTrack.title = tracks.reduce(.empty) { $0.reduce(nextValue: $1.title) }
      infoTrack.duration = tracks.reduce(.empty) { $0.reduce(nextValue: $1.duration) }
      infoTrack.artistName = tracks.reduce(.empty) { $0.reduce(nextValue: $1.artistName) }
      infoTrack.albumName = tracks.reduce(.empty) { $0.reduce(nextValue: $1.albumName) }
      infoTrack.albumArtistName = tracks.reduce(.empty) { $0.reduce(nextValue: $1.albumArtistName) }
      infoTrack.albumDate = tracks.reduce(.empty) { $0.reduce(nextValue: $1.albumDate) }
      infoTrack.trackNumber = tracks.reduce(.empty) { $0.reduce(nextValue: $1.trackNumber) }
      infoTrack.trackTotal = tracks.reduce(.empty) { $0.reduce(nextValue: $1.trackTotal) }
      infoTrack.discNumber = tracks.reduce(.empty) { $0.reduce(nextValue: $1.discNumber) }
      infoTrack.discTotal = tracks.reduce(.empty) { $0.reduce(nextValue: $1.discTotal) }
    }
    .onChange(of: sortOrder) {
//      library.tracks.sort(using: sortOrder)
    }
  }

//  nonisolated static private func play(track: LibraryTrack) async {
//    let source = track.source
//    let item = AudioPlayerItem(url: source.url)
//
//    await source.accessingSecurityScopedResource {
//      await item.install()
//      await player.play(item: item)
//    }
//  }
}
