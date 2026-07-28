//
//  ExSubtitleApp.swift
//  ExSubtitle
//

import SwiftUI

@main
struct ExSubtitleApp: App {
    @StateObject private var subManager = SubtitleManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(subManager)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open .srt file") {
                    NotificationCenter.default.post(name: .openSRTFile, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)

                Divider()

            }
        }

        Settings {
            SettingsView()
        }
    }
}

extension Notification.Name {
    static let openSRTFile = Notification.Name("openSRTFile")
}
