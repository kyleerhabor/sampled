//
//  Bookmark.swift
//  Sampled
//
//  Created by Kyle Erhabor on 2/7/26.
//

import Foundation
import OSLog

extension Logger {
  static let sandbox = Self(subsystem: Bundle.appID, category: "Sandbox")
}

extension DispatchQueue {
  static let bookmark = DispatchQueue(label: "\(Bundle.appID).Bookmark", target: .global())
}

extension URL {
  func startSecurityScope() -> Bool {
    let isAccessing = self.startAccessingSecurityScopedResource()

    if isAccessing {
      Logger.sandbox.debug("Started security scope for resource at URL '\(self.debugString)'")
    } else {
      Logger.sandbox.log("Could not start security scope for resource at URL '\(self.debugString)'")
    }

    return isAccessing
  }

  func endSecurityScope() {
    self.stopAccessingSecurityScopedResource()
    Logger.sandbox.debug("Ended security scope for resource at URL '\(self.debugString)'")
  }

  @available(*, noasync)
  func bookmark(options: BookmarkCreationOptions, relativeTo relative: URL?) throws -> Data {
    try self.bookmarkData(options: options, relativeTo: relative)
  }

  func bookmark(options: BookmarkCreationOptions, relativeTo relative: URL?) async throws -> Data {
    try await schedule(on: .bookmark) {
      try self.bookmark(options: options, relativeTo: relative)
    }
  }
}

protocol SecurityScopedResource {
  associatedtype SecurityScope

  func startSecurityScope() -> SecurityScope

  func endSecurityScope(_ scope: SecurityScope)
}

extension SecurityScopedResource {
  func accessingSecurityScopedResource<R, E>(_ body: () throws(E) -> R) throws(E) -> R {
    let scope = self.startSecurityScope()

    defer {
      self.endSecurityScope(scope)
    }

    return try body()
  }

  func accessingSecurityScopedResource<R, E>(
    isolation: isolated (any Actor)? = #isolation,
    _ body: () async throws(E) -> R,
  ) async throws(E) -> R {
    let scope = self.startSecurityScope()

    defer {
      self.endSecurityScope(scope)
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
  // TODO: Consider whether or not to use URL.BookmarkResolutionOptions
  let options: URL.BookmarkCreationOptions
}

extension URLSource: Equatable {}

extension URLSource: Hashable {
  func hash(into hasher: inout Hasher) {
    hasher.combine(self.url)
    hasher.combine(self.options.rawValue)
  }
}

extension URLSource: SecurityScopedResource {
  func startSecurityScope() -> Bool {
    self.options.contains(.withSecurityScope) && self.url.startSecurityScope()
  }

  func endSecurityScope(_ scope: Bool) {
    self.url.endSecurityScope(scope)
  }
}

struct URLSourceDocument {
  let source: URLSource
  let relative: URLSource?
}

extension URLSourceDocument: SecurityScopedResource {
  struct SecurityScope {
    let source: URLSource.SecurityScope
    let relative: URLSource.SecurityScope?
  }

  func startSecurityScope() -> SecurityScope {
    let relative = self.relative?.startSecurityScope()
    let source = self.source.startSecurityScope()
    let scope = SecurityScope(source: source, relative: relative)

    return scope
  }

  func endSecurityScope(_ scope: SecurityScope) {
    self.source.endSecurityScope(scope.source)

    guard let scope = scope.relative else {
      return
    }

    self.relative!.endSecurityScope(scope)
  }
}

// This has one and only one use case: handling an optional relative.
extension Optional: SecurityScopedResource where Wrapped: SecurityScopedResource {
  func startSecurityScope() -> Wrapped.SecurityScope? {
    self?.startSecurityScope()
  }

  func endSecurityScope(_ scope: Wrapped.SecurityScope?) {
    guard let scope else {
      return
    }

    self!.endSecurityScope(scope)
  }
}

extension KeyedEncodingContainer {
  mutating func encode(_ value: URL.BookmarkCreationOptions, forKey key: KeyedEncodingContainer<K>.Key) throws {
    try self.encode(value.rawValue, forKey: key)
  }

  mutating func encode(_ value: URL.BookmarkCreationOptions?, forKey key: KeyedEncodingContainer<K>.Key) throws {
    try self.encode(value?.rawValue, forKey: key)
  }
}

extension KeyedDecodingContainer {
  func decode(
    _ type: URL.BookmarkCreationOptions.Type,
    forKey key: KeyedDecodingContainer<K>.Key,
  ) throws -> URL.BookmarkCreationOptions {
    URL.BookmarkCreationOptions(rawValue: try self.decode(URL.BookmarkCreationOptions.RawValue.self, forKey: key))
  }

  func decodeIfPresent(
    _ type: URL.BookmarkCreationOptions.Type,
    forKey key: KeyedDecodingContainer<K>.Key,
  ) throws -> URL.BookmarkCreationOptions? {
    guard let rawValue = try self.decodeIfPresent(URL.BookmarkCreationOptions.RawValue.self, forKey: key) else {
      return nil
    }

    let options = URL.BookmarkCreationOptions(rawValue: rawValue)

    return options
  }
}

struct Bookmark {
  let data: Data
  let options: URL.BookmarkCreationOptions
}

extension Bookmark {
  @available(*, noasync)
  init(url: URL, options: URL.BookmarkCreationOptions, relativeTo relative: URL?) throws {
    self.init(
      data: try url.bookmark(options: options, relativeTo: relative),
      options: options
    )
  }

  init(url: URL, options: URL.BookmarkCreationOptions, relativeTo relative: URL?) async throws {
    self.init(
      data: try await url.bookmark(options: options, relativeTo: relative),
      options: options
    )
  }
}

extension Bookmark: Sendable {}

extension Bookmark: Codable {
  enum CodingKeys: CodingKey {
    case data, options
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    self.init(
      data: try container.decode(Data.self, forKey: .data),
      options: try container.decode(URL.BookmarkCreationOptions.self, forKey: .options),
    )
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(data, forKey: .data)
    try container.encode(options, forKey: .options)
  }
}

struct URLBookmark {
  let url: URL
  let bookmark: Bookmark

  init(url: URL, bookmark: Bookmark) {
    self.url = url
    self.bookmark = bookmark
  }

  @available(*, noasync)
  init(url: URL, options: URL.BookmarkCreationOptions, relativeTo relative: URL?) throws {
    self.init(
      url: url,
      bookmark: try Bookmark(url: url, options: options, relativeTo: relative),
    )
  }

  init(
    url: URL,
    options: URL.BookmarkCreationOptions,
    relativeTo relative: URL?,
  ) async throws {
    self.init(
      url: url,
      bookmark: try await Bookmark(url: url, options: options, relativeTo: relative),
    )
  }
}

extension URLBookmark: Sendable, Codable {}

struct ResolvedBookmark {
  let url: URL
  let isStale: Bool

  init(url: URL, isStale: Bool) {
    self.url = url
    self.isStale = isStale
  }

  init(data: Data, options: URL.BookmarkResolutionOptions, relativeTo relative: URL?) throws {
    var isStale = false

    self.url = try URL(resolvingBookmarkData: data, options: options, relativeTo: relative, bookmarkDataIsStale: &isStale)
    self.isStale = isStale
  }
}

extension ResolvedBookmark: Sendable {}

// https://english.stackexchange.com/a/227919
struct AssignedBookmark {
  let resolved: ResolvedBookmark
  let data: Data

  init(resolved: ResolvedBookmark, data: Data) {
    self.resolved = resolved
    self.data = data
  }

  @available(*, noasync)
  init(
    data: Data,
    options: URL.BookmarkResolutionOptions,
    relativeTo relative: URL?,
    create: (URL) throws -> Data,
  ) throws {
    var data = data
    let resolved = try ResolvedBookmark(data: data, options: options, relativeTo: relative)

    if resolved.isStale {
      data = try create(resolved.url)
    }

    self.init(resolved: resolved, data: data)
  }

  init(
    data: Data,
    options: URL.BookmarkResolutionOptions,
    relativeTo relative: URL?,
    create: (URL) async throws -> Data,
  ) async throws {
    var data = data
    let resolved = try ResolvedBookmark(data: data, options: options, relativeTo: relative)

    if resolved.isStale {
      data = try await create(resolved.url)
    }

    self.init(resolved: resolved, data: data)
  }
}

extension AssignedBookmark: Sendable {}

struct AssignedBookmarkDocument {
  let bookmark: AssignedBookmark
  let relative: AssignedBookmark?

  init(bookmark: AssignedBookmark, relative: AssignedBookmark?) {
    self.bookmark = bookmark
    self.relative = relative
  }
}

extension AssignedBookmarkDocument: Sendable {}

