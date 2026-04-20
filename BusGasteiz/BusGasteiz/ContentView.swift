import SwiftUI
import MapKit

// MARK: - Pre-calentamiento de MapKit

/// Crea un MKMapView real (a tamaño de pantalla, con región establecida) y lo
/// mantiene vivo como propiedad estática. Al insertar esta vista en el árbol de
/// SwiftUI al arrancar la app, Metal/MapKit inicializa sus recursos (texturas,
/// shader library, tile pipeline) antes de que el usuario cambie a la pestaña
/// del mapa, eliminando el freeze de ~1 s en la primera apertura.
///
/// Se usa UIViewRepresentable en lugar de `Map {}` porque SwiftUI puede omitir
/// el render pass de vistas con opacity(0)/frame 1×1, mientras que makeUIView()
/// de UIViewRepresentable se llama siempre al insertar la vista en el árbol.
private struct MapKitPrewarm: UIViewRepresentable {

    /// Instancia estática: se crea una sola vez y nunca se libera.
    static let mapView: MKMapView = {
        let frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let m = MKMapView(frame: frame)
        // alpha = 0 en UIKit: la vista sigue procesada por Metal pero no se compone
        // en el framebuffer final, por lo que es invisible para el usuario.
        m.alpha = 0
        // Establecer la región de Vitoria-Gasteiz fuerza la inicialización del
        // tile pipeline al zoom correcto, que es el que usará BusMapView.
        m.setRegion(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: vitoriaCenterCoordinate.latitude,
                                               longitude: vitoriaCenterCoordinate.longitude),
                latitudinalMeters: 1600,
                longitudinalMeters: 1600
            ),
            animated: false
        )
        return m
    }()

    func makeUIView(context: Context) -> MKMapView { Self.mapView }
    func updateUIView(_ uiView: MKMapView, context: Context) {}
}

// MARK: - Toast

private struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 32)
    }
}

// MARK: - Pestañas de la app

private enum AppTab { case stops, map, favorites }

// MARK: - Vista raíz

struct ContentView: View {

    @Environment(LocationManager.self) private var locationManager

    @State private var selectedTab: AppTab = .stops
    @State private var stopsPath = NavigationPath()
    @State private var favoritesPath = NavigationPath()
    @State private var toastMessage: String?
    @State private var toastDismissTask: Task<Void, Never>?

    /// Binding que detecta el toque en la pestaña ya seleccionada y resetea
    /// su pila de navegación al primer nivel.
    private var tabSelection: Binding<AppTab> {
        Binding {
            selectedTab
        } set: { newTab in
            if newTab == selectedTab {
                switch newTab {
                case .stops:     stopsPath     = NavigationPath()
                case .favorites: favoritesPath = NavigationPath()
                case .map:       break
                }
            }
            selectedTab = newTab
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: tabSelection) {
                NavigationStack(path: $stopsPath) {
                    NearbyStopsView()
                }
                .tag(AppTab.stops)
                .tabItem {
                    Label("Stops", systemImage: "list.bullet")
                }

                NavigationStack {
                    BusMapView()
                }
                .tag(AppTab.map)
                .tabItem {
                    Label("Map", systemImage: "map")
                }

                NavigationStack(path: $favoritesPath) {
                    FavoritesView()
                }
                .tag(AppTab.favorites)
                .tabItem {
                    Label("Favorites", systemImage: "star")
                }
            }
            .background {
                // Insertamos el pre-warm en el árbol para que makeUIView() se llame
                // en cuanto aparece ContentView (mientras el usuario ve la pestaña Stops).
                MapKitPrewarm()
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            if let msg = toastMessage {
                ToastView(message: msg)
                    .padding(.bottom, 90)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: toastMessage != nil)
        .onChange(of: locationManager.positionToastMessage) { _, message in
            guard let msg = message else { return }
            locationManager.positionToastMessage = nil
            toastMessage = msg
            toastDismissTask?.cancel()
            toastDismissTask = Task {
                try? await Task.sleep(for: .seconds(3))
                toastMessage = nil
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(DataManager.shared)
        .environment(LocationManager())
        .environment(FavoritesManager())
        .environment(AppSettings())
}
