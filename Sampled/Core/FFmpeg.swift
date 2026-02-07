//
//  FFmpeg.swift
//  Sampled
//
//  Created by Kyle Erhabor on 2/5/26.
//

import CFFmpeg
import CoreFFmpeg
import SampledCore
import Foundation
import OSLog

extension Logger {
  static let ffmpeg = Self(subsystem: Bundle.appID, category: "FFmpeg")
}

// MARK: - libavutil

let FFSTATUS_OK: Int32 = 0
let FFSTATUS_EOF = FFAVERROR_EOF
let FFSTATUS_INVALIDDATA = FFAVERROR_INVALIDDATA
let FFSTATUS_STREAM_NOT_FOUND = FFAVERROR_STREAM_NOT_FOUND
let FFSTATUS_ENOMEM = FFAVERROR_ENOMEM
let FFSTATUS_EISDIR = FFAVERROR_EISDIR
let FFSTATUS_EAGAIN = FFAVERROR_EAGAIN

func allocate(bytes: Int) -> UnsafeMutableRawPointer {
  guard let pointer = CFFmpeg.allocate(size: bytes) else {
    fatalError("Could not allocate memory for \(bytes) bytes")
  }

  return pointer
}

func deallocate(_ pointer: consuming UnsafeMutableRawPointer?) {
  freeAllocation(&pointer)
}

struct FFError: Error {
  let code: Code

  struct Code: Sendable, RawRepresentable {
    var rawValue: Int32

    static let outputChanged = Self(rawValue: AVERROR_OUTPUT_CHANGED) // -1668179714
    static let endOfFile = Self(rawValue: FFSTATUS_EOF) // -541478725
    static let invalidData = Self(rawValue: FFSTATUS_INVALIDDATA) // -1094995529
    static let streamNotFound = Self(rawValue: FFSTATUS_STREAM_NOT_FOUND) // -1381258232
    static let isDirectory = Self(rawValue: FFSTATUS_EISDIR) // -21
    static let resourceTemporarilyUnavailable = Self(rawValue: FFSTATUS_EAGAIN) // -35

    public init(rawValue: Int32) {
      self.rawValue = rawValue
    }
  }
}

struct Allocation: ~Copyable {
  private let bytes: UnsafeMutableRawPointer

  consuming func initialize<T>(span: Span<T>) -> UnsafeMutablePointer<T>? {
    let pointer = span.withUnsafeBufferPointer { buffer -> UnsafeMutablePointer<T>? in
      guard let baseAddress = buffer.baseAddress else {
        return nil
      }

      let pointer = self.bytes.initializeMemory(as: T.self, from: baseAddress, count: buffer.count)

      return pointer
    }

    guard let pointer else {
      _ = consume self

      return nil
    }

    discard self

    return pointer
  }

  deinit {
    deallocate(self.bytes)
  }
}

extension Allocation {
  init(bytes: Int) {
    self.init(bytes: allocate(bytes: bytes))
  }
}

struct LogLevel: RawRepresentable {
  let rawValue: Int32

  static let trace = Self(rawValue: AV_LOG_TRACE)
  static let debug = Self(rawValue: AV_LOG_DEBUG)
  static let verbose = Self(rawValue: AV_LOG_VERBOSE)
  static let info = Self(rawValue: AV_LOG_INFO)
  static let warning = Self(rawValue: AV_LOG_WARNING)
  static let error = Self(rawValue: AV_LOG_ERROR)
  static let fatal = Self(rawValue: AV_LOG_FATAL)
  static let panic = Self(rawValue: AV_LOG_PANIC)

  init(rawValue: Int32) {
    self.rawValue = rawValue
  }
}

extension LogLevel: Equatable {}

extension AVPixelFormat {
  init(_ format: PixelFormat) {
    self.init(rawValue: format.rawValue)
  }
}

struct PixelFormat: RawRepresentable {
  let rawValue: Int32

  static let rgba = Self(rawValue: AV_PIX_FMT_RGBA.rawValue)

  init(rawValue: Int32) {
    self.rawValue = rawValue
  }
}

extension AVSampleFormat {
  static let unknownBytesPerSample: Int32 = 0

  init(_ format: SampleFormat) {
    self.init(rawValue: format.rawValue)
  }
}

// This should really be an enum, but I don't want to hardcode the raw values.
struct SampleFormat: RawRepresentable {
  let rawValue: Int32
  var isPlanar: Bool {
    AVSampleFormat.isPlanar(AVSampleFormat(self)) == 1
  }

  var bytesPerSample: Int32? {
    let bytesPerSample = AVSampleFormat.bytesPerSample(AVSampleFormat(self))

    guard bytesPerSample != AVSampleFormat.unknownBytesPerSample else {
      return nil
    }

    return bytesPerSample
  }

  static let floatPlanar = Self(rawValue: AV_SAMPLE_FMT_FLTP.rawValue)

  init(rawValue: Int32) {
    self.rawValue = rawValue
  }
}

// MARK: - libavformat

func allocateFormatContext() -> UnsafeMutablePointer<AVFormatContext> {
  guard let context = AVFormatContext.allocate() else {
    fatalError("Could not allocate format context")
  }

  return context
}

func deallocateFormatContext(_ context: UnsafeMutablePointer<AVFormatContext>?) {
  AVFormatContext.free(context)
}

func openInput(
  _ context: consuming UnsafeMutablePointer<AVFormatContext>?,
  at url: UnsafePointer<CChar>,
) throws(FFError) -> UnsafeMutablePointer<AVFormatContext> {
  let status = AVFormatContext.openInput(&context, url: url, format: nil, options: nil)

  guard status == FFSTATUS_OK else {
    throw FFError(code: FFError.Code(rawValue: status))
  }

  return context!
}

func closeInput(_ context: consuming UnsafeMutablePointer<AVFormatContext>?) {
  AVFormatContext.closeInput(&context)
}

func findStreamInfo(_ context: UnsafeMutablePointer<AVFormatContext>) throws(FFError) {
  let result = AVFormatContext.findStreamInfo(context, options: nil)

  guard result >= 0 else {
    throw FFError(code: FFError.Code(rawValue: result))
  }
}

func findBestStream(
  _ context: UnsafeMutablePointer<AVFormatContext>,
  type: CFFmpeg.AVMediaType,
  decoder: inout UnsafePointer<AVCodec>?,
) throws(FFError) -> Int32 {
  let result = AVFormatContext.findBestStream(
    context,
    type: type,
    wantedStream: -1,
    relatedStream: -1,
    decoder: &decoder,
    flags: 0,
  )

  guard result >= 0 else {
    throw FFError(code: FFError.Code(rawValue: result))
  }

  return result
}

func readFrame(
  _ context: UnsafeMutablePointer<AVFormatContext>,
  packet: UnsafeMutablePointer<AVPacket>,
) throws(FFError) {
  let status = AVFormatContext.readFrame(context, packet: packet)

  guard status == FFSTATUS_OK else {
    throw FFError(code: FFError.Code(rawValue: status))
  }
}

extension FormatContext {
  init() {
    self.init(context: allocateFormatContext())
  }
}

struct Disposition: OptionSet {
  var rawValue: Int32

  static let attachedPicture = Self(rawValue: AV_DISPOSITION_ATTACHED_PIC)

  init(rawValue: Int32) {
    self.rawValue = rawValue
  }
}

extension AVStream {
  var streamDisposition: Disposition {
    Disposition(rawValue: self.disposition)
  }
}

// MARK: - libavcodec

func allocateCodecContext(codec: UnsafePointer<AVCodec>?) -> UnsafeMutablePointer<AVCodecContext> {
  guard let context = AVCodecContext.allocate(codec: codec) else {
    let message: String

    if let codec {
      message = "Could not allocate codec context with codec '\(codec.pointee.name!)'"
    } else {
      message = "Could not allocate codec context"
    }

    fatalError(message)
  }

  return context
}

func deallocateCodecContext(_ context: consuming UnsafeMutablePointer<AVCodecContext>?) {
  AVCodecContext.free(&context)
}

func allocatePacket() -> UnsafeMutablePointer<AVPacket> {
  guard let packet = AVPacket.allocate() else {
    fatalError("Could not allocate packet")
  }

  return packet
}

func deallocatePacket(_ packet: consuming UnsafeMutablePointer<AVPacket>?) {
  AVPacket.free(&packet)
}

func packetFromData(
  _ packet: UnsafeMutablePointer<AVPacket>,
  data: UnsafeMutablePointer<UInt8>,
  size: Int32,
) throws(FFError) {
  let status = AVPacket.fromData(packet, data: data, size: size)

  guard status == FFSTATUS_OK else {
    throw FFError(code: FFError.Code(rawValue: status))
  }
}

func allocateFrame() -> UnsafeMutablePointer<AVFrame> {
  guard let frame = AVFrame.allocate() else {
    fatalError("Could not allocate frame")
  }

  return frame
}

func deallocateFrame(_ frame: consuming UnsafeMutablePointer<AVFrame>?) {
  AVFrame.free(&frame)
}

func copyCodecParameters(
  _ context: UnsafeMutablePointer<AVCodecContext>,
  parameters: UnsafePointer<AVCodecParameters>,
) throws(FFError) {
  let result = AVCodecContext.copyParameters(context, parameters: parameters)

  guard result >= 0 else {
    throw FFError(code: FFError.Code(rawValue: result))
  }
}

func openCodec(
  _ context: UnsafeMutablePointer<AVCodecContext>,
  codec: UnsafePointer<AVCodec>?,
) throws(FFError) {
  let status = AVCodecContext.open(context, codec: codec, options: nil)

  guard status == FFSTATUS_OK else {
    throw FFError(code: FFError.Code(rawValue: status))
  }
}

func sendPacket(
  _ context: UnsafeMutablePointer<AVCodecContext>,
  packet: UnsafePointer<AVPacket>?,
) throws(FFError) {
  let status = AVCodecContext.sendPacket(context, packet: packet)

  switch status {
    case FFSTATUS_OK:
      break
    case FFSTATUS_ENOMEM:
      fatalError("Could not send packet to decoder")
    default:
      throw FFError(code: FFError.Code(rawValue: status))
  }
}

func receiveFrame(
  _ context: UnsafeMutablePointer<AVCodecContext>,
  frame: UnsafeMutablePointer<AVFrame>,
) throws(FFError) {
  let status = AVCodecContext.receiveFrame(context, frame: frame)

  guard status == FFSTATUS_OK else {
    throw FFError(code: FFError.Code(rawValue: status))
  }
}

struct CodecContext: ~Copyable {
  let context: UnsafeMutablePointer<AVCodecContext>

  deinit {
    deallocateCodecContext(self.context)
  }
}

extension CodecContext {
  init(codec: UnsafePointer<AVCodec>?) {
    self.init(context: allocateCodecContext(codec: codec))
  }
}

struct Packet: ~Copyable {
  let packet: UnsafeMutablePointer<AVPacket>

  deinit {
    deallocatePacket(self.packet)
  }
}

extension Packet {
  init() {
    self.init(packet: allocatePacket())
  }
}

struct Frame: ~Copyable {
  let frame: UnsafeMutablePointer<AVFrame>

  deinit {
    deallocateFrame(self.frame)
  }
}

extension Frame {
  init() {
    self.init(frame: allocateFrame())
  }
}

extension AVFrame {
  var sampleFormat: SampleFormat? {
    guard self.format != AV_SAMPLE_FMT_NONE.rawValue else {
      return nil
    }

    let format = SampleFormat(rawValue: self.format)

    return format
  }
}

// MARK: - libswscale

func allocateScaleContext() -> UnsafeMutablePointer<SwsContext> {
  guard let context = SwsContext.allocate() else {
    fatalError("Could not allocate scale context")
  }

  return context
}

func deallocateScaleContext(_ context: consuming UnsafeMutablePointer<SwsContext>?) {
  SwsContext.free(&context)
}

func scaleFrame(
  _ context: UnsafeMutablePointer<SwsContext>,
  source: UnsafePointer<AVFrame>,
  destination: UnsafeMutablePointer<AVFrame>,
) throws(FFError) {
  let result = SwsContext.scaleFrame(context, destination: destination, source: source)

  guard result >= 0 else {
    throw FFError(code: FFError.Code(rawValue: result))
  }
}

struct ScaleContext: ~Copyable {
  let context: UnsafeMutablePointer<SwsContext>

  deinit {
    deallocateScaleContext(self.context)
  }
}

extension ScaleContext {
  init() {
    self.init(context: allocateScaleContext())
  }
}

// MARK: - libswresample

func allocateResampleContext() -> OpaquePointer {
  guard let context = CFFmpeg.allocateResampleContext() else {
    fatalError("Could not allocate resample context")
  }

  return context
}

func deallocateResampleContext(_ context: consuming OpaquePointer?) {
  freeResampleContext(&context)
}

func configureResampleContextFrame(
  _ context: OpaquePointer,
  source: UnsafePointer<AVFrame>,
  destination: UnsafePointer<AVFrame>,
) throws(FFError) {
  let status = configureResampleContextFrame(context, destination: destination, source: source)

  guard status == FFSTATUS_OK else {
    throw FFError(code: FFError.Code(rawValue: status))
  }
}

func convertResampleContextFrame(
  _ context: OpaquePointer,
  source: UnsafePointer<AVFrame>?,
  destination: UnsafeMutablePointer<AVFrame>?,
) throws(FFError) {
  let status = convertResampleContextFrame(context, destination: destination, source: source)

  guard status == FFSTATUS_OK else {
    throw FFError(code: FFError.Code(rawValue: status))
  }
}

struct ResampleContext: ~Copyable {
  let context: OpaquePointer

  deinit {
    deallocateResampleContext(self.context)
  }
}

extension ResampleContext {
  init() {
    self.init(context: allocateResampleContext())
  }
}

// MARK: -

struct CodecID: RawRepresentable {
  let rawValue: UInt32
  var name: UnsafePointer<CChar> {
    codecName(id: AVCodecID(self))
  }

  static let png = Self(AV_CODEC_ID_PNG)
  static let mjpeg = Self(AV_CODEC_ID_MJPEG) // Motion JPEG
}

extension CodecID {
  init(_ id: AVCodecID) {
    self.init(rawValue: id.rawValue)
  }
}

extension AVCodecID {
  init(_ id: CodecID) {
    self.init(rawValue: id.rawValue)
  }
}

extension CodecID: Equatable {}

struct FormatContext: ~Copyable {
  let context: UnsafeMutablePointer<AVFormatContext>

  consuming func openInput(at url: UnsafePointer<CChar>) throws(FFError) -> Self {
    do {
      _ = try Sampled.openInput(self.context, at: url)
    } catch {
      discard self

      throw error
    }

    return self
  }

  consuming func closeInput() {
    Sampled.closeInput(self.context)

    discard self
  }

  consuming func openingInput<T>(
    at url: UnsafePointer<CChar>,
    _ body: (borrowing Self) throws(FFError) -> T,
  ) throws(FFError) -> T where T: ~Copyable {
    let this = try openInput(at: url)
    // For some reason, we can't use defer here.
    let result: T

    do {
      result = try body(this)
    } catch {
      this.closeInput()

      throw error
    }

    this.closeInput()

    return result
  }

  deinit {
    deallocateFormatContext(self.context)
  }
}
