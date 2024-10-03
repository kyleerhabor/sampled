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

public let AVSTATUS_OK: Int32 = 0
public let AVSTATUS_EOF = AVERR_EOF
public let AVSTATUS_DECODER_NOT_FOUND = AVERR_DECODER_NOT_FOUND
public let AVSTATUS_STREAM_NOT_FOUND = AVERR_STREAM_NOT_FOUND
public let AVSTATUS_ENOMEM = AVERR_ENOMEM
public let AVSTATUS_EAGAIN = AVERR_EAGAIN

public struct FFError: Error {
  public let code: Code

  public struct Code: RawRepresentable {
    public var rawValue: Int32

    public static let endOfFile = Self(rawValue: AVSTATUS_EOF)
    public static let resourceTemporarilyUnavailable = Self(rawValue: AVSTATUS_EAGAIN)
    public static let decoderNotFound = Self(rawValue: AVSTATUS_DECODER_NOT_FOUND)
    public static let streamNotFound = Self(rawValue: AVSTATUS_STREAM_NOT_FOUND)

    public init(rawValue: Int32) {
      self.rawValue = rawValue
    }
  }
}

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

  public func open(at url: UnsafePointer<CChar>!) throws {
    let status = avformat_open_input(&context, url, nil, nil)

    guard status == AVSTATUS_OK else {
      throw FFError(code: FFError.Code(rawValue: status))
    }
  }

  public func findStreamInfo() throws {
    let status = avformat_find_stream_info(context, nil)

    guard status == AVSTATUS_OK else {
      throw FFError(code: FFError.Code(rawValue: status))
    }
  }

  public func findBestStream(
    type: CFFmpeg.AVMediaType,
    decoder: UnsafeMutablePointer<UnsafePointer<AVCodec>?>!
  ) throws -> Int32 {
    let result = av_find_best_stream(context, type, -1, -1, decoder, 0)

    guard result >= 0 else {
      throw FFError(code: FFError.Code(rawValue: result))
    }

    return result
  }

  public func readFrame(into packet: UnsafeMutablePointer<AVPacket>!) throws {
    let status = av_read_frame(context, packet)

    guard status == AVSTATUS_OK else {
      throw FFError(code: FFError.Code(rawValue: status))
    }
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

  public func copyCodecParameters(_ params: UnsafePointer<AVCodecParameters>!) throws {
    let result = avcodec_parameters_to_context(context, params)

    guard result >= 0 else {
      throw FFError(code: FFError.Code(rawValue: result))
    }
  }

  public func open(decoder: UnsafePointer<AVCodec>!) throws {
    let openStatus = avcodec_open2(context, decoder, nil)

    guard openStatus == AVSTATUS_OK else {
      throw FFError(code: FFError.Code(rawValue: openStatus))
    }
  }

  public func sendPacket(_ packet: UnsafePointer<AVPacket>!) throws {
    let status = avcodec_send_packet(context, packet)

    switch status {
      case AVSTATUS_OK: break
      case AVSTATUS_ENOMEM:
        fatalError()
      default:
        throw FFError(code: FFError.Code(rawValue: status))
    }
  }

  public func receiveFrame(_ frame: UnsafeMutablePointer<AVFrame>!) throws {
    let status = avcodec_receive_frame(context, frame)

    guard status == AVSTATUS_OK else {
      throw FFError(code: FFError.Code(rawValue: status))
    }
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

  public static let formatUnknown = -1

  public var sampleFormat: AVSampleFormat? {
    let format = frame.pointee.format

    guard format != Self.formatUnknown else {
      return nil
    }

    return AVSampleFormat(rawValue: format)
  }

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
  public var isPlanar: Bool {
    av_sample_fmt_is_planar(self) == 1
  }

  public init?(settings: [String: Any]) {
    // As of May 29th, 2024, Apple's documentation claims AVLinearPCMBitDepthKey can be 8, 16, 24, or 32; however, this
    // is not true, given AVAudioCommonFormat.pcmFormatFloat64 has a bit depth of 64.

    // Do we need to check AVLinearPCMIsBigEndianKey?
    guard let bitDepth = settings[AVLinearPCMBitDepthKey] as? Int,
          let isFloat = settings[AVLinearPCMIsFloatKey] as? Bool,
          let isNonInterleaved = settings[AVLinearPCMIsNonInterleaved] as? Bool else {
      return nil
    }

    switch (bitDepth, isFloat, isNonInterleaved) {
      case (8, false, false): self = AV_SAMPLE_FMT_U8
      case (8, false, true): self = AV_SAMPLE_FMT_U8P
      case (16, false, false): self = AV_SAMPLE_FMT_S16
      case (16, false, true): self = AV_SAMPLE_FMT_S16P
      case (32, false, false): self = AV_SAMPLE_FMT_S32
      case (32, false, true): self = AV_SAMPLE_FMT_S32P
      case (32, true, false): self = AV_SAMPLE_FMT_FLT
      case (32, true, true): self = AV_SAMPLE_FMT_FLTP
      case (64, false, false): self = AV_SAMPLE_FMT_S64
      case (64, false, true): self = AV_SAMPLE_FMT_S64P
      case (64, true, false): self = AV_SAMPLE_FMT_DBL
      case (64, true, true): self = AV_SAMPLE_FMT_DBLP
      default: return nil
    }
  }
}

extension AVAudioCommonFormat {
  public init?(_ sampleFormat: AVSampleFormat) {
    switch sampleFormat {
      case AV_SAMPLE_FMT_S16, AV_SAMPLE_FMT_S16P: self = .pcmFormatInt16
      case AV_SAMPLE_FMT_S32, AV_SAMPLE_FMT_S32P: self = .pcmFormatInt32
      case AV_SAMPLE_FMT_FLT, AV_SAMPLE_FMT_FLTP: self = .pcmFormatFloat32
      case AV_SAMPLE_FMT_DBL, AV_SAMPLE_FMT_DBLP: self = .pcmFormatFloat64
      case AV_SAMPLE_FMT_U8, AV_SAMPLE_FMT_U8P,
           AV_SAMPLE_FMT_S64, AV_SAMPLE_FMT_S64P: self = .otherFormat
      default: return nil
    }
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

  public func configure(
    inputChannelLayout: UnsafePointer<AVChannelLayout>!,
    inputSampleFormat: AVSampleFormat,
    inputSampleRate: Int32,
    outputChannelLayout: UnsafePointer<AVChannelLayout>!,
    outputSampleFormat: AVSampleFormat,
    outputSampleRate: Int32
  ) throws {
    let status = swr_alloc_set_opts2(
      &context,
      outputChannelLayout,
      outputSampleFormat,
      outputSampleRate,
      inputChannelLayout,
      inputSampleFormat,
      inputSampleRate,
      0, // ?
      nil
    )

    guard status == AVSTATUS_OK else {
      throw FFError(code: FFError.Code(rawValue: status))
    }
  }

  public func initialize() throws {
    let status = swr_init(context)

    guard status == AVSTATUS_OK else {
      throw FFError(code: FFError.Code(rawValue: status))
    }
  }

  public func convertFrame(from source: UnsafePointer<AVFrame>!, to destination: UnsafeMutablePointer<AVFrame>!) throws {
    let status = swr_convert_frame(context, destination, source)

    guard status == AVSTATUS_OK else {
      throw FFError(code: FFError.Code(rawValue: status))
    }
  }
}

extension AVChannelOrder {
  public static let native = AV_CHANNEL_ORDER_NATIVE
}

extension CFFmpeg.AVMediaType {
  public static let audio = AVMEDIA_TYPE_AUDIO
}
