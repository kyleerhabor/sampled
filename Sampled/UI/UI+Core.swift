//
//  UI+Core.swift
//  Sampled
//
//  Created by Kyle Erhabor on 10/18/24.
//

import Foundation
import OSLog
import SwiftUI

// MARK: - Foundation

extension URL {
  static let file = URL(string: "file:")!
}

// MARK: - Core Graphics

extension CGSize {
  var length: Double {
    max(self.width, self.height)
  }
}

// MARK: -

extension Logger {
  static let ui = Self(subsystem: Bundle.appID, category: "UI")
}

enum StorageAppearance: Int {
  case automatic, light, dark

  var appearance: NSAppearance? {
    switch self {
      case .light: NSAppearance(named: .aqua)
      case .dark: NSAppearance(named: .darkAqua)
      default: nil
    }
  }
}

enum StorageLibrarySource: Int {
  case none, local, openSubsonic
}

enum StorageOpenSubsonicLibrarySourceAuthenticationMethod: Int {
  case none, apiKey, login
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

extension AppStorage {
  init(_ key: StorageKey<Value>) where Value == String {
    self.init(wrappedValue: key.defaultValue, key.name)
  }

  // For some reason, init(wrappedValue:_:store:) doesn't recognize URL? as Value.
  init(_ key: StorageKey<Value>) where Value == URL {
    self.init(wrappedValue: key.defaultValue, key.name)
  }

  init(_ key: StorageKey<Value>) where Value: RawRepresentable,
                                       Value.RawValue == Int {
    self.init(wrappedValue: key.defaultValue, key.name)
  }
}

enum StorageKeys {
  private static let appID = Bundle.main.object(forInfoDictionaryKey: "DEFAULTS_PRODUCT_BUNDLE_IDENTIFIER") as! String

  static let appearance = StorageKey("\(Self.appID)_appearance", defaultValue: StorageAppearance.automatic)
  static let librarySource = StorageKey("\(Self.appID)_library_source", defaultValue: StorageLibrarySource.none)
  static let librarySourceOpenSubsonicLocation = StorageKey(
    "\(Self.appID)_library_source_opensubsonic_location",
    defaultValue: "",
  )
  
  static let librarySourceOpenSubsonicAuthenticationMethod = StorageKey(
    "\(Self.appID)_library_source_opensubsonic_authentication_method",
    defaultValue: StorageOpenSubsonicLibrarySourceAuthenticationMethod.none,
  )
  /// The URL to the user's library folder.
  ///
  /// This is sourced from SQLite but exists so SwiftUI can render it without fetching from the database.
  static let libraryFolder = StorageKey("\(Self.appID)_library_folder", defaultValue: URL.file)
}
