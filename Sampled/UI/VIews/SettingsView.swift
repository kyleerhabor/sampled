//
//  SettingsView.swift
//  Sampled
//
//  Created by Kyle Erhabor on 10/18/24.
//

import OSLog
import SwiftUI

struct SettingsGroupBoxStyle: GroupBoxStyle {
  func makeBody(configuration: Configuration) -> some View {
    VStack(alignment: .leading, spacing: 6) { // 2^2 + 2^1
      configuration.content
    }
  }
}

extension GroupBoxStyle where Self == SettingsGroupBoxStyle {
  static var settings: SettingsGroupBoxStyle {
    SettingsGroupBoxStyle()
  }
}

struct SettingsLabeledGroupBoxStyle: GroupBoxStyle {
  func makeBody(configuration: Configuration) -> some View {
    VStack(alignment: .leading, spacing: 6) { // 2^2 + 2^1
      configuration.label

      configuration.content
        .padding(.leading)
    }
  }
}

extension GroupBoxStyle where Self == SettingsLabeledGroupBoxStyle {
  static var settingsLabeled: SettingsLabeledGroupBoxStyle {
    SettingsLabeledGroupBoxStyle()
  }
}

struct SettingsLabeledContentStyle: LabeledContentStyle {
  let width: CGFloat

  func makeBody(configuration: Configuration) -> some View {
    // There's probably a better way to model this, but we want all tabs to share the same alignment.
    GridRow(alignment: .firstTextBaseline) {
      Color.clear
        .frame(maxWidth: .infinity, maxHeight: 0)

      configuration.label
        .frame(width: self.width * 0.35, alignment: .trailing)

      VStack(alignment: .leading) {
        configuration.content
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(width: self.width * 0.65, alignment: .leading)

      Color.clear
        .frame(maxWidth: .infinity, maxHeight: 0)
    }
  }
}

extension LabeledContentStyle where Self == SettingsLabeledContentStyle {
  static func settings(width: CGFloat) -> some LabeledContentStyle {
    SettingsLabeledContentStyle(width: width)
  }
}

struct SettingsFormStyle: FormStyle {
  let width: CGFloat

  func makeBody(configuration: Configuration) -> some View {
    Grid {
      configuration.content
        .labeledContentStyle(.settings(width: self.width))
    }
  }
}

extension FormStyle where Self == SettingsFormStyle {
  static func settings(width: CGFloat) -> some FormStyle {
    SettingsFormStyle(width: width)
  }
}

struct SettingsView: View {
  static let windowWidth: CGFloat = 600
  static let contentWidth: CGFloat = 400
  static let pickerWidth: CGFloat = 165
  // TODO: Extract and rename.
  nonisolated static let openSubsonicAPIKey = "\(Bundle.appID).OpenSubsonicAPIKey"
  nonisolated static let openSubsonicLogin = "\(Bundle.appID).OpenSubsonicLogin"

  @AppStorage(StorageKeys.appearance) private var appearance
  @AppStorage(StorageKeys.librarySource) private var librarySource
  @AppStorage(StorageKeys.librarySourceOpenSubsonicLocation) private var librarySourceOpenSubsonicLocation
  @AppStorage(StorageKeys.librarySourceOpenSubsonicAuthenticationMethod) private var librarySourceOpenSubsonicAuthenticationMethod
  @State private var isLibrarySourceSheetPresented = false
  @State private var localLibrary = SettingsLibrarySourceLocalLibraryModel(url: nil)
  @State private var openSubsonicLibrary = SettingsOpenSubsonicLibraryModel(
    location: "",
    authenticationMethod: .none,
    apiKey: "",
    username: "",
    password: "",
  )

  var body: some View {
    Form {
      LabeledContent("Settings.General.Appearance") {
        Picker("Settings.General.Appearance.Use", selection: $appearance) {
          Section {
            Text("Settings.General.Appearance.Use.System")
              .tag(StorageAppearance.automatic, includeOptional: false)
          }

          Section {
            Text("Settings.General.Appearance.Use.Light")
              .tag(StorageAppearance.light, includeOptional: false)

            Text("Settings.General.Appearance.Use.Dark")
              .tag(StorageAppearance.dark, includeOptional: false)
          }
        }
        .labelsHidden()
        .frame(width: SettingsView.pickerWidth)
        .onChange(of: self.appearance) {
          NSApp.appearance = self.appearance.appearance
        }
      }

      LabeledContent("Settings.General.LibrarySource") {
        HStack(alignment: .firstTextBaseline) {
          Picker("Settings.General.LibrarySource.Use", selection: $librarySource) {
            Section {
              Text("Settings.General.LibrarySource.Use.None")
                .tag(StorageLibrarySource.none, includeOptional: false)
            }
            
            Section {
              Text("Settings.General.LibrarySource.Use.OnMyMac")
                .tag(StorageLibrarySource.local, includeOptional: false)
              
              Text("Settings.General.LibrarySource.Use.OpenSubsonic")
                .tag(StorageLibrarySource.openSubsonic, includeOptional: false)
            }
          }
          .labelsHidden()
          .frame(width: Self.pickerWidth)
          
          Button("Settings.General.LibrarySource.Manage") {
            Task {
              switch self.librarySource {
                case .none:
                  unreachable()
                case .local:
                  // TODO: Fetch folder URL from database.
                  self.localLibrary.url = nil
                case .openSubsonic:
                  // TODO: Rename.
                  guard let x = await perform() else {
                    return
                  }

                  self.openSubsonicLibrary.apiKey = x.apiKey
                  self.openSubsonicLibrary.username = x.username
                  self.openSubsonicLibrary.password = x.password
                  self.openSubsonicLibrary.location = self.librarySourceOpenSubsonicLocation
                  self.openSubsonicLibrary.authenticationMethod = self.librarySourceOpenSubsonicAuthenticationMethod
              }

              self.isLibrarySourceSheetPresented = true
            }
          }
          .buttonStyle(.accessory)
          .disabled(self.librarySource == .none)
          .sheet(isPresented: $isLibrarySourceSheetPresented) {
            switch self.librarySource {
              case .none:
                unreachable()
              case .local:
                SettingsLibrarySourceLocalView(library: self.localLibrary)
              case .openSubsonic:
                SettingsOpenSubsonicView(library: self.openSubsonicLibrary)
            }
          }
        }
      }
    }
    .formStyle(.settings(width: Self.contentWidth))
    .scenePadding()
    .frame(width: Self.windowWidth)
  }

  // TODO: Rename.
  struct X {
    let apiKey: String
    let username: String
    let password: String
  }

  nonisolated func perform() async -> X? {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecMatchLimit: kSecMatchLimitAll,
      kSecUseDataProtectionKeychain: true,
      kSecReturnData: true,
      kSecReturnAttributes: true,
    ]

    var result: AnyObject!
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess else {
      Logger.ui.error("\(status)")

      return nil
    }

    let items = result as! [[CFString: Any]]
    var apiKey = ""
    var username = ""
    var password = ""

    items.forEach { item in
      guard let service = item[kSecAttrService] else {
        return
      }

      switch service as! String {
        case Self.openSubsonicAPIKey:
          guard let valueData = item[kSecValueData] else {
            return
          }

          guard let dataString = String(data: valueData as! Data, encoding: .utf8) else {
            return
          }

          apiKey = dataString
        case Self.openSubsonicLogin:
          guard let account = item[kSecAttrAccount],
                let valueData = item[kSecValueData] else {
            return
          }

          guard let dataString = String(data: valueData as! Data, encoding: .utf8) else {
            return

          }

          username = account as! String
          password = dataString
        default:
          break
      }
    }

    let x = X(apiKey: apiKey, username: username, password: password)

    return x
  }
}

#Preview {
  @Previewable @State var settings = SettingsModel()

  SettingsView()
    .environment(settings)
}
