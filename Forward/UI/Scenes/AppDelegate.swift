//
//  AppDelegate.swift
//  Forward
//
//  Created by Kyle Erhabor on 10/3/24.
//

import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
  func applicationWillFinishLaunching(_ notification: Notification) {
    // I'd prefer to keep this enabled, but don't want the user creating multiple instances of the main library.
    NSWindow.allowsAutomaticWindowTabbing = false
  }
}
