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

// MARK: - Thin

public func streams(_ context: UnsafePointer<AVFormatContext>!) -> UnsafeBufferPointer<UnsafeMutablePointer<AVStream>?> {
  UnsafeBufferPointer(start: context.pointee.streams, count: Int(context.pointee.nb_streams))
}

public func duration(_ duration: Int64) -> Int64? {
  guard duration != FFAV_NOPTS_VALUE else {
    return nil
  }

  return duration
}

extension AVChannelLayout {
  public var `default`: Self {
    var channelLayout = Self()
    av_channel_layout_default(&channelLayout, self.nb_channels)

    return channelLayout
  }
}

// These wrappers are flawed in that the pointer can be used past the class's lifetime, causing the class to free the
// underlying type while in use.

// TODO: Remove.
//
// We need to resolve AudioPlayerItem using Copyable.
public class FFCodecContext {
  public var context: UnsafeMutablePointer<AVCodecContext>!

  public init(context: UnsafeMutablePointer<AVCodecContext>!) {
    self.context = context
  }

  public convenience init(codec: UnsafePointer<AVCodec>!) {
    guard let context = AVCodecContext.allocate(codec: codec) else {
      fatalError()
    }

    self.init(context: context)
  }

  deinit {
    AVCodecContext.free(&context)
  }
}

extension CFFmpeg.AVMediaType {
  public static let audio = AVMEDIA_TYPE_AUDIO
  public static let video = AVMEDIA_TYPE_VIDEO
}

extension AVCodecID {
  public static let png = AV_CODEC_ID_PNG
  public static let mjpeg = AV_CODEC_ID_MJPEG // Motion JPEG
}

// MARK: - Thick

/// Calculates the duration of a stream.
/// - Parameters:
///   - stream: The stream.
///   - formatContext: The stream's format context.
/// - Returns: The duration in seconds.
public func duration(stream: UnsafePointer<AVStream>!, formatContext: UnsafePointer<AVFormatContext>!) -> Double? {
  // Some formats (like Matroska) have the stream duration set to AV_NOPTS_VALUE, while exposing the real value in the
  // format context.

  if let duration = duration(stream.pointee.duration) {
    return Double(duration) * av_q2d(stream.pointee.time_base)
  }

  if let duration = duration(formatContext.pointee.duration) {
    return Double(duration * Int64(AV_TIME_BASE))
  }

  return nil
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
