// main.swift
// App entry point. Uses NSApplicationMain to avoid @main conflicts with AppKit.

import AppKit

LegacyMigration.run()   // before AppDelegate creates the stores
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
