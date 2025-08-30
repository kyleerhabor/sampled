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

struct EventStreamEventFlags: OptionSet {
  var rawValue: Int

  static let mustScanSubdirectories = Self(rawValue: kFSEventStreamEventFlagMustScanSubDirs)
}

struct EventStreamEvents {
  let count: Int
  let paths: [URL]
  let flags: [EventStreamEventFlags]
}

final class EventStream {
  typealias Action = (EventStreamEvents) -> Void

  private let queue = DispatchQueue(label: "\(Bundle.appID).EventStream", target: .global())
  private var stream: FSEventStreamRef?
  private var action: Action?

  deinit {
    queue.sync {
      guard let stream else {
        return
      }

      FSEventStreamInvalidate(stream)
    }
  }

  func create(forFileAt fileURL: URL, latency: Double, _ action: @escaping Action) -> Bool {
    queue.sync {
      self.action = action

      var context = FSEventStreamContext(
        version: 0,
        info: Unmanaged.passUnretained(self).toOpaque(),
        retain: { info in
          _ = Unmanaged<EventStream>.fromOpaque(info!).retain()

          return info
        },
        release: { info in
          Unmanaged<EventStream>.fromOpaque(info!).release()
        },
        copyDescription: nil,
      )

      guard let stream = FSEventStreamCreate(
        nil,
        { eventStream, info, eventCount, eventPaths, eventFlags, eventIDs in
          let this = Unmanaged<EventStream>.fromOpaque(info!).takeUnretainedValue()
          let eventPaths = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
          this.action!(
            EventStreamEvents(
              count: eventCount,
              paths: UnsafeBufferPointer(start: eventPaths, count: eventCount)
                .map { URL(fileURLWithFileSystemRepresentation: $0, isDirectory: true, relativeTo: nil) },
              flags: UnsafeBufferPointer(start: eventFlags, count: eventCount)
                .map { EventStreamEventFlags(rawValue: Int($0)) },
            ),
          )
        },
        &context,
        [fileURL.pathString] as CFArray,
        // TODO: Accept as a parameter.
        //
        // If we replace the event stream, we want to start at the last event ID, rather than the current one.
        FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
        latency,
        // We could use kFSEventStreamCreateFlagFileEvents to subscribe to individual files, but we're already notified
        // about changes to the directory, and we need to check it for flags like kFSEventStreamEventFlagMustScanSubDirs,
        // so we may as well eat the cost of enumerating directories.
        FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot),
      ) else {
        return false
      }

      // Should we let the user set the dispatch queue?
      FSEventStreamSetDispatchQueue(stream, .global())

      self.stream = stream

      return true
    }
  }

  func start() -> Bool {
    queue.sync {
      guard let stream else {
        return false
      }

      return FSEventStreamStart(stream)
    }
  }

  func stop() {
    queue.sync {
      guard let stream else {
        return
      }

      FSEventStreamStop(stream)
    }
  }
}

extension EventStream: @unchecked Sendable {}
