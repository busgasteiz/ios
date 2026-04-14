//
//  ContentView.swift
//  BusGasteiz
//
//  Created by Ion Jaureguialzo Sarasola on 14/04/2026.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                NearbyStopsView()
            }
            .tabItem {
                Label("Stops", systemImage: "list.bullet")
            }

            NavigationStack {
                BusMapView()
            }
            .tabItem {
                Label("Map", systemImage: "map")
            }

            NavigationStack {
                FavoritesView()
            }
            .tabItem {
                Label("Favorites", systemImage: "star")
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(DataManager.shared)
        .environment(LocationManager())
        .environment(FavoritesManager())
}
