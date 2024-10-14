//
//  View.swift
//  Forward
//
//  Created by Kyle Erhabor on 10/3/24.
//

import SwiftUI

struct AppMenuItemAction<I, A> where I: Equatable {
  let identity: I
  let action: A
}

extension AppMenuItemAction: Equatable {
  static func ==(lhs: Self, rhs: Self) -> Bool {
    lhs.identity == rhs.identity
  }
}

struct AppMenuItem<I, A> where I: Equatable {
  let isEnabled: Bool
  let action: AppMenuItemAction<I, A>
}

extension AppMenuItem {
  init(identity: I, isEnabled: Bool, action: A) {
    self.init(
      isEnabled: isEnabled,
      action: AppMenuItemAction(identity: identity, action: action)
    )
  }
}

extension AppMenuItem: Equatable {}

typealias AppMenuItemDefaultAction = () -> Void
typealias AppMenuActionItem<I> = AppMenuItem<I, AppMenuItemDefaultAction> where I: Equatable

extension AppMenuItem where A == AppMenuItemDefaultAction {
  func callAsFunction() {
    action.action()
  }
}

extension KeyboardShortcut {
  static let open = KeyboardShortcut("o", modifiers: .command)
}

extension View {
  private static var opaque: Double { 1 }
  private static var transparent: Double { 0 }

  func visible(_ flag: Bool) -> some View {
    self.opacity(flag ? Self.opaque : Self.transparent)
  }
}

extension Text {
  init() {
    self.init(verbatim: "")
  }
}

enum OpenIdentity {
  case library
}

extension OpenIdentity: Equatable {}

extension FocusedValues {
  @Entry var open: AppMenuActionItem<OpenIdentity?>?
  @Entry var tracks: [LibraryTrack]?
}
