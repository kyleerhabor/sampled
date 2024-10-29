//
//  SettingsView.swift
//  Forward
//
//  Created by Kyle Erhabor on 10/18/24.
//

import SwiftUI

extension EnvironmentValues {
  @Entry var settingsWidth = CGFloat.zero
}

struct SettingsGroupBoxStyle: GroupBoxStyle {
  func makeBody(configuration: Configuration) -> some View {
    VStack(alignment: .leading, spacing: 6) { // 2^2 + 2^1
      configuration.label

      configuration.content
        .groupBoxStyle(.settings)
        .padding(.leading)
    }
  }
}

struct SettingsGroupedGroupBoxStyle: GroupBoxStyle {
  func makeBody(configuration: Configuration) -> some View {
    VStack(alignment: .leading, spacing: 6) { // 2^2 + 2^1
      configuration.content
        .groupBoxStyle(.settings)
    }
  }
}

extension GroupBoxStyle where Self == SettingsGroupBoxStyle {
  static var settings: SettingsGroupBoxStyle {
    SettingsGroupBoxStyle()
  }
}


extension GroupBoxStyle where Self == SettingsGroupedGroupBoxStyle {
  static var settingsGrouped: SettingsGroupedGroupBoxStyle {
    SettingsGroupedGroupBoxStyle()
  }
}

struct SettingsLabeledContentStyle: LabeledContentStyle {
  @Environment(\.settingsWidth) private var width

  func makeBody(configuration: Configuration) -> some View {
    GridRow(alignment: .firstTextBaseline) {
      Color.clear.frame(maxWidth: .infinity, maxHeight: 0)

      configuration.label
        .frame(width: width * 0.3, alignment: .trailing)

      VStack(alignment: .leading) {
        configuration.content
          .groupBoxStyle(.settings)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(width: width * 0.7, alignment: .leading)

      Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
    }
  }
}

extension LabeledContentStyle where Self == SettingsLabeledContentStyle {
  static var settings: SettingsLabeledContentStyle {
    SettingsLabeledContentStyle()
  }
}

struct SettingsFormStyle: FormStyle {
  let width: CGFloat

  func makeBody(configuration: Configuration) -> some View {
    Grid {
      configuration.content
        .labeledContentStyle(.settings)
        .environment(\.settingsWidth, width)
    }
  }
}

extension FormStyle {
  static func settings(width: CGFloat) -> some FormStyle where Self == SettingsFormStyle {
    SettingsFormStyle(width: width)
  }
}

struct SettingsView: View {
  static let contentWidth: CGFloat = 448 // 384 - 512

  @AppStorage(StorageKeys.preferArtistsDisplay.name) private var preferArtistsDisplay = StorageKeys.preferArtistsDisplay.defaultValue

  var body: some View {
    Form {
      Toggle("Settings.PreferArtistsDisplay", isOn: $preferArtistsDisplay)
    }
    .scenePadding()
  }
}
