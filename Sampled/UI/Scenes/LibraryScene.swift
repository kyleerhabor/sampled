//
//  LibraryScene.swift
//  Sampled
//
//  Created by Kyle Erhabor on 8/17/25.
//

import SwiftUI

struct LibraryScene: Scene {
  var body: some Scene {
    Window("Library.Window.Title", id: "library") {
      LibraryView()
    }
    .windowToolbarStyle(.unifiedCompact)
    .commands {
      LibraryCommands()
    }
  }
}
