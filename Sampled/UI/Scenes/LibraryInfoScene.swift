//
//  LibraryInfoScene.swift
//  Sampled
//
//  Created by Kyle Erhabor on 10/12/24.
//

import SwiftUI

struct LibraryInfoScene: Scene {
  @FocusedValue(LibraryInfoTrackModel.self) private var libraryInfoTrack
  @State private var defaultLibraryInfoTrack = LibraryInfoTrackModel()

  var body: some Scene {
    // TODO: Size to content size.
    UtilityWindow("LibraryInfo.Window.Title", id: "library-info") {
      LibraryInfoView()
        .environment(libraryInfoTrack ?? defaultLibraryInfoTrack)
        .frame(
          width: 224, // 192 - 256
          height: 496, // 480 - 512
          alignment: .top
        )
    }
    .keyboardShortcut(.libraryInfo)
    .windowResizability(.contentSize)
    .restorationBehavior(.disabled)
  }
}
