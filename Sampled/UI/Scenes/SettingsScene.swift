//
//  SettingsScene.swift
//  Sampled
//
//  Created by Kyle Erhabor on 8/17/25.
//

import SwiftUI

struct SettingsScene: Scene {
  var body: some Scene {
    Settings {
      SettingsView()
    }
    .windowResizability(.contentSize)
  }
}
