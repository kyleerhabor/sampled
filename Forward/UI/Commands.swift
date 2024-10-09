//
//  Commands.swift
//  Forward
//
//  Created by Kyle Erhabor on 10/7/24.
//

import SwiftUI

struct MenuItemView<I, Label>: View where I: Equatable, Label: View {
  typealias ActionItem = AppMenuActionItem<I>

  private let item: ActionItem
  private let label: Label

  var body: some View {
    Button {
      item()
    } label: {
      label
    }
    .disabled(!item.isEnabled)
  }

  init(item: ActionItem, @ViewBuilder label: () -> Label) {
    self.item = item
    self.label = label()
  }
}
