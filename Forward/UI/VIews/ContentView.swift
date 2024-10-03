//
//  ContentView.swift
//  Forward
//
//  Created by Kyle Erhabor on 10/3/24.
//

import ForwardFFmpeg
import CFFmpeg
import AVFoundation
import Algorithms
import OSLog
import SwiftUI

struct Track {
  let url: URL

  let title: String
  let artist: String
  let album: String
  let cover: NSImage
}

extension Track: Identifiable {
  var id: URL { url }
}

struct AVDictionaryIterator: IteratorProtocol {
  private let dict: OpaquePointer!
  private var tag: UnsafePointer<AVDictionaryEntry>!

  mutating func next() -> UnsafePointer<AVDictionaryEntry>? {
    let tag = av_dict_iterate(dict, tag)

    self.tag = tag

    return tag
  }

  init(_ dict: OpaquePointer!) {
    self.dict = dict
  }
}

extension AVDictionaryIterator: Sequence {}

enum DecoderError: Error {
  case placeholder
}

let audioEngine = AVAudioEngine()

struct ContentView: View {
  @State private var isFileImporterPresented = false
  @State private var isCoverPresented = false
  @State private var tracks = [Track]()
  @State private var track: Track?

  var body: some View {
    Table(tracks) {
      TableColumn(Text(verbatim: "Title"), value: \.title)
      TableColumn(Text(verbatim: "Artist"), value: \.artist)
      TableColumn(Text(verbatim: "Album"), value: \.album)
    }
    .contextMenu { urls in
      Button {
        NSWorkspace.shared.activateFileViewerSelecting(Array(urls))
      } label: {
        Text(verbatim: "Show in Finder")
      }

      Divider()

      Button {
        track = tracks.first { urls.contains($0.url) }
        isCoverPresented = true
      } label: {
        Text(verbatim: "Show Information")
      }
    }
    //    primaryAction: { urls in
    //      guard let track = tracks.first(where: { urls.contains($0.id) }) else {
    //        Logger.main.error("No track.")
    //
    //        return
    //      }
    //
    //      let url = track.url
    //      let path = url.pathString
    //
    //      let formatContext = FFFormatContext()
    //
    //      url.accessingSecurityScopedResource {
    //        do {
    //          try formatContext.open(at: path)
    //        } catch {
    //          Logger.main.error("\(error)")
    //
    //          return
    //        }
    //
    //        defer {
    //          avformat_close_input(&formatContext.context)
    //        }
    //
    //        do {
    //          try formatContext.findStreamInfo()
    //        } catch {
    //          Logger.main.error("\(error)")
    //
    //          return
    //        }
    //
    //        var decoder: UnsafePointer<AVCodec>! = nil
    //        let streami: Int32
    //
    //        do {
    //          streami = try formatContext.findBestStream(type: .audio, decoder: &decoder)
    //        } catch {
    //          Logger.main.error("\(error)")
    //
    //          return
    //        }
    //
    //        let stream = formatContext.context.pointee.streams[Int(streami)]!
    //        let codecContext = FFCodecContext(codec: decoder)
    //
    //        do {
    //          try codecContext.copyCodecParameters(stream.pointee.codecpar)
    //          try codecContext.open(decoder: decoder)
    //        } catch {
    //          Logger.main.error("\(error)")
    //
    //          return
    //        }
    //
    //        guard codecContext.context.pointee.ch_layout.order == .native else {
    //          return
    //        }
    //
    //        var layout = AudioChannelLayout()
    //        layout.mChannelBitmap = AudioChannelBitmap(rawValue: UInt32(codecContext.context.pointee.ch_layout.u.mask))
    //        layout.mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelBitmap
    //
    //        let processingFormat = AVAudioFormat(
    //          standardFormatWithSampleRate: Double(codecContext.context.pointee.sample_rate),
    //          channelLayout: AVAudioChannelLayout(layout: &layout)
    //        )
    //
    //        guard let processingSampleFormat = AVSampleFormat(settings: processingFormat.settings) else {
    //          return
    //        }
    //
    //        let packet = FFPacket()
    //        let frame = FFFrame()
    //        let reframe = FFFrame()
    //        let resampleContext = FFResampleContext()
    //        var buffers = Array(
    //          repeating: Data(),
    //          count: processingFormat.isInterleaved ? 1 : Int(processingFormat.channelCount)
    //        )
    //
    //        while true {
    //          do {
    //            try formatContext.readFrame(into: packet.packet)
    //          } catch let err as FFError where err.code == .endOfFile {
    //            // We could do our work here, but that would be annoying to follow.
    //            break
    //          } catch {
    //            Logger.main.error("\(error)")
    //
    //            return
    //          }
    //
    //          defer {
    //            av_packet_unref(packet.packet)
    //          }
    //
    //          guard packet.packet.pointee.stream_index == streami else {
    //            continue
    //          }
    //
    //          do {
    //            try codecContext.sendPacket(packet.packet)
    //          } catch {
    //            Logger.main.error("\(error)")
    //
    //            return
    //          }
    //
    //          do {
    //            while true {
    //              try codecContext.receiveFrame(frame.frame)
    //
    //              guard let sampleFormat = frame.sampleFormat else {
    //                // This should (probably) not happen.
    //                return
    //              }
    //
    //              let channelLayout = frame.frame.pointer(to: \.ch_layout)
    //
    //              do {
    //                try resampleContext.configure(
    //                  inputChannelLayout: channelLayout,
    //                  inputSampleFormat: sampleFormat,
    //                  inputSampleRate: frame.frame.pointee.sample_rate,
    //                  outputChannelLayout: channelLayout,
    //                  outputSampleFormat: processingSampleFormat,
    //                  outputSampleRate: Int32(processingFormat.sampleRate)
    //                )
    //
    //                try resampleContext.initialize()
    //              } catch {
    //                Logger.main.error("\(error)")
    //
    //                return
    //              }
    //
    //              reframe.frame.pointee.ch_layout = frame.frame.pointee.ch_layout
    //              reframe.frame.pointee.sample_rate = Int32(processingFormat.sampleRate)
    //              reframe.frame.pointee.format = processingSampleFormat.rawValue
    //
    //              do {
    //                try resampleContext.convertFrame(from: frame.frame, to: reframe.frame)
    //              } catch {
    //                Logger.main.error("\(error)")
    //
    //                return
    //              }
    //
    //              guard let sampleFormat = reframe.sampleFormat else {
    //                return
    //              }
    //
    //              let linesize = Int(reframe.frame.pointee.linesize.0)
    //              let indicies = 0..<(sampleFormat.isPlanar ? Int(reframe.frame.pointee.ch_layout.nb_channels) : 1)
    //
    //              indicies.forEach { index in
    //                buffers[index].append(reframe.frame.pointee.extended_data[index]!, count: linesize)
    //              }
    //            }
    //          } catch let err as FFError where err.code == .resourceTemporarilyUnavailable {
    //            // Fallthrough
    //          } catch {
    //            Logger.main.error("\(error)")
    //
    //            return
    //          }
    //        }
    //
    //        do {
    //          try codecContext.sendPacket(nil)
    //        } catch {
    //          Logger.main.error("\(error)")
    //
    //          return
    //        }
    //
    //        do {
    //          while true {
    //            try codecContext.receiveFrame(frame.frame)
    //
    //            guard let sampleFormat = frame.sampleFormat else {
    //              // This should (probably) not happen.
    //              return
    //            }
    //
    //            let channelLayout = frame.frame.pointer(to: \.ch_layout)
    //
    //            do {
    //              try resampleContext.configure(
    //                inputChannelLayout: channelLayout,
    //                inputSampleFormat: sampleFormat,
    //                inputSampleRate: frame.frame.pointee.sample_rate,
    //                outputChannelLayout: channelLayout,
    //                outputSampleFormat: processingSampleFormat,
    //                outputSampleRate: Int32(processingFormat.sampleRate)
    //              )
    //
    //              try resampleContext.initialize()
    //            } catch {
    //              Logger.main.error("\(error)")
    //
    //              return
    //            }
    //
    //            reframe.frame.pointee.ch_layout = frame.frame.pointee.ch_layout
    //            reframe.frame.pointee.sample_rate = Int32(processingFormat.sampleRate)
    //            reframe.frame.pointee.format = processingSampleFormat.rawValue
    //
    //            do {
    //              try resampleContext.convertFrame(from: frame.frame, to: reframe.frame)
    //            } catch {
    //              Logger.main.error("\(error)")
    //
    //              return
    //            }
    //
    //            guard let sampleFormat = reframe.sampleFormat else {
    //              return
    //            }
    //
    //            let linesize = Int(reframe.frame.pointee.linesize.0)
    //            let indicies = 0..<(sampleFormat.isPlanar ? Int(reframe.frame.pointee.ch_layout.nb_channels) : 1)
    //
    //            indicies.forEach { index in
    //              buffers[index].append(reframe.frame.pointee.extended_data[index]!, count: linesize)
    //            }
    //          }
    //        } catch let err as FFError where err.code == .endOfFile {
    //          // Fallthrough
    //        } catch {
    //          Logger.main.error("\(error)")
    //
    //          return
    //        }
    //
    //        let audioBuffers = buffers.map { buffer in
    //          let outliving = UnsafeMutableBufferPointer<Data.Element>.allocate(capacity: buffer.count)
    //
    //          guard buffer.copyBytes(to: outliving) == outliving.count else {
    //            // TODO: Replace.
    //            fatalError()
    //          }
    //
    //          return AudioBuffer(
    //            outliving,
    //            numberOfChannels: processingFormat.isInterleaved ? Int(processingFormat.channelCount) : 1
    //          )
    //        }
    //
    //        var audioBufferList = AudioBufferList()
    //        audioBufferList.mNumberBuffers = UInt32(audioBuffers.count)
    //
    //        let pointer = UnsafeMutableAudioBufferListPointer(&audioBufferList)
    //
    //        audioBuffers.enumerated().forEach { (bufferi, buffer) in
    //          pointer[bufferi] = buffer
    //        }
    //
    //        let pcmBuffer = AVAudioPCMBuffer(pcmFormat: processingFormat, bufferListNoCopy: &audioBufferList) { audioBufferList in
    //          let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: audioBufferList))
    //          list.forEach { buffer in
    //            buffer.mData?.deallocate()
    //          }
    //        }!
    //
    //        Logger.main.info("\(audioBuffers)")
    //
    //        let audioPlayer = AVAudioPlayerNode()
    //        audioPlayer.volume = 0.25
    //
    //        audioEngine.attach(audioPlayer)
    //        audioEngine.connect(audioPlayer, to: audioEngine.mainMixerNode, format: nil)
    //        audioEngine.mainMixerNode.volume = 0.25
    //
    //        fatalError()
    //
    //        Task {
    //          await audioPlayer.scheduleBuffer(pcmBuffer)
    //
    //          Logger.main.info("Playing? \(audioPlayer.isPlaying) \(pcmBuffer)")
    //        }
    //
    //        try! audioEngine.start()
    //        audioPlayer.play()
    //      }
    //    }
    .overlay(alignment: .bottom) {
      VStack(spacing: 0) {
        Divider()

        Button {
          isFileImporterPresented = true
        } label: {
          Text(verbatim: "Metadata...")
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.background)
        .popover(item: $track, arrowEdge: .top) { track in
          VStack(spacing: 8) {
            Image(nsImage: track.cover)
              .resizable()
              .frame(width: 256, height: 256)
              .scaledToFit()
              .clipShape(.rect(cornerRadius: 8))

            Group {
              Text(verbatim: "\(track.artist) — \(track.title)")
                .fontWeight(.medium)

              Text(verbatim: track.album)
            }
            .font(.headline)
          }
          .padding(12)
        }
        .fileImporter(isPresented: $isFileImporterPresented, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
          switch result {
            case .success(let urls):
              tracks = urls.compactMap { url -> Track? in
                let path = url.pathString
                let context = FFFormatContext()

                do {
                  try url.accessingSecurityScopedResource {
                    try context.open(at: path)
                  }
                } catch {
                  Logger.main.error("\(error)")

                  return nil
                }

                defer {
                  avformat_close_input(&context.context)
                }

                let streams = UnsafeBufferPointer(start: context.context.pointee.streams, count: Int(context.context.pointee.nb_streams))
                  .compactMap { AVDictionaryIterator($0!.pointee.metadata) }
                  .joined()

                let metadata = chain(AVDictionaryIterator(context.context.pointee.metadata), streams)
                  .uniqued(on: \.pointee.key)
                  .reduce(into: [:]) { partialResult, tag in
                    partialResult[String(cString: tag.pointee.key).lowercased()] = String(cString: tag.pointee.value)
                  }

                let title_key = "title"
                let artist_key = "artist"
                let album_key = "album"

                guard let title = metadata[title_key] else {
                  Logger.main.error("URL \"\(path)\" has no metadata for key \"\(title_key)\"")

                  return nil
                }

                guard let artist = metadata[artist_key] else {
                  Logger.main.error("URL \"\(path)\" has no metadata for key \"\(title_key)\"")

                  return nil
                }

                guard let album = metadata[album_key] else {
                  Logger.main.error("URL \"\(path)\" has no metadata for key \"\(title_key)\"")

                  return nil
                }

                guard let video = context.context.pointee.streams[1] else {
                  Logger.main.error("URL \"\(path)\" has no stream 1.")

                  return nil
                }

                let packet = video.pointee.attached_pic
                let data = Data(bytes: packet.data, count: Int(packet.size))

                guard let image = NSImage(data: data) else {
                  Logger.main.info("Stream 1 for URL \"\(path)\" does not contain a representable image.")

                  return nil
                }

                return Track(url: url, title: title, artist: artist, album: album, cover: image)
              }
            case .failure(let err):
              Logger.main.error("\(err)")
          }
        }
      }
    }
  }
}
