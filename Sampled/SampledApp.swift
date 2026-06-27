//
//  SampledApp.swift
//  Sampled
//
//  Created by Kyle Erhabor on 5/12/24.
//

import CFFmpeg
import OSLog
import SwiftUI

@main
struct SampledApp: App {
  @NSApplicationDelegateAdaptor private var delegate: AppDelegate

  var body: some Scene {
    AppScene()
      .environment(self.delegate)
  }

  init() {
    setLogLevel(level: LogLevel.verbose.rawValue)
    setLogCallback { @Sendable _, level, format, arguments in
      guard level <= getLogLevel() else {
        return
      }

      let message = NSString(format: String(cString: format), arguments: arguments)
      let level: OSLogType = switch LogLevel(rawValue: level) {
        case .trace, .debug, .verbose, .info:
          .debug
        case .warning:
          .default
        case .error, .fatal:
          .error
        case .panic:
          .fault
        default:
          .default
      }

      // TODO: Figure out how to only redact arguments.
      Logger.ffmpeg.log(level: level, "\(message, privacy: .public)")
    }
  }
}
