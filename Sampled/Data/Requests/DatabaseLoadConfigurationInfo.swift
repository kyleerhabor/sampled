//
//  DatabaseLoadConfigurationInfo.swift
//  Sampled
//
//  Created by Kyle Erhabor on 2/7/26.
//

import GRDB

struct DatabaseLoadConfigurationMainLibraryFileBookmarkBookmarkInfo {
  let bookmark: BookmarkRecord
}

extension DatabaseLoadConfigurationMainLibraryFileBookmarkBookmarkInfo: Decodable, FetchableRecord {}

struct DatabaseLoadConfigurationMainLibraryFileBookmarkInfo {
  let fileBookmark: FileBookmarkRecord
  let bookmark: DatabaseLoadConfigurationMainLibraryFileBookmarkBookmarkInfo
}

extension DatabaseLoadConfigurationMainLibraryFileBookmarkInfo: Decodable {
  enum CodingKeys: String, CodingKey {
    case fileBookmark,
         bookmark = "_bookmark"
  }
}

struct DatabaseLoadConfigurationMainLibraryInfo {
  let library: LibraryRecord
  let fileBookmark: DatabaseLoadConfigurationMainLibraryFileBookmarkInfo
}

extension DatabaseLoadConfigurationMainLibraryInfo: Decodable {
  enum CodingKeys: String, CodingKey {
    case library, fileBookmark
  }
}

extension DatabaseLoadConfigurationMainLibraryInfo: FetchableRecord {}

struct DatabaseLoadConfigurationInfo {
  let configuration: ConfigurationRecord
  let mainLibrary: DatabaseLoadConfigurationMainLibraryInfo
}

extension DatabaseLoadConfigurationInfo: Decodable {
  enum CodingKeys: String, CodingKey {
    case configuration, mainLibrary
  }
}

extension DatabaseLoadConfigurationInfo: FetchableRecord {}
