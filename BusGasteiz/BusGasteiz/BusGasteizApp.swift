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

    init() {
        let config = ModelConfiguration(cloudKitDatabase: .automatic)
        let c = try! ModelContainer(
            for: FavoriteStop.self, FavoriteRoute.self,
            configurations: config
        )
        container = c
        _favoritesManager = State(wrappedValue: FavoritesManager(modelContext: c.mainContext))
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
    }
}
