//
//  UI+Model.swift
//  Sampled
//
//  Created by Kyle Erhabor on 8/19/25.
//

import CFFmpeg
import CryptoKit
import Foundation

// In Info structs, CodingKeys with a prefixed string value are there to disambiguate it from the returned rows when
// decoding.

func hash(data: some DataProtocol) -> Data {
  Data(SHA256.hash(data: data))
}

extension LibraryTrackAlbumArtworkFormat {
  init?(codecID: AVCodecID) {
    switch codecID {
      case .png: self = .png
      case .mjpeg: self = .jpeg
      default: return nil
    }
  }

  var codecID: AVCodecID {
    switch self {
      case .png: .png
      case .jpeg: .mjpeg
    }
  }
}
