//
//  VisibleViewModifier.swift
//  Sampled
//
//  Created by Kyle Erhabor on 5/8/26.
//

import SwiftUI

struct VisibleViewModifier: ViewModifier {
  private static let transparent = 0.0
  private static let opaque = 1.0
  let isVisible: Bool

  func body(content: Content) -> some View {
    content
      .opacity(self.isVisible ? Self.opaque : Self.transparent)
  }
}

extension View {
  func visible(_ isVisible: Bool) -> some View {
    self.modifier(VisibleViewModifier(isVisible: isVisible))
  }
}
