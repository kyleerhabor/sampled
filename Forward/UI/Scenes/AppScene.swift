//
//  AppScene.swift
//  Forward
//
//  Created by Kyle Erhabor on 10/3/24.
//

import SwiftUI

struct AppScene: Scene {
  var body: some Scene {
    Window("Library", id: "main") {
      LibraryView()
    }
    .commands {
      LibraryCommands()
    }

    LibraryInfoScene()
  }
}
