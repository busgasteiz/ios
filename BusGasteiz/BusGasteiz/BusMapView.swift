import SwiftUI
import MapKit

// MARK: - Mapa de paradas cercanas

struct BusMapView: View {

    @Environment(DataManager.self) private var dataManager
    @Environment(LocationManager.self) private var locationManager
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.colorScheme) private var colorScheme

    @State private var position: MapCameraPosition = .automatic
    @State private var mapInteractionModes: MapInteractionModes = .all
    @State private var nearbyStops: [NearbyStop] = []
    @State private var selectedStopId: String?
    @State private var selectedStop: NearbyStop?
    @State private var showStopSheet = false
    @State private var isLocating = false
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var recomputeTask: Task<Void, Never>?
    /// Evita calcular anotaciones durante la animación de entrada de la pestaña.
    /// Se activa una vez (350 ms después del primer onAppear) y ya no se resetea.
    @State private var isReady = false
    /// Evita que actualizar `appSettings.searchRadius` desde el cambio de cámara
    /// dispare `centerOnUser()` en el `onChange` correspondiente.
    @State private var syncingRadiusFromCamera = false
    /// Indica que el movimiento de cámara actual es programático (centerOnUser).
    /// Mientras esté activo, los cambios de cámara no actualizan el selector de radio.
    @State private var programmaticCameraChange = false

    var body: some View {
        Map(position: $position, interactionModes: mapInteractionModes, selection: $selectedStopId) {
            // Anotaciones de paradas cercanas
            ForEach(nearbyStops) { nearby in
                Annotation(nearby.stop.localizedName, coordinate: nearby.stop.coordinate, anchor: .bottom) {
                    StopAnnotationView(isSelected: selectedStopId == nearby.stop.id,
                                       isTram: nearby.stop.isTram,
                                       hasArrivals: nearby.hasArrivals,
                                       hasAlert: nearby.hasAlert)
                }
                .tag(nearby.stop.id)
            }

            // Posición del usuario
            UserAnnotation()
        }
        .mapStyle(.standard)
        .ignoresSafeArea()
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .overlay {
            switch dataManager.loadState {
            case .idle, .loading:
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.3)
                        .tint(.white)
                    if case .loading(let msg) = dataManager.loadState {
                        Text(msg)
                            .font(.footnote)
                            .foregroundStyle(.white)
                    }
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            case .failed(let msg):
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(msg)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                    Button {
                        Task { await dataManager.forceRefresh() }
                    } label: {
                        Text("Retry")
                            .bold()
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal, 40)
            case .ready:
                EmptyView()
            }
        }
        .navigationTitle("Map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            locationButton
            radiusMenu
            reloadButton
        }
        .sheet(isPresented: $showStopSheet) {
            if let nearby = selectedStop {
                NavigationStack {
                    StopDetailView(stop: nearby.stop, distance: nearby.distance, starLeading: false)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                SheetCloseButton { showStopSheet = false }
                            }
                        }
                        .navigationDestination(for: AppNavDestination.self) { dest in
                            switch dest {
                            case .routeArrivals(let stop, let distance, let routeShortName, let routeColor):
                                RouteArrivalsView(stop: stop, distance: distance,
                                                  routeShortName: routeShortName,
                                                  routeColor: routeColor)
                            default:
                                EmptyView()
                            }
                        }
                }
                .environment(\.colorScheme, colorScheme)
                .preferredColorScheme(colorScheme)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .onChange(of: selectedStopId) { _, newId in
            guard let id = newId,
                  let nearby = nearbyStops.first(where: { $0.id == id }) else { return }
            selectedStop = nearby
            showStopSheet = true
        }
        .onChange(of: showStopSheet) { _, visible in
            if !visible { selectedStopId = nil }
        }
        .onChange(of: dataManager.version) { recompute() }
        .onChange(of: locationManager.locationVersion) { guard isReady else { return }; centerOnUser() }
        .onChange(of: appSettings.searchRadius) {
            guard isReady else { return }
            if syncingRadiusFromCamera {
                syncingRadiusFromCamera = false
                return
            }
            centerOnUser()
        }
        .onMapCameraChange(frequency: .continuous) { context in
            visibleRegion = context.region
            locationManager.activePosition = CLLocation(
                latitude: context.region.center.latitude,
                longitude: context.region.center.longitude
            )
            guard isReady else { return }
            if !programmaticCameraChange {
                let inferred = inferSearchRadius(from: context.region)
                if inferred != appSettings.searchRadius {
                    syncingRadiusFromCamera = true
                    appSettings.searchRadius = inferred
                }
            }
            recompute()
        }
        .onAppear {
            if dataManager.gtfsData == nil {
                Task { await dataManager.refreshIfNeeded() }
            }
            guard !isReady else { return }
            // Centrado inicial: posicionamiento síncrono sin animación.
            // No se usa centerOnUser() aquí porque sus Tasks asíncronos
            // extienden la animación de cámara a lo largo de varios frames de
            // render, lo que produce un parpadeo si el usuario cambia de pestaña
            // durante los primeros ~300 ms tras abrir el mapa por primera vez.
            let initialRegion = MKCoordinateRegion(
                center: locationManager.activePosition.coordinate,
                latitudinalMeters: appSettings.searchRadius * 4,
                longitudinalMeters: appSettings.searchRadius * 4
            )
            withAnimation(.none) { position = .region(initialRegion) }
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                isReady = true
                recompute()
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var locationButton: some ToolbarContent {
        if #available(iOS 26, *) {
            ToolbarItem(placement: .topBarTrailing) {
                locationButtonContent
            }
        } else {
            ToolbarItem(placement: .topBarLeading) {
                locationButtonContent
            }
        }
    }

    @ViewBuilder
    private var locationButtonContent: some View {
        Button {
            Task {
                isLocating = true
                async let minDelay: () = Task.sleep(for: .seconds(1))
                locationManager.resolveActivePosition()
                centerOnUser()
                _ = try? await minDelay
                isLocating = false
            }
        } label: {
            if isLocating {
                ProgressView()
            } else {
                Image(systemName: "location.fill")
            }
        }
        .disabled(isLocating)
    }

    @ToolbarContentBuilder
    private var radiusMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                ForEach([100.0, 200.0, 300.0, 500.0, 1000.0], id: \.self) { r in
                    Button {
                        appSettings.searchRadius = r
                        recompute()
                    } label: {
                        if r == appSettings.searchRadius {
                            Label("\(Int(r)) m", systemImage: "checkmark")
                        } else {
                            Text("\(Int(r)) m")
                        }
                    }
                }
            } label: {
                Text("\(Int(appSettings.searchRadius)) m")
            }
        }
    }

    @ToolbarContentBuilder
    private var reloadButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await dataManager.forceRefresh() }
            } label: {
                if dataManager.isRefreshing {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(dataManager.isRefreshing)
        }
    }

    // MARK: Helpers

    /// Devuelve el valor de radio más cercano a los predefinidos a partir del span visible del mapa.
    /// La región se establece siempre como `radio * 4` en `centerOnUser()`, por lo que
    /// el radio estimado es `latitudinalMeters / 4`.
    private func inferSearchRadius(from region: MKCoordinateRegion) -> Double {
        let presets = [100.0, 200.0, 300.0, 500.0, 1000.0]
        let latMeters = region.span.latitudeDelta * 111_000
        let estimated = latMeters / 4
        return presets.min(by: { abs($0 - estimated) < abs($1 - estimated) }) ?? 200
    }

    private func centerOnUser() {
        programmaticCameraChange = true
        let coord = locationManager.activePosition.coordinate
        let region = MKCoordinateRegion(
            center: coord,
            latitudinalMeters: appSettings.searchRadius * 4,
            longitudinalMeters: appSettings.searchRadius * 4
        )
        // En iOS 26 el binding MapCameraPosition no interrumpe un gesto activo:
        // la actualización se aplaza hasta que el gesto termina.
        // Desactivar la interacción brevemente fuerza la cancelación del gesto
        // antes de aplicar la nueva posición, lo que permite centrar el mapa
        // de forma inmediata aunque el usuario esté haciendo scroll.
        mapInteractionModes = []
        Task { @MainActor in
            position = .region(region)
            Task { @MainActor in
                mapInteractionModes = .all
                // Mantener el flag activo hasta que la animación de cámara concluya.
                // La duración estándar de MapKit es ~0,3 s; 1,2 s da margen suficiente.
                try? await Task.sleep(for: .milliseconds(1200))
                programmaticCameraChange = false
            }
        }
    }

    private func recompute() {
        guard let gtfs = dataManager.gtfsData,
              let region = visibleRegion else { return }

        let halfLat = region.span.latitudeDelta / 2
        let halfLon = region.span.longitudeDelta / 2
        let minLat = region.center.latitude  - halfLat
        let maxLat = region.center.latitude  + halfLat
        let minLon = region.center.longitude - halfLon
        let maxLon = region.center.longitude + halfLon

        let refLat: Double
        let refLon: Double
        if let loc = locationManager.location {
            refLat = loc.coordinate.latitude
            refLon = loc.coordinate.longitude
        } else {
            refLat = vitoriaCenterCoordinate.latitude
            refLon = vitoriaCenterCoordinate.longitude
        }

        recomputeTask?.cancel()
        let activeIds = dataManager.activeStopIds
        let alerts = dataManager.serviceAlerts
        recomputeTask = Task.detached(priority: .userInitiated) {
            let stops = computeStopsInBounds(
                minLat: minLat, maxLat: maxLat,
                minLon: minLon, maxLon: maxLon,
                refLat: refLat, refLon: refLon,
                gtfsData: gtfs,
                activeStopIds: activeIds,
                alerts: alerts
            )
            guard !Task.isCancelled else { return }
            await MainActor.run { nearbyStops = stops }
        }
    }
}

// MARK: - Vista de anotación en el mapa

struct StopAnnotationView: View {
    let isSelected: Bool
    var isTram: Bool = false
    var hasArrivals: Bool = true
    var hasAlert: Bool = false

    private var size: CGFloat { isSelected ? 30 : 24 }

    var body: some View {
        StopIconView(isTram: isTram, size: size, hasArrivals: hasArrivals, hasAlert: hasAlert)
            .animation(.spring(duration: 0.2), value: isSelected)
    }
}
