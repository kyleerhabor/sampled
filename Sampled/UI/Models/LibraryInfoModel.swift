//
//  LibraryInfoModel.swift
//  Sampled
//
//  Created by Kyle Erhabor on 8/23/25.
//

import AppKit
import Foundation
import Observation

enum LibraryInfoTrackModelProperty<Value> {
  case empty
  case value(Value)
  case mixed
}

extension LibraryInfoTrackModelProperty: Equatable where Value: Equatable {
  func reduce(nextValue: @autoclosure () -> Value) -> Self {
    switch self {
      case .empty:
        return .value(nextValue())
      case .value(let value):
        if value == nextValue() {
          return self
        }

        return .mixed
      case .mixed:
        return self
    }
  }
}

struct LibraryInfoTrackModelAlbumArtwork {
  let image: NSImage
  let hash: Data
}

extension LibraryInfoTrackModelAlbumArtwork: Equatable {
  static func ==(lhs: Self, rhs: Self) -> Bool {
    lhs.hash == rhs.hash
  }
}

@Observable
@MainActor
class LibraryInfoTrackModel {
  var title: LibraryInfoTrackModelProperty<String?>
  var duration: LibraryInfoTrackModelProperty<Duration>
  var artistName: LibraryInfoTrackModelProperty<String?>
  var albumName: LibraryInfoTrackModelProperty<String?>
  var albumArtistName: LibraryInfoTrackModelProperty<String?>
  var albumDate: LibraryInfoTrackModelProperty<Date?>
  var albumArtwork: LibraryInfoTrackModelProperty<LibraryInfoTrackModelAlbumArtwork?>
  var trackNumber: LibraryInfoTrackModelProperty<Int?>
  var trackTotal: LibraryInfoTrackModelProperty<Int?>
  var discNumber: LibraryInfoTrackModelProperty<Int?>
  var discTotal: LibraryInfoTrackModelProperty<Int?>

  init(
    title: LibraryInfoTrackModelProperty<String?> = .empty,
    duration: LibraryInfoTrackModelProperty<Duration> = .empty,
    artistName: LibraryInfoTrackModelProperty<String?> = .empty,
    albumName: LibraryInfoTrackModelProperty<String?> = .empty,
    albumArtistName: LibraryInfoTrackModelProperty<String?> = .empty,
    albumDate: LibraryInfoTrackModelProperty<Date?> = .empty,
    albumArtwork: LibraryInfoTrackModelProperty<LibraryInfoTrackModelAlbumArtwork?> = .empty,
    trackNumber: LibraryInfoTrackModelProperty<Int?> = .empty,
    trackTotal: LibraryInfoTrackModelProperty<Int?> = .empty,
    discNumber: LibraryInfoTrackModelProperty<Int?> = .empty,
    discTotal: LibraryInfoTrackModelProperty<Int?> = .empty,
  ) {
    self.title = title
    self.artistName = artistName
    self.albumName = albumName
    self.albumArtistName = albumArtistName
    self.albumDate = albumDate
    self.albumArtwork = albumArtwork
    self.trackNumber = trackNumber
    self.trackTotal = trackTotal
    self.discNumber = discNumber
    self.discTotal = discTotal
    self.duration = duration
  }
}
