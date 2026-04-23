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
    @Environment(\.scenePhase) private var scenePhase

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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, dataManager.gtfsData != nil, dataManager.needsRefresh {
                Task { await dataManager.forceRefresh() }
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
