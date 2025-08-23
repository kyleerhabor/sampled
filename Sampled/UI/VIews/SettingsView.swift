//
//  SettingsView.swift
//  Sampled
//
//  Created by Kyle Erhabor on 10/18/24.
//

import Defaults
import OSLog
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

  @Environment(SettingsModel.self) private var settings
  @Default(.libraryFolderURL) private var libraryFolder
  @State private var isFileImporterPresented = false

  var body: some View {
    Form {
      GroupBox("Settings.Item.LibraryFolder.Title") {
        VStack(alignment: .leading) {
          if let libraryFolder {
            Text(libraryFolder.pathString)
              .monospaced()

            HStack {
              Spacer()

              Button("Settings.Item.LibraryFolder.Change") {
                isFileImporterPresented = true
              }
            }
          } else {
            ContentUnavailableView {
              Text("Settings.Item.LibraryFolder.Unavailable")
            } actions: {
              Button("Settings.Item.LibraryFolder.Unavailable.Action.Set") {
                isFileImporterPresented = true
              }
            }
          }
        }
        .padding(4)
        .frame(maxWidth: .infinity)
        .fileImporter(isPresented: $isFileImporterPresented, allowedContentTypes: [.folder]) { result in
          let url: URL

          switch result {
            case let .success(x):
              url = x
            case let .failure(error):
              // TODO: Log.
              Logger.ui.error("\(error)")

              return
          }

          Task {
            await settings.setLibraryFolder(url: url)
          }
        }
      }
    }
    .scenePadding()
    .frame(width: 384) // 256 - 512
    .task {
      await settings.load()
    }
  }
}

#Preview {
  @Previewable @State var settings = SettingsModel()

  SettingsView()
    .environment(settings)
}
