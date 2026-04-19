//
//  BusGasteizApp.swift
//  BusGasteiz
//
//  Created by Ion Jaureguialzo Sarasola on 14/04/2026.
//

import SwiftUI
import SwiftData

@main
struct BusGasteizApp: App {

    let container: ModelContainer
    @State private var favoritesManager: FavoritesManager
    @State private var dataManager = DataManager.shared
    @State private var locationManager = LocationManager()
    @State private var appSettings = AppSettings()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let config = ModelConfiguration(cloudKitDatabase: .automatic)
        let c = try! ModelContainer(
            for: FavoriteStop.self, FavoriteRoute.self,
            configurations: config
        )
        container = c
        _favoritesManager = State(wrappedValue: FavoritesManager(modelContext: c.mainContext, container: c))
    }

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
            if phase == .active {
                favoritesManager.startForegroundPolling()
            } else {
                favoritesManager.stopForegroundPolling()
            }
        }
    }
}
