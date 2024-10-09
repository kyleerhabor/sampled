//
//  Standard.swift
//  Forward
//
//  Created by Kyle Erhabor on 5/14/24.
//

import Foundation
import OSLog

func noop<each Argument>(_ args: repeat each Argument) -> Void {}

extension Bundle {
  static let appIdentifier = Bundle.main.bundleIdentifier!
}

extension Logger {
  static let main = Self()
  static let ui = Self(subsystem: Bundle.appIdentifier, category: "UI")
  static let sandbox = Self(subsystem: Bundle.appIdentifier, category: "Sandbox")
  static let ffmpeg = Self(subsystem: Bundle.appIdentifier, category: "FFmpeg")
}

extension RangeReplaceableCollection {
  init(minimumCapacity capacity: Int) {
    self.init()
    self.reserveCapacity(capacity)
  }
}

extension URL {
  var pathString: String {
    self.path(percentEncoded: false)
  }

  // TODO: Move security-scoped related code elsewhere.
  func startSecurityScope() -> Bool {
    let accessing = self.startAccessingSecurityScopedResource()

    if accessing {
      Logger.sandbox.debug("Started security scope for URL \"\(self.pathString)\"")
    } else {
      Logger.sandbox.info("Tried to start security scope for URL \"\(self.pathString)\", but scope was inaccessible")
    }

    return accessing
  }

  func endSecurityScope() {
    self.stopAccessingSecurityScopedResource()

    Logger.sandbox.debug("Ended security scope for URL \"\(self.pathString)\"")
  }
}

protocol SecurityScopedResource {
  associatedtype Scope

  func startSecurityScope() -> Scope

  func endSecurityScope(_ scope: Scope)
}

extension SecurityScopedResource {
  func accessingSecurityScopedResource<T, Failure>(_ body: () throws(Failure) -> T) throws(Failure) -> T {
    let scope = startSecurityScope()

    defer {
      endSecurityScope(scope)
    }

    return try body()
  }
}

extension URL: SecurityScopedResource {
  func endSecurityScope(_ scope: Bool) {
    guard scope else {
      return
    }

    self.endSecurityScope()
  }
}
