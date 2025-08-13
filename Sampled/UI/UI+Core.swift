//
//  UI+Core.swift
//  Sampled
//
//  Created by Kyle Erhabor on 10/18/24.
//

import SwiftUI

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
