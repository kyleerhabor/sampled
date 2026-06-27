//
//  AccessoryButtonStyle.swift
//  Sampled
//
//  Created by Kyle Erhabor on 5/7/26.
//

import SwiftUI

struct AccessoryButtonStyle: PrimitiveButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    Button(configuration)
      .buttonStyle(.accessoryBarAction)
      .font(.callout)
  }
}

extension PrimitiveButtonStyle where Self == AccessoryButtonStyle {
  static var accessory: AccessoryButtonStyle {
    AccessoryButtonStyle()
  }
}
