//
//  LibraryAlbumArtworkImageView.swift
//  Sampled
//
//  Created by Kyle Erhabor on 9/1/25.
//

import SwiftUI

struct LibraryAlbumArtworkImageView: View {
  let image: NSImage?

  var body: some View {
    Image(nsImage: image ?? NSImage())
      .resizable()
      .scaledToFill()
      .clipShape(.rect(cornerRadius: 2))
  }
}

#Preview {
  LibraryAlbumArtworkImageView(image: nil)
}
