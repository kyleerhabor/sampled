//
//  AppScene.swift
//  Sampled
//
//  Created by Kyle Erhabor on 10/3/24.
//

import SwiftUI

struct AppScene: Scene {
  var body: some Scene {
    WindowGroup { $library in
      LibraryView()
        .environment(library)
    } defaultValue: {
      LibraryModel(id: .main)
    }
    .commands {
      LibraryCommands()
    }

    LibraryInfoScene()

    Settings {
      SettingsView()
        .frame(width: 384) // 256 - 512
    }
    .windowResizability(.contentSize)
  }
}
