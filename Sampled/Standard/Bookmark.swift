//
//  Bookmark.swift
//  Sampled
//
//  Created by Kyle Erhabor on 8/24/25.
//

import Foundation
import OSLog

extension URL {
  func startSecurityScope() -> Bool {
    let accessing = self.startAccessingSecurityScopedResource()

    if accessing {
      Logger.sandbox.debug("Started security scope for URL '\(self.pathString)'")
    } else {
      Logger.sandbox.log("Could not start security scope for URL '\(self.pathString)'")
    }

    return accessing
  }

  func endSecurityScope() {
    self.stopAccessingSecurityScopedResource()

    Logger.sandbox.debug("Ended security scope for URL '\(self.pathString)'")
  }
}

extension URL.BookmarkResolutionOptions {
  init(_ options: URL.BookmarkCreationOptions) {
    self.init()

    if options.contains(.withSecurityScope) {
      self.insert(.withSecurityScope)
    }

    if options.contains(.withoutImplicitSecurityScope) {
      self.insert(.withoutImplicitStartAccessing)
    }
  }
}

protocol SecurityScopedResource {
  associatedtype Scope

  func startSecurityScope() -> Scope

  func endSecurityScope(_ scope: Scope)
}

extension SecurityScopedResource {
  func accessingSecurityScopedResource<R, E>(_ body: () throws(E) -> R) throws(E) -> R {
    let scope = startSecurityScope()

    defer {
      endSecurityScope(scope)
    }

    return try body()
  }

  func accessingSecurityScopedResource<Result, E>(
    _ body: @isolated(any) () async throws(E) -> Result
  ) async throws(E) -> Result where Result: Sendable {
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

    return URL.BookmarkCreationOptions(rawValue: rawValue)
  }
}

struct Bookmark {
  let data: Data
  let options: URL.BookmarkCreationOptions
}

extension Bookmark {
  init(url: URL, options: URL.BookmarkCreationOptions, relativeTo relative: URL?) throws {
    self.init(
      data: try url.bookmarkData(options: options, relativeTo: relative),
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

struct ResolvedBookmark {
  let url: URL
  let isStale: Bool
}

extension ResolvedBookmark {
  init(data: Data, options: URL.BookmarkResolutionOptions, relativeTo relative: URL?) throws {
    var isStale = false

    self.url = try URL(resolvingBookmarkData: data, options: options, relativeTo: relative, bookmarkDataIsStale: &isStale)
    self.isStale = isStale
  }
}

extension ResolvedBookmark: Sendable {}

// https://english.stackexchange.com/a/227919
struct AssignedBookmark {
  let url: URL
  let data: Data
}

extension AssignedBookmark {
  init(
    data: Data,
    options: URL.BookmarkResolutionOptions,
    relativeTo relative: URL?,
    create: (URL) throws -> Data,
  ) throws {
    var data = data
    let resolved = try ResolvedBookmark(data: data, options: options, relativeTo: relative)

    if resolved.isStale {
      Logger.sandbox.log("Bookmark for URL '\(resolved.url.pathString)' is stale: re-creating...")

      data = try create(resolved.url)
    }

    self.init(url: resolved.url, data: data)
  }
}

extension AssignedBookmark: Sendable {}

struct URLBookmark {
  let url: URL
  let bookmark: Bookmark
}

extension URLBookmark {
  init(url: URL, options: URL.BookmarkCreationOptions, relativeTo relative: URL?) throws {
    self.init(
      url: url,
      bookmark: try Bookmark(url: url, options: options, relativeTo: relative)
    )
  }
}

extension URLBookmark: Sendable, Codable {}
