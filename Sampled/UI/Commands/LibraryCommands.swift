//
//  LibraryCommands.swift
//  Sampled
//
//  Created by Kyle Erhabor on 10/7/24.
//

import OSLog
import SwiftUI

extension NSUserInterfaceItemIdentifier {
  static let libraryOpen = Self(rawValue: "\(Bundle.appID).open-library")
}

struct LibraryCommands: Commands {
  @Environment(\.openWindow) private var openWindow
  @FocusedValue(\.open) private var open
  @FocusedValue(\.importTracks) private var importTracks

  var body: some Commands {
    CommandGroup(replacing: .newItem) {
      Section {
        MenuItemView(item: importTracks ?? AppMenuActionItem(identity: nil, isEnabled: false, action: noop)) {
          Text("Library.Commands.File.Import")
        }
        .keyboardShortcut(.add)
      }

      Section {
        MenuItemView(item: open ?? AppMenuActionItem(identity: nil, isEnabled: true, action: performOpen)) {
          Text("Library.Commands.File.Open")
        }
        .keyboardShortcut(.open)
      }
    }
  }

  func performOpen() {
    Task {
      await performOpen()
    }
  }

  func performOpen() async {
    let panel = NSOpenPanel()
    panel.identifier = .libraryOpen
    panel.canChooseFiles = true
//    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = true
    panel.allowedContentTypes = libraryContentTypes

    // We don't want panel.begin() since it creates a modeless window—a kind which SwiftUI does not recognize focus for.
    // This is most apparent when the open dialog window is the only window and the user activates the app, causing
    // SwiftUI to create a new window.
    //
    // FIXME: Entering Command-Shift-. to show hidden files causes the service to crash.
    //
    // This only occurs when using an identifier. Interestingly, this affects SwiftUI, too (using fileDialogCustomizationID(_:)).
    guard panel.runModal() == .OK else {
      return
    }

    let library = LibraryModel(id: .scene(UUID()))
    library.tracks = await load(urls: panel.urls)

    openWindow(value: library)
  }

  nonisolated func load(urls: [URL]) async -> [LibraryTrack] {
    urls.compactMap { url in
      let source = URLSource(url: url, options: [.withReadOnlySecurityScope, .withoutImplicitSecurityScope])

      return source.accessingSecurityScopedResource {
        do {
          return try LibraryModel.read(source: source)
        } catch {
          Logger.ffmpeg.error("\(error)")

          return nil
        }
      }
    }
  }
}
