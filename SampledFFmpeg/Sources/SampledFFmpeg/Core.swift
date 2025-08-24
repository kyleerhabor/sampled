//
//  Core.swift
//  
//
//  Created by Kyle Erhabor on 5/18/24.
//

import CFFmpeg
import CoreFFmpeg
import AVFoundation
import Foundation

public let FFSTATUS_OK: Int32 = 0
public let FFSTATUS_EOF = FFAVERROR_EOF
public let FFSTATUS_INVALIDDATA = FFAVERROR_INVALIDDATA
public let FFSTATUS_STREAM_NOT_FOUND = FFAVERROR_STREAM_NOT_FOUND
public let FFSTATUS_ENOMEM = FFAVERROR_ENOMEM
public let FFSTATUS_EISDIR = FFAVERROR_EISDIR
public let FFSTATUS_EAGAIN = FFAVERROR_EAGAIN

public func duration(_ duration: Int64) -> Int64? {
  guard duration != FFAV_NOPTS_VALUE else {
    return nil
  }

  return duration
}

public func bufferCount(sampleFormat: AVSampleFormat, channelCount: Int32) -> Int32 {
  if sampleFormat.isInterleaved {
    return 1
  }

  return channelCount
}

public func streams(_ context: UnsafePointer<AVFormatContext>!) -> UnsafeBufferPointer<UnsafeMutablePointer<AVStream>?> {
  UnsafeBufferPointer(start: context.pointee.streams, count: Int(context.pointee.nb_streams))
}

// MARK: -

// I would make this a class, but deinit doesn't seem to play nicely with av_freep(_:).
public func allocateMemory(bytes: Int) -> UnsafeMutableRawPointer! {
  guard let allocatedMemory = av_malloc(bytes) else {
    fatalError()
  }

  return allocatedMemory
}

public func openInput(
  _ context: UnsafeMutablePointer<UnsafeMutablePointer<AVFormatContext>?>!,
  at url: UnsafePointer<CChar>!,
) throws(FFError) {
  let status = avformat_open_input(context, url, nil, nil)

  guard status == FFSTATUS_OK else {
    throw FFError(code: FFError.Code(rawValue: status))
  }
}

public func openingInput<T>(
  _ context: UnsafeMutablePointer<UnsafeMutablePointer<AVFormatContext>?>!,
  at url: UnsafePointer<CChar>!,
  _ body: (UnsafeMutablePointer<AVFormatContext>?) throws -> T,
) throws -> T where T: ~Copyable {
  try openInput(context, at: url)

  defer {
    avformat_close_input(context)
  }

  return try body(context.pointee)
}

public func openingInput<T>(
  _ context: UnsafeMutablePointer<UnsafeMutablePointer<AVFormatContext>?>!,
  at url: UnsafePointer<CChar>!,
  _ body: (UnsafeMutablePointer<AVFormatContext>?) throws(FFError) -> T,
) throws(FFError) -> T where T: ~Copyable {
  try openInput(context, at: url)

  defer {
    avformat_close_input(context)
  }

  return try body(context.pointee)
}

public func findStreamInfo(_ context: UnsafeMutablePointer<AVFormatContext>!) throws(FFError) {
  let result = avformat_find_stream_info(context, nil)

  guard result >= 0 else {
    throw FFError(code: FFError.Code(rawValue: result))
  }
}

public func findBestStream(
  _ context: UnsafeMutablePointer<AVFormatContext>!,
  type: CFFmpeg.AVMediaType,
  decoder: UnsafeMutablePointer<UnsafePointer<AVCodec>?>!,
) throws(FFError) -> Int32 {
  let result = av_find_best_stream(context, type, -1, -1, decoder, 0)

  guard result >= 0 else {
    throw FFError(code: FFError.Code(rawValue: result))
  }

  return result
}

public func readFrame(
  _ context: UnsafeMutablePointer<AVFormatContext>!,
  into packet: UnsafeMutablePointer<AVPacket>!,
) throws(FFError) {
  let status = av_read_frame(context, packet)

  guard status == FFSTATUS_OK else {
    throw FFError(code: FFError.Code(rawValue: status))
  }
}

public func copyCodecParameters(
  _ context: UnsafeMutablePointer<AVCodecContext>!,
  params: UnsafePointer<AVCodecParameters>!,
) throws(FFError) {
  let result = avcodec_parameters_to_context(context, params)

  guard result >= 0 else {
    throw FFError(code: FFError.Code(rawValue: result))
  }
}

public func openCodec(
  _ context: UnsafeMutablePointer<AVCodecContext>!,
  codec: UnsafePointer<AVCodec>!,
) throws(FFError) {
  let status = avcodec_open2(context, codec, nil)

  guard status == FFSTATUS_OK else {
    throw FFError(code: FFError.Code(rawValue: status))
  }
}

public func sendPacket(
  _ context: UnsafeMutablePointer<AVCodecContext>!,
  packet: UnsafePointer<AVPacket>!,
) throws(FFError) {
  let status = avcodec_send_packet(context, packet)

  switch status {
    case FFSTATUS_OK:
      break
    case FFSTATUS_ENOMEM:
      fatalError()
    default:
      throw FFError(code: FFError.Code(rawValue: status))
  }
}

public func receiveFrame(
  _ context: UnsafeMutablePointer<AVCodecContext>!,
  frame: UnsafeMutablePointer<AVFrame>!,
) throws(FFError) {
  let status = avcodec_receive_frame(context, frame)

  guard status == FFSTATUS_OK else {
    throw FFError(code: FFError.Code(rawValue: status))
  }
}

public func scaleFrame(
  _ context: UnsafeMutablePointer<SwsContext>!,
  source: UnsafePointer<AVFrame>!,
  destination: UnsafeMutablePointer<AVFrame>!,
) throws(FFError) {
  let result = sws_scale_frame(context, destination, source)

  guard result >= 0 else {
    throw FFError(code: FFError.Code(rawValue: result))
  }
}

public func configureResampler(
  _ context: OpaquePointer!,
  source: UnsafePointer<AVFrame>!,
  destination: UnsafePointer<AVFrame>!,
) throws(FFError) {
  let status = swr_config_frame(context, destination, source)

  guard status == FFSTATUS_OK else {
    throw FFError(code: FFError.Code(rawValue: status))
  }
}

public func resampleFrame(
  _ context: OpaquePointer!,
  source: UnsafePointer<AVFrame>!,
  destination: UnsafeMutablePointer<AVFrame>!,
) throws(FFError) {
  let status = swr_convert_frame(context, destination, source)

  guard status == FFSTATUS_OK else {
    throw FFError(code: FFError.Code(rawValue: status))
  }
}

public func resampleFrame(
  _ context: OpaquePointer!,
  source: UnsafePointer<AVFrame>!,
  destination: UnsafeMutablePointer<AVFrame>!,
  channelLayout: AVChannelLayout,
  sampleRate: Int32,
  sampleFormat: Int32,
) throws(FFError) {
  destination.pointee.ch_layout = channelLayout
  destination.pointee.sample_rate = sampleRate
  destination.pointee.format = sampleFormat

  try resampleFrame(context, source: source, destination: destination)
}

public func packetFromData(
  _ packet: UnsafeMutablePointer<AVPacket>!,
  data: UnsafeMutablePointer<UInt8>!,
  size: Int32,
) throws(FFError) {
  let status = av_packet_from_data(packet, data, size)

  guard status == FFSTATUS_OK else {
    throw FFError(code: FFError.Code(rawValue: status))
  }
}

extension AVChannelLayout {
  public var `default`: Self {
    var channelLayout = Self()
    av_channel_layout_default(&channelLayout, self.nb_channels)

    return channelLayout
  }
}

public struct StreamDisposition: OptionSet, Sendable {
  public var rawValue: Int32

  public static let attachedPicture = Self(rawValue: AV_DISPOSITION_ATTACHED_PIC)

  public init(rawValue: Int32) {
    self.rawValue = rawValue
  }
}

extension AVStream {
  public var streamDisposition: StreamDisposition {
    StreamDisposition(rawValue: self.disposition)
  }
}

extension AVFrame {
  static public let unknownFormat = -1

  public var pixelFormat: AVPixelFormat? {
    let format = self.format

    guard format != Self.unknownFormat else {
      return nil
    }

    return AVPixelFormat(rawValue: format)
  }

  public var sampleFormat: AVSampleFormat? {
    let format = self.format

    guard format != Self.unknownFormat else {
      return nil
    }

    return AVSampleFormat(rawValue: format)
  }
}

public struct FFError: Error {
  public let code: Code

  public init(code: Code) {
    self.code = code
  }

  public struct Code: Sendable, RawRepresentable {
    public var rawValue: Int32

    public static let outputChanged = Self(rawValue: AVERROR_OUTPUT_CHANGED) // -1668179714
    public static let endOfFile = Self(rawValue: FFSTATUS_EOF) // -541478725
    public static let invalidData = Self(rawValue: FFSTATUS_INVALIDDATA) // -1094995529
    public static let streamNotFound = Self(rawValue: FFSTATUS_STREAM_NOT_FOUND) // -1381258232
    public static let isDirectory = Self(rawValue: FFSTATUS_EISDIR) // -21
    public static let resourceTemporarilyUnavailable = Self(rawValue: FFSTATUS_EAGAIN) // -35

    public init(rawValue: Int32) {
      self.rawValue = rawValue
    }
  }
}

// These wrappers are flawed in that the pointer can be used past the class's lifetime, causing the class to free the
// underlying type while in use.

public class FFFormatContext {
  public var context: UnsafeMutablePointer<AVFormatContext>!

  public init(context: UnsafeMutablePointer<AVFormatContext>!) {
    self.context = context
  }

  public convenience init() {
    guard let context = avformat_alloc_context() else {
      fatalError()
    }

    self.init(context: context)
  }

  deinit {
    avformat_free_context(context)
  }
}

public class FFCodecContext {
  public var context: UnsafeMutablePointer<AVCodecContext>!

  public init(context: UnsafeMutablePointer<AVCodecContext>!) {
    self.context = context
  }

  public convenience init(codec: UnsafePointer<AVCodec>!) {
    guard let context = avcodec_alloc_context3(codec) else {
      fatalError()
    }

    self.init(context: context)
  }

  deinit {
    avcodec_free_context(&context)
  }
}

public class FFPacket {
  public var packet: UnsafeMutablePointer<AVPacket>!

  public init(packet: UnsafeMutablePointer<AVPacket>!) {
    self.packet = packet
  }

  public convenience init() {
    guard let packet = av_packet_alloc() else {
      fatalError()
    }

    self.init(packet: packet)
  }

  deinit {
    av_packet_free(&packet)
  }
}

public class FFFrame {
  public var frame: UnsafeMutablePointer<AVFrame>!

  public init(frame: UnsafeMutablePointer<AVFrame>!) {
    self.frame = frame
  }

  public convenience init() {
    guard let frame = av_frame_alloc() else {
      fatalError()
    }

    self.init(frame: frame)
  }

  deinit {
    av_frame_free(&frame)
  }
}

extension AVSampleFormat {
  public var isInterleaved: Bool {
    av_sample_fmt_is_planar(self) == 0
  }
}

public class FFScaleContext {
  public var context: UnsafeMutablePointer<SwsContext>!

  public init(context: UnsafeMutablePointer<SwsContext>!) {
    self.context = context
  }

  public convenience init() {
    self.init(context: sws_alloc_context())
  }

  deinit {
    sws_free_context(&context)
  }
}

public class FFResampleContext {
  public var context: OpaquePointer!

  public init(context: OpaquePointer!) {
    self.context = context
  }

  public convenience init() {
    guard let context = swr_alloc() else {
      fatalError()
    }

    self.init(context: context)
  }

  deinit {
    swr_free(&context)
  }
}

extension CFFmpeg.AVMediaType {
  public static let audio = AVMEDIA_TYPE_AUDIO
  public static let video = AVMEDIA_TYPE_VIDEO
}

extension AVCodecID {
  public static let png = AV_CODEC_ID_PNG
  public static let mjpeg = AV_CODEC_ID_MJPEG
}

// I'm not sure if libavutil's AVDictionary keys are unique.
public struct FFDictionaryIterator: IteratorProtocol {
  private let dict: OpaquePointer!
  private var tag: UnsafePointer<AVDictionaryEntry>!

  public mutating func next() -> UnsafePointer<AVDictionaryEntry>? {
    let tag = av_dict_iterate(dict, tag)
    self.tag = tag

    return tag
  }
}

extension FFDictionaryIterator {
  public init(_ dict: OpaquePointer!, tag: UnsafePointer<AVDictionaryEntry>! = nil) {
    self.init(dict: dict, tag: tag)
  }
}

extension FFDictionaryIterator: Sequence {}
