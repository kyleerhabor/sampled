//
//  Core.swift
//  Sampled
//
//  Created by Kyle Erhabor on 2/7/26.
//

import Foundation

// MARK: - Swift

extension Sequence where Element == UInt8 {
  // https://stackoverflow.com/a/40089462
  func hexEncodedString() -> String {
    let format = "%02hhx" // Lower case.
    let string = self.map { String(format: format, $0) }.joined()

    return string
  }
}


extension RangeReplaceableCollection {
  init(reservingCapacity capacity: Int) {
    self.init()
    self.reserveCapacity(capacity)
  }
}

extension SetAlgebra {
  func isNonEmptySubset(of other: Self) -> Bool {
    !self.isEmpty && self.isSubset(of: other)
  }
}

// MARK: - Swift Concurrency

// In some settings, calling a synchronous function from an asynchronous one can block the underlying cooperative thread,
// deadlocking the system when all cooperative threads are blocked (e.g., calling URL/bookmarkData(options:includingResourceValuesForKeys:relativeTo:)
// from a task group). I presume this is caused by a function:
//
//   1. Not being preconcurrency
//   2. Being I/O bound
//   3. Blocking a cooperative thread
//
// The solution, then, is to not block cooperative threads.
//
// See https://forums.swift.org/t/cooperative-pool-deadlock-when-calling-into-an-opaque-subsystem/70685
func schedule<T>(on queue: DispatchQueue, _ body: @escaping @Sendable () throws -> T) async throws -> T {
  try await withCheckedThrowingContinuation { continuation in
    queue.async {
      do {
        continuation.resume(returning: try body())
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }
}

// MARK: - Foundation

extension URL {
  var debugString: String {
    let absoluteString = self.absoluteString
    let string = absoluteString.removingPercentEncoding ?? absoluteString

    return string
  }
}

struct TypedIterator<Base, T> where Base: IteratorProtocol {
  private var base: Base

  init(_ base: Base, as type: T.Type = T.self) {
    self.base = base
  }
}

extension TypedIterator: IteratorProtocol {
  mutating func next() -> T? {
    self.base.next() as? T
  }
}

extension TypedIterator: Sequence {}

extension FileManager {
  func enumerate(at url: URL, options: FileManager.DirectoryEnumerationOptions) -> (some Sequence<URL>)? {
    guard let enumerator = self.enumerator(at: url, includingPropertiesForKeys: nil, options: options) else {
      return nil as TypedIterator<NSFastEnumerationIterator, URL>?
    }

    let result = TypedIterator(enumerator.makeIterator(), as: URL.self)

    return result
  }
}

// MARK: -

extension Bundle {
  static let appID = Bundle.main.bundleIdentifier!
}

func unreachable() -> Never {
  fatalError("Reached supposedly unreachable code")
}
