//
//  LibraryCommands.swift
//  Forward
//
//  Created by Kyle Erhabor on 10/7/24.
//

import SwiftUI

struct LibraryCommands: Commands {
  @FocusedValue(\.open) private var open

  var body: some Commands {
    CommandGroup(after: .newItem) {
      Section {
        MenuItemView(item: open ?? AppMenuActionItem(identity: nil, isEnabled: false, action: noop)) {
          Text("Library.Commands.File.Open")
        }
        .keyboardShortcut(.open)
      }
    }
  }
}
