//
//  BusGasteizApp.swift
//  BusGasteiz
//
//  Created by Ion Jaureguialzo Sarasola on 14/04/2026.
//

import SwiftUI

@main
struct BusGasteizApp: App {

    @State private var dataManager = DataManager.shared
    @State private var locationManager = LocationManager()
    @State private var favoritesManager = FavoritesManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(dataManager)
                .environment(locationManager)
                .environment(favoritesManager)
                .task {
                    locationManager.requestPermissionIfNeeded()
                }
        }
    }
}
