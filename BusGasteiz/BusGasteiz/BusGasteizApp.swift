//
//  BusGasteizApp.swift
//  BusGasteiz
//
//  Created by Ion Jaureguialzo Sarasola on 14/04/2026.
//

import SwiftUI

@main
struct BusGasteizApp: App {

    @State private var favoritesManager = FavoritesManager()
    @State private var dataManager = DataManager.shared
    @State private var locationManager = LocationManager()
    @State private var appSettings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(dataManager)
                .environment(locationManager)
                .environment(favoritesManager)
                .environment(appSettings)
                .task {
                    locationManager.requestPermissionIfNeeded()
                }
        }
        .commands {
            CommandGroup(replacing: .appVisibility) { }
            CommandGroup(after: .sidebar) {
                Button("Actualizar datos") {
                    Task { await dataManager.forceRefresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}
