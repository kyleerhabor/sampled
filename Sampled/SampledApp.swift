//
//  SampledApp.swift
//  Sampled
//
//  Created by Kyle Erhabor on 5/12/24.
//

import SwiftUI

@main
struct SampledApp: App {
  @NSApplicationDelegateAdaptor private var delegate: AppDelegate
  @Environment(\.locale) private var locale

  var body: some Scene {
    AppScene()
      .onChange(of: locale, setNowPlaying)
  }

  func setNowPlaying() {

  }
}
