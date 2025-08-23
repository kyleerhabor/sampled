//
//  Standard.swift
//  Sampled
//
//  Created by Kyle Erhabor on 5/14/24.
//

import Foundation
import OSLog

typealias AsyncStreamContinuationPair<Element> = (
  stream: AsyncStream<Element>,
  continuation: AsyncStream<Element>.Continuation,
)

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

  func sum() -> Element where Element: AdditiveArithmetic {
    self.reduce(.zero, +)
  }
}

extension Sequence where Element: Identifiable {
  func filter(ids: some SetAlgebra<Element.ID>) -> [Element] {
    self.filter(in: ids, by: \.id)
  }
}

extension RangeReplaceableCollection {
  init(minimumCapacity capacity: Int) {
    self.init()
    self.reserveCapacity(capacity)
  }
}

// MARK: - Darwin

extension Bundle {
  static let appID = Bundle.main.bundleIdentifier!
}

extension Logger {
  static let sandbox = Self(subsystem: Bundle.appID, category: "Sandbox")
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
      Logger.sandbox.debug("Started security scope for URL '\(self.pathString)'")
    } else {
      Logger.sandbox.log("Tried to start security scope for URL '\(self.pathString)', but scope was inaccessible")
    }

    return accessing
  }

  func endSecurityScope() {
    self.stopAccessingSecurityScopedResource()

    Logger.sandbox.debug("Ended security scope for URL '\(self.pathString)'")
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

  func accessingSecurityScopedResource<R, E>(
    _ body: @isolated(any) () async throws(E) -> R
  ) async throws(E) -> R where R: Sendable {
    let scope = startSecurityScope()

    defer {
      endSecurityScope(scope)
    }

    return try await body()
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

public actor Once<Value> where Value: Sendable {
  public typealias Producer = () async throws -> Value

  private let producer: Producer
  private var task: Task<Value, any Error>?

  public init(_ producer: @escaping Producer) {
    self.producer = producer
  }

  public func callAsFunction() async throws -> Value {
    if let task {
      return try await task.value
    }

    let task = Task {
      try await producer()
    }

    self.task = task

    do {
      return try await task.value
    } catch {
      // Try again on the next invocation.
      self.task = nil

      throw error
    }
  }
}
