//
//  Standard.swift
//  Forward
//
//  Created by Kyle Erhabor on 5/14/24.
//

import Foundation
import OSLog

func noop<each Argument>(_ args: repeat each Argument) -> Void {}

func transform<T, E, each Argument>(
  _ args: repeat each Argument,
  body: (repeat each Argument) throws(E) -> T
) throws(E) -> T {
  try body(repeat each args)
}

extension Duration {
  static let hour = Self.seconds(60 * 60)
}

extension Sequence {
  func filter<T>(in set: some SetAlgebra<T>, by transform: (Element) -> T) -> [Element] {
    self.filter { set.contains(transform($0)) }
  }
}

// MARK: - Darwin

extension Bundle {
  static let appID = Bundle.main.bundleIdentifier!
}

extension Logger {
  static let ui = Self(subsystem: Bundle.appID, category: "UI")
  static let model = Self(subsystem: Bundle.appID, category: "Model")
  static let sandbox = Self(subsystem: Bundle.appID, category: "Sandbox")
  static let ffmpeg = Self(subsystem: Bundle.appID, category: "FFmpeg")
}

extension Date {
  static let epoch = Date(timeIntervalSinceReferenceDate: 0)
}

extension URL {
  var pathString: String {
    self.path(percentEncoded: false)
  }

  var lastPath: String {
    self.deletingPathExtension().lastPathComponent
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

extension URL.BookmarkCreationOptions {
  public static let withReadOnlySecurityScope = Self([.withSecurityScope, .securityScopeAllowOnlyReadAccess])
}

protocol SecurityScopedResource {
  associatedtype Scope

  func startSecurityScope() -> Scope

  func endSecurityScope(_ scope: Scope)
}

extension SecurityScopedResource {
  func accessingSecurityScopedResource<T, E>(_ body: () throws(E) -> T) throws(E) -> T {
    let scope = startSecurityScope()

    defer {
      endSecurityScope(scope)
    }

    return try body()
  }

  public func accessingSecurityScopedResource<T, E>(
    _ body: @isolated(any) () async throws(E) -> T
  ) async throws(E) -> T where T: Sendable {
    let scope = startSecurityScope()

    defer {
      endSecurityScope(scope)
    }

    return try await body()
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

struct URLSource {
  let url: URL
  let options: URL.BookmarkCreationOptions

  init(url: URL, options: URL.BookmarkCreationOptions) {
    self.url = url
    self.options = options
  }
}

extension URLSource: Equatable {}

extension URLSource: SecurityScopedResource {
  func startSecurityScope() -> Bool {
    options.contains(.withSecurityScope) && url.startSecurityScope()
  }

  func endSecurityScope(_ scope: Bool) {
    url.endSecurityScope(scope)
  }
}
