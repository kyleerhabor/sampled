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

func unreachable() -> Never {
  fatalError("Reached supposedly unreachable code")
}

func setter<Object: AnyObject, Value>(
  _ value: Value,
  on keyPath: ReferenceWritableKeyPath<Object, Value>,
) -> (Object) -> Void {
  { object in
    object[keyPath: keyPath] = value
  }
}

extension Duration {
  static let hour = Self.seconds(60 * 60)
}

extension Sequence {
  func filter<T>(in set: some SetAlgebra<T>, by transform: (Element) -> T) -> [Element] {
    self.filter { set.contains(transform($0)) }
  }

  func filter(ids: some SetAlgebra<Element.ID>) -> [Element] where Element: Identifiable {
    self.filter(in: ids, by: \.id)
  }

  func sum() -> Element where Element: AdditiveArithmetic {
    self.reduce(.zero, +)
  }
}

extension RangeReplaceableCollection {
  init(minimumCapacity capacity: Int) {
    self.init()
    self.reserveCapacity(capacity)
  }
}

extension Set {
  func isNonEmptySubset(of other: Self) -> Bool {
    !self.isEmpty && self.isSubset(of: other)
  }
}

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
}

extension UserDefaults {
  static var `default`: Self {
    let suiteName: String?

    #if DEBUG
    suiteName = nil

    #else
    suiteName = "\(Bundle.appID).Debug"

    #endif

    return Self(suiteName: suiteName)!
  }
}
