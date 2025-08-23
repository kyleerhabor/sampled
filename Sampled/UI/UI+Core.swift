//
//  UI+Core.swift
//  Sampled
//
//  Created by Kyle Erhabor on 10/18/24.
//

import Defaults
import OSLog
import SwiftUI

extension Logger {
  static let ui = Self(subsystem: Bundle.appID, category: "UI")
  static let model = Self(subsystem: Bundle.appID, category: "Model")
  static let ffmpeg = Self(subsystem: Bundle.appID, category: "FFmpeg")
}

struct StorageKey<Value> {
  let name: String
  let defaultValue: Value
}

extension StorageKey {
  init(_ name: String, defaultValue: Value) {
    self.init(name: name, defaultValue: defaultValue)
  }
}

extension StorageKey: Sendable where Value: Sendable {}

enum StorageKeys {}

extension AppStorage {
  init(_ key: StorageKey<Value>) where Value == Bool {
    self.init(wrappedValue: key.defaultValue, key.name)
  }
}

extension Defaults.Keys {
  // Defaults does not allow periods in key names, meaning unless we want to munge it, we can't qualify it with our
  // bundle ID.

  /// The URL to the user's library folder.
  ///
  /// This is sourced from SQLite but exists so SwiftUI can render it without fetching from the database.
  static let libraryFolderURL = Key("library-folder-url", default: nil as URL?)
}
