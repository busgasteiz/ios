//
//  ContentView.swift
//  BusGasteiz
//
//  Created by Ion Jaureguialzo Sarasola on 14/04/2026.
//

import SwiftUI
import MapKit

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
        .background {
            // MapKit (Metal + MKMapView) tarda ~2 s en inicializarse la primera vez.
            // Este Map invisible fuerza esa inicialización mientras el usuario está
            // en la pestaña Stops, de modo que al cambiar al mapa no hay freezing.
            Map { }
                .frame(width: 1, height: 1)
                .opacity(0.001)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

#Preview {
    ContentView()
        .environment(DataManager.shared)
        .environment(LocationManager())
        .environment(FavoritesManager())
}
