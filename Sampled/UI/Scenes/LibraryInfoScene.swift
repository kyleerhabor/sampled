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
    UtilityWindow("LibraryInfo.Window.Title", id: "library-info") {
      LibraryInfoView()
        .environment(libraryInfoTrack ?? defaultLibraryInfoTrack)
        .frame(width: 320, height: 480)
    }
    .keyboardShortcut(.libraryInfo)
    .windowResizability(.contentSize)
    .restorationBehavior(.disabled)
  }
}
