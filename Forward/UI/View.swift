//
//  View.swift
//  Forward
//
//  Created by Kyle Erhabor on 10/3/24.
//

import SwiftUI

extension View {
  private static var opaque: Double { 1 }
  private static var transparent: Double { 0 }

  func visible(_ flag: Bool) -> some View {
    self.opacity(flag ? Self.opaque : Self.transparent)
  }
}
