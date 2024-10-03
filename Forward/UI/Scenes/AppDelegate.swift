//
//  AppDelegate.swift
//  Forward
//
//  Created by Kyle Erhabor on 10/3/24.
//

import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }
}
