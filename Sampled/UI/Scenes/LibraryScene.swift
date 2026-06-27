//
//  LibraryScene.swift
//  Sampled
//
//  Created by Kyle Erhabor on 8/17/25.
//

import SwiftUI

struct LibraryScene: Scene {
  static let id = "library"

  var body: some Scene {
    // TODO: Support multiple libraries.
    Window("Library.Window.Title", id: "library") {
      LibraryView()
    }
    .windowToolbarStyle(.unifiedCompact)
    .commands {
      LibraryCommands()
    }
  }
}
