//
//  LibraryImageView.swift
//  Sampled
//
//  Created by Kyle Erhabor on 8/31/25.
//

import OSLog
import SwiftUI

private struct LibraryImageID<ID> where ID: Equatable {
  let id: ID
  let length: Double
}

extension LibraryImageID: Equatable {}

struct LibraryImageView<ID>: View where ID: Equatable {
  typealias Action = (Double) async -> NSImage?

  @Environment(\.pixelLength) private var pixelLength
  @State private var image: NSImage?
  private let id: ID
  private let action: Action

  var body: some View {
    LibraryAlbumArtworkImageView(image: image)
      .background {
        GeometryReader { proxy in
          Color.clear
            .task(id: LibraryImageID(id: id, length: length(proxy: proxy))) {
              // I tried using Image I/O for this, but it would always fail with a cryptic error like this:
              //
              //   CGImageSourceCreateThumbnailAtIndex:5176: *** ERROR: CGImageSourceCreateThumbnailAtIndex[0] - 'n/a ' - failed to create thumbnail [-50] {alw:1, abs: -1 tra:-1 max:64}
              //
              // There's no way we're encoding the CGImage so Image I/O can decode and resample it, so libswscale it is.

              let length = length(proxy: proxy)

              guard length != 0 else {
                return
              }

              image = await action(length)
            }
        }
    }
  }

  init(id: ID, action: @escaping Action) {
    self.id = id
    self.action = action
  }

  func length(proxy: GeometryProxy) -> Double {
    proxy.size.length / pixelLength
  }
}
