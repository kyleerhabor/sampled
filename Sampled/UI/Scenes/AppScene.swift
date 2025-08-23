//
//  AppScene.swift
//  Sampled
//
//  Created by Kyle Erhabor on 10/3/24.
//

import SwiftUI

struct AppScene: Scene {
  @State private var library = LibraryModel()
  @State private var settings = SettingsModel()

  var body: some Scene {
    LibraryScene()
      .environment(library)

    LibraryInfoScene()

    SettingsScene()
      .environment(settings)
  }
}
