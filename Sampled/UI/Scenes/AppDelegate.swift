//
//  AppDelegate.swift
//  Sampled
//
//  Created by Kyle Erhabor on 10/3/24.
//

import AppKit

@Observable
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationWillFinishLaunching(_ notification: Notification) {
    // We don't want the user creating multiple instances of the library.
    NSWindow.allowsAutomaticWindowTabbing = false
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }
}
