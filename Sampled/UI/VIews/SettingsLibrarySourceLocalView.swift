//
//  SettingsLibrarySourceLocalView.swift
//  Sampled
//
//  Created by Kyle Erhabor on 5/6/26.
//

import OSLog
import SwiftUI
import UniformTypeIdentifiers

let localLibraryLocationContentTypes: [UTType] = [.folder]

@Observable
@MainActor
class SettingsLibrarySourceLocalLibraryModel {
  var url: URL?

  init(url: URL?) {
    self.url = url
  }
}

struct SettingsLibrarySourceLocalView: View {
  @Environment(SettingsModel.self) private var settings
  @Environment(\.dismiss) private var dismiss
  @AppStorage(StorageKeys.libraryFolder) private var libraryFolder
  @State private var isFileImporterActive = false
  let library: SettingsLibrarySourceLocalLibraryModel

  var body: some View {
    Form {
      LabeledContent("Settings.General.LibrarySource.Local.Location") {
        Text(self.library.url?.pathString, default: "Settings.General.LibrarySource.Local.Location.None")
          .monospaced(self.library.url != nil)
      }

      Button {
        self.isFileImporterActive = true
      } label: {
        Text(verbatim: "Set...")
      }
      .fileImporter(
        isPresented: $isFileImporterActive,
        allowedContentTypes: localLibraryLocationContentTypes,
      ) { result in
        let url: URL

        switch result {
          case let .success(x):
            url = x
          case let .failure(error):
            Logger.ui.error("\(error)")

            return
        }

        self.library.url = url
      }
    }
    .formStyle(.grouped)
    .presentationSizing(.fitted)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Settings.General.LibrarySource.Local.Cancel", role: .cancel) {
          self.dismiss()
        }
      }

      ToolbarItem(placement: .confirmationAction) {
        Button("Settings.General.LibrarySource.Local.Save") {
          // TODO: Implement.
        }
      }
    }

//    LabeledContent {
//      Button {
//        self.isFileImporterPresented = true
//      } label: {
//        Text(verbatim: "Set Folder...")
//      }
//      .fileImporter(
//        isPresented: $isFileImporterPresented,
//        allowedContentTypes: localLibraryFolderContentTypes,
//      ) { result in
//        let url: URL
//
//        switch result {
//          case let .success(x):
//            url = x
//          case let .failure(error):
//            // TODO: Log.
//            Logger.ui.error("\(error)")
//
//            return
//        }
//
//        Task {
//          await settings.setLibraryFolder(url: url)
//        }
//      }
//
//      if self.libraryFolder != .file {
//        Text(self.libraryFolder.pathString)
//          .monospaced()
////          .fixedSize(horizontal: false, vertical: true)
//      }
//    } label: {
//      Text(verbatim: "On My Mac:")
//    }

//    GroupBox("Settings.Item.LibraryFolder.Title") {
//      Group {
//        if self.libraryFolder != .file {
//          Text(self.libraryFolder.pathString)
//            .monospaced()
//          
//          HStack {
//            Spacer()
//            
//            Button("Settings.Item.LibraryFolder.Change") {
//              self.isFileImporterPresented = true
//            }
//          }
//        } else {
//          ContentUnavailableView {
//            Text("Settings.Item.LibraryFolder.Unavailable")
//          } actions: {
//            Button("Settings.Item.LibraryFolder.Unavailable.Action.Set") {
//              self.isFileImporterPresented = true
//            }
//          }
//        }
//      }
//      .padding(4)
//      .frame(maxWidth: .infinity)
//      .fileImporter(isPresented: $isFileImporterPresented, allowedContentTypes: [.folder]) { result in
//        let url: URL
//        
//        switch result {
//          case let .success(x):
//            url = x
//          case let .failure(error):
//            // TODO: Log.
//            Logger.ui.error("\(error)")
//            
//            return
//        }
//        
//        Task {
//          await settings.setLibraryFolder(url: url)
//        }
//      }
//    }
  }
}
