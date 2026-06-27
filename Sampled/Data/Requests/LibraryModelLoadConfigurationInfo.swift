//
//  LibraryModelLoadConfigurationInfo.swift
//  Sampled
//
//  Created by Kyle Erhabor on 2/7/26.
//

import Foundation
import GRDB

struct LibraryModelLoadConfigurationMainLibraryFileBookmarkBookmarkInfo {
  let bookmark: BookmarkRecord
}

extension LibraryModelLoadConfigurationMainLibraryFileBookmarkBookmarkInfo: Decodable, FetchableRecord {}

struct LibraryModelLoadConfigurationMainLibraryFileBookmarkInfo {
  let fileBookmark: FileBookmarkRecord
  let bookmark: LibraryModelLoadConfigurationMainLibraryFileBookmarkBookmarkInfo
}

extension LibraryModelLoadConfigurationMainLibraryFileBookmarkInfo: Decodable {
  enum CodingKeys: String, CodingKey {
    case fileBookmark,
         bookmark = "_bookmark"
  }
}

struct LibraryModelLoadConfigurationMainLibraryCurrentQueueItemTrackInfo {
  let track: LibraryTrackRecord
}

extension LibraryModelLoadConfigurationMainLibraryCurrentQueueItemTrackInfo: Decodable, FetchableRecord {}

struct LibraryModelLoadConfigurationMainLibraryCurrentQueueItemInfo {
  let item: LibraryQueueItemRecord
  let track: LibraryModelLoadConfigurationMainLibraryCurrentQueueItemTrackInfo
}

extension LibraryModelLoadConfigurationMainLibraryCurrentQueueItemInfo: Decodable {
  enum CodingKeys: String, CodingKey {
    case item,
         track = "_track"
  }
}

extension LibraryModelLoadConfigurationMainLibraryCurrentQueueItemInfo: FetchableRecord {}

struct LibraryModelLoadConfigurationMainLibraryCurrentQueueInfo {
  let queue: LibraryQueueRecord
  let items: [LibraryModelLoadConfigurationMainLibraryCurrentQueueItemInfo]
}

extension LibraryModelLoadConfigurationMainLibraryCurrentQueueInfo: Decodable {
  enum CodingKeys: String, CodingKey {
    case queue, items
  }
}

extension LibraryModelLoadConfigurationMainLibraryCurrentQueueInfo: FetchableRecord {}

struct LibraryModelLoadConfigurationMainLibraryTrackFileBookmarkBookmarkInfo {
  let bookmark: BookmarkRecord
}

extension LibraryModelLoadConfigurationMainLibraryTrackFileBookmarkBookmarkInfo: Decodable, FetchableRecord {}

struct LibraryModelLoadConfigurationMainLibraryTrackFileBookmarkInfo {
  let fileBookmark: FileBookmarkRecord
  let bookmark: LibraryModelLoadConfigurationMainLibraryTrackFileBookmarkBookmarkInfo
}

extension LibraryModelLoadConfigurationMainLibraryTrackFileBookmarkInfo: Decodable {
  enum CodingKeys: String, CodingKey {
    case fileBookmark,
         bookmark = "_bookmark"
  }
}

extension LibraryModelLoadConfigurationMainLibraryTrackFileBookmarkInfo: FetchableRecord {}

struct LibraryModelLoadConfigurationMainLibraryTrackAlbumArtworkInfo {
  let albumArtwork: LibraryTrackAlbumArtworkRecord
}

extension LibraryModelLoadConfigurationMainLibraryTrackAlbumArtworkInfo: Decodable, FetchableRecord {}

struct LibraryModelLoadConfigurationMainLibraryTrackInfo {
  let track: LibraryTrackRecord
  let fileBookmark: LibraryModelLoadConfigurationMainLibraryTrackFileBookmarkInfo
  let albumArtwork: LibraryModelLoadConfigurationMainLibraryTrackAlbumArtworkInfo?
}

extension LibraryModelLoadConfigurationMainLibraryTrackInfo: Decodable {
  enum CodingKeys: String, CodingKey {
    case track, fileBookmark, albumArtwork
  }
}

extension LibraryModelLoadConfigurationMainLibraryTrackInfo: FetchableRecord {}

struct LibraryModelLoadConfigurationMainLibraryInfo {
  let library: LibraryRecord
  let fileBookmark: LibraryModelLoadConfigurationMainLibraryFileBookmarkInfo
  let currentQueue: LibraryModelLoadConfigurationMainLibraryCurrentQueueInfo?
  let tracks: [LibraryModelLoadConfigurationMainLibraryTrackInfo]
}

extension LibraryModelLoadConfigurationMainLibraryInfo: Decodable {
  enum CodingKeys: String, CodingKey {
    case library, fileBookmark, currentQueue, tracks
  }
}

extension LibraryModelLoadConfigurationMainLibraryInfo: FetchableRecord {}

struct LibraryModelLoadConfigurationInfo {
  let configuration: ConfigurationRecord
  let mainLibrary: LibraryModelLoadConfigurationMainLibraryInfo
}

extension LibraryModelLoadConfigurationInfo: Decodable {
  enum CodingKeys: String, CodingKey {
    case configuration, mainLibrary
  }
}

extension LibraryModelLoadConfigurationInfo: FetchableRecord {}
