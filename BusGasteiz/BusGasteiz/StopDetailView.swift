import SwiftUI

// MARK: - Detalle de parada: llegadas previstas

struct StopDetailView: View {

    let stop: StopInfo
    let distance: Double
    var starLeading: Bool = false

    @Environment(DataManager.self)      private var dataManager
    @Environment(FavoritesManager.self) private var favorites

    @State private var arrivals: [UpcomingArrival] = []
    @State private var nextArrivals: [UpcomingArrival] = []
    @State private var lastUpdate: Date?

    private var stopAlerts: [ServiceAlert] {
        dataManager.serviceAlerts.stopAlerts[stop.id] ?? []
    }

    var body: some View {
        Group {
            if arrivals.isEmpty {
                ScrollView {
                    if !stopAlerts.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(stopAlerts) { alert in
                                AlertRowView(alert: alert)
                                    .padding(.horizontal)
                            }
                        }
                        .padding(.top, 16)
                    }

                    ContentUnavailableView(
                        "No Arrivals",
                        systemImage: "clock",
                        description: Text("No scheduled arrivals in the next 60 minutes.")
                    )
                    .padding(.top, stopAlerts.isEmpty ? 60 : 16)

                    if !nextArrivals.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Next scheduled services")
                                .font(.headline)
                                .padding(.horizontal)
                                .padding(.top, 24)
                                .padding(.bottom, 8)

                            ForEach(nextArrivals) { arrival in
                                NavigationLink(value: AppNavDestination.routeArrivals(
                                    stop: stop, distance: distance,
                                    routeShortName: arrival.routeShortName,
                                    routeColor: arrival.routeColor)) {
                                    ArrivalRowView(arrival: arrival)
                                        .padding(.horizontal)
                                }
                                .buttonStyle(.plain)
                                Divider().padding(.leading, 76)
                            }
                        }
                    }
                }
                .refreshable { await refreshAndRecompute() }
            } else {
                List {
                    ForEach(stopAlerts) { alert in
                        AlertRowView(alert: alert)
                            .listRowBackground(Color.red.opacity(0.07))
                    }
                    ForEach(arrivals) { arrival in
                        NavigationLink(value: AppNavDestination.routeArrivals(
                            stop: stop, distance: distance,
                            routeShortName: arrival.routeShortName,
                            routeColor: arrival.routeColor)) {
                            ArrivalRowView(arrival: arrival)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            let isFav = favorites.isRouteFavorite(stopId: stop.id,
                                                                  routeShortName: arrival.routeShortName)
                            Button {
                                favorites.toggleRoute(stopId: stop.id,
                                                      routeShortName: arrival.routeShortName)
                            } label: {
                                Label(isFav ? String(localized: "Remove") : String(localized: "Favorite"),
                                      systemImage: isFav ? "star.slash.fill" : "star.fill")
                            }
                            .tint(isFav ? .gray : .yellow)
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable { await refreshAndRecompute() }
            }
        }
        .navigationTitle(stop.localizedName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(stop.localizedName)
                        .font(.headline)
                    Text(distanceLabel(distance))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
            }
            ToolbarItem(placement: starLeading ? .topBarLeading : .topBarTrailing) {
                let isFav = favorites.isStopFavorite(stop.id)
                Button {
                    favorites.toggleStop(stop.id)
                } label: {
                    Image(systemName: isFav ? "star.fill" : "star")
                        .foregroundStyle(isFav ? .yellow : .primary)
                        .animation(.spring(duration: 0.2), value: isFav)
                }
            }
        }
        .onAppear { recompute() }
        .onChange(of: dataManager.version) { recompute() }
    }

    private func refreshAndRecompute() async {
        // Descargar RT nuevo y recalcular; animación visible al menos 1 segundo.
        async let refresh: () = dataManager.forceRefresh()
        async let minDelay: () = Task.sleep(for: .seconds(1))
        _ = await (refresh, try? minDelay)
        recompute()
    }

    private func recompute() {
        guard let gtfs = dataManager.gtfsData else { return }
        let sid = stop.id
        let dist = distance
        let delays = dataManager.tripDelays
        let alerts = dataManager.serviceAlerts
        Task.detached(priority: .userInitiated) {
            let result = computeArrivals(stopId: sid, distance: dist,
                                         gtfsData: gtfs, delays: delays, alerts: alerts)
            let next = result.isEmpty
                ? computeNextArrivals(stopId: sid, distance: dist,
                                      gtfsData: gtfs, delays: delays, alerts: alerts)
                : []
            await MainActor.run {
                arrivals = result
                nextArrivals = next
                lastUpdate = Date()
            }
        }
    }

    private func distanceLabel(_ d: Double) -> String {
        d < 1000
            ? String(format: String(localized: "%lld m"), Int(d.rounded()))
            : String(format: "%.1f km", d / 1000)
    }
}

// MARK: - Fila de llegada

struct ArrivalRowView: View {
    let arrival: UpcomingArrival
    @State private var now = Date()

    var body: some View {
        HStack(spacing: 12) {
            // Badge de línea cuadrado
            RouteBadgeView(routeShortName: arrival.routeShortName, colorHex: arrival.routeColor,
                           hasAlert: arrival.hasAlert)
                .frame(width: 52)

            // Destino y datos RT
            VStack(alignment: .leading, spacing: 2) {
                Text(arrival.headsign)
                    .font(.body)
                    .lineLimit(1)

                if arrival.isRealTime {
                    if arrival.delaySecs != 0 {
                        Text("Scheduled \(formatTime(arrival.scheduledTime)) • \(delayText)")
                            .font(.caption)
                            .foregroundStyle(arrival.delaySecs > 0 ? .red : .green)
                    } else {
                        Label("Live", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                } else {
                    Label("Scheduled", systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Tiempo restante
            VStack(alignment: .trailing, spacing: 2) {
                Text(timeLabel)
                    .font(.headline)
                    .monospacedDigit()
                Text(formatTime(arrival.predictedTime))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                now = Date()
            }
        }
    }

    private var timeLabel: String {
        let mins = minutesUntil(arrival.predictedTime, from: now)
        switch mins {
        case ..<1:    return String(localized: "Now")
        case 1:       return String(localized: "1 min")
        case ..<60:   return String(format: String(localized: "%lld min"), mins)
        default:
            let h = mins / 60
            let m = mins % 60
            return m == 0
                ? String(format: String(localized: "%lldh"), h)
                : String(format: String(localized: "%lldh %lldm"), h, m)
        }
    }

    private var delayText: String {
        let a = abs(Int(arrival.delaySecs))
        let sign = arrival.delaySecs > 0 ? "+" : "-"
        return a < 60 ? "\(sign)\(a)s" : String(format: "%@%dm%02ds", sign, a / 60, a % 60)
    }
}

// MARK: - Fila de alerta de servicio

struct AlertRowView: View {
    let alert: ServiceAlert

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.title3)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                if !alert.headerText.isEmpty {
                    Text(alert.headerText)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !alert.descriptionText.isEmpty && alert.descriptionText != alert.headerText {
                    Text(alert.descriptionText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Extensión Color desde hex

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: .alphanumerics.inverted)
        guard h.count == 6, let value = UInt64(h, radix: 16) else {
            self = .accentColor; return
        }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8)  & 0xFF) / 255
        let b = Double( value        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Llegadas de una línea concreta en esta parada

struct RouteArrivalsView: View {

    let stop: StopInfo
    let distance: Double
    let routeShortName: String
    let routeColor: String

    @Environment(DataManager.self)      private var dataManager
    @Environment(FavoritesManager.self) private var favorites

    @State private var arrivals: [UpcomingArrival] = []
    @State private var nextArrival: UpcomingArrival?

    private var routeAlerts: [ServiceAlert] {
        guard let gtfs = dataManager.gtfsData else { return [] }
        // Buscar route_id: coincidencia directa o por nombre base (variantes como "5A" -> "5")
        let route = gtfs.routes.values.first(where: { $0.shortName == routeShortName })
            ?? gtfs.routes.values.first(where: {
                $0.shortName == String(routeShortName.prefix(while: { $0.isNumber }))
            })
        guard let routeId = route?.id else { return [] }
        return dataManager.serviceAlerts.routeAlerts[routeId] ?? []
    }

    var body: some View {
        Group {
            if arrivals.isEmpty {
                ScrollView {
                    if !routeAlerts.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(routeAlerts) { alert in
                                AlertRowView(alert: alert)
                                    .padding(.horizontal)
                            }
                        }
                        .padding(.top, 16)
                    }

                    ContentUnavailableView(
                        "No Arrivals",
                        systemImage: "clock",
                        description: Text("No more arrivals of line \(routeShortName) in the next 60 minutes.")
                    )
                    .padding(.top, routeAlerts.isEmpty ? 60 : 16)

                    if let next = nextArrival {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Next scheduled services")
                                .font(.headline)
                                .padding(.horizontal)
                                .padding(.top, 24)
                                .padding(.bottom, 8)

                            ArrivalRowView(arrival: next)
                                .padding(.horizontal)
                        }
                    }
                }
                .refreshable { await refreshAndRecompute() }
            } else {
                List {
                    ForEach(routeAlerts) { alert in
                        AlertRowView(alert: alert)
                            .listRowBackground(Color.red.opacity(0.07))
                    }
                    ForEach(arrivals) { arrival in
                        ArrivalRowView(arrival: arrival)
                    }
                }
                .listStyle(.plain)
                .refreshable { await refreshAndRecompute() }
            }
        }
        .navigationTitle(String(format: String(localized: "Line %@"), routeShortName))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    RouteBadgeView(routeShortName: routeShortName, colorHex: routeColor, outerSize: 34)
                    Text(stop.localizedName)
                        .font(.headline)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                let isFav = favorites.isRouteFavorite(stopId: stop.id, routeShortName: routeShortName)
                Button {
                    favorites.toggleRoute(stopId: stop.id, routeShortName: routeShortName)
                } label: {
                    Image(systemName: isFav ? "star.fill" : "star")
                        .foregroundStyle(isFav ? .yellow : .primary)
                        .animation(.spring(duration: 0.2), value: isFav)
                }
            }
        }
        .onAppear { recompute() }
        .onChange(of: dataManager.version) { recompute() }
    }

    private func refreshAndRecompute() async {
        async let refresh: () = dataManager.forceRefresh()
        async let minDelay: () = Task.sleep(for: .seconds(1))
        _ = await (refresh, try? minDelay)
        recompute()
    }

    private func recompute() {
        guard let gtfs = dataManager.gtfsData else { return }
        let sid = stop.id
        let dist = distance
        let delays = dataManager.tripDelays
        let alerts = dataManager.serviceAlerts
        let route = routeShortName
        Task.detached(priority: .userInitiated) {
            let all = computeArrivals(stopId: sid, distance: dist,
                                      gtfsData: gtfs, delays: delays, alerts: alerts)
            let filtered = all.filter { $0.routeShortName == route }
            let next = filtered.isEmpty
                ? computeNextArrivals(stopId: sid, distance: dist,
                                      gtfsData: gtfs, delays: delays, alerts: alerts)
                    .first { $0.routeShortName == route }
                : nil
            await MainActor.run {
                arrivals = filtered
                nextArrival = next
            }
        }
    }
}
