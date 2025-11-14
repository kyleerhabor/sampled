//
//  HistoryScene.swift
//  Sampled
//
//  Created by GitHub Copilot on 11/13/25.
//

import SwiftUI

struct HistoryScene: Scene {
  var body: some Scene {
    Window("History", id: "history") {
      HistoryView()
    }
    .keyboardShortcut("h", modifiers: [.command, .shift])
    .defaultSize(width: 800, height: 600)
  }
}
