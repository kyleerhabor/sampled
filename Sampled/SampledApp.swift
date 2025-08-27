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

  var body: some Scene {
    AppScene()
      .defaultAppStorage(.default)
  }
}
