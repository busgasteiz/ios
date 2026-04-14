import Foundation
import Observation

// MARK: - DataManager

@Observable @MainActor
final class DataManager {

    // MARK: Estado de carga

    enum LoadState: Equatable {
        case idle
        case loading(String)
        case ready
        case failed(String)
    }

    static let shared = DataManager()

    var loadState: LoadState = .idle
    var gtfsData: GTFSData?
    var tripDelays: [String: TripDelayInfo] = [:]
    var lastRefresh: Date?
    /// Se incrementa con cada recarga; útil para `onChange` en vistas.
    private(set) var version: Int = 0

    private let maxAge: TimeInterval = 10 * 60   // 10 minutos

    // MARK: Rutas de caché

    private var cacheDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GTFSCache")
    }

    private var gtfsDir: URL { cacheDir.appendingPathComponent("GTFS_Data") }
    private var pbURL: URL { cacheDir.appendingPathComponent("tripUpdates.pb") }
    private var euskotrenGtfsDir: URL { cacheDir.appendingPathComponent("Euskotren_Data") }
    private var euskotrenPbURL: URL { cacheDir.appendingPathComponent("euskotrenTripUpdates.pb") }

    // MARK: Init

    init() {
        let modDate = (try? FileManager.default.attributesOfItem(atPath: pbURL.path))?[.modificationDate] as? Date
        lastRefresh = modDate
    }

    // MARK: API pública

    var needsRefresh: Bool {
        guard let last = lastRefresh else { return true }
        return Date().timeIntervalSince(last) > maxAge
    }

    func refreshIfNeeded() async {
        guard needsRefresh || gtfsData == nil else { return }
        await performRefresh()
    }

    func forceRefresh() async {
        await performRefresh()
    }

    // MARK: Lógica interna

    private func performRefresh() async {
        if case .loading = loadState { return }

        // Si no hay datos aún, mostrar spinner de carga completo.
        // Si ya hay datos, mantenemos .ready para no destruir la vista activa
        // (destruirla cancela el task del .refreshable y corta la descarga).
        let hasData = gtfsData != nil

        do {
            print("[DataManager] Iniciando refresco…")
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

            // Datos GTFS estáticos Tuvisa: descargar solo si no están frescos
            if !isGTFSFresh() {
                if !hasData { loadState = .loading("Descargando datos GTFS…") }
                print("[DataManager] Descargando GTFS ZIP Tuvisa…")
                let zipData = try await downloadData(
                    from: "https://www.vitoria-gasteiz.org/we001/http/vgTransit/google_transit.zip"
                )
                print("[DataManager] ZIP descargado: \(zipData.count) bytes")

                if !hasData { loadState = .loading("Descomprimiendo datos GTFS…") }
                try await extractZip(zipData: zipData, to: gtfsDir)
                print("[DataManager] ZIP descomprimido")
            } else {
                print("[DataManager] GTFS Tuvisa en caché y vigente, omitiendo descarga")
            }

            // Datos GTFS estáticos Euskotren: descargar solo si no están frescos
            if !isEuskoTranFresh() {
                if !hasData { loadState = .loading("Descargando datos tranvía…") }
                print("[DataManager] Descargando GTFS ZIP Euskotren…")
                let tramZipData = try await downloadData(
                    from: "https://opendata.euskadi.eus/transport/moveuskadi/euskotren/gtfs_euskotren.zip"
                )
                print("[DataManager] ZIP Euskotren descargado: \(tramZipData.count) bytes")

                if !hasData { loadState = .loading("Descomprimiendo datos tranvía…") }
                try await extractZip(zipData: tramZipData, to: euskotrenGtfsDir)
                print("[DataManager] ZIP Euskotren descomprimido")
            } else {
                print("[DataManager] GTFS Euskotren en caché y vigente, omitiendo descarga")
            }

            // Feed RT Tuvisa: siempre actualizar
            if !hasData { loadState = .loading("Descargando datos en tiempo real…") }
            print("[DataManager] Descargando feed RT Tuvisa…")
            let pbData = try await downloadData(
                from: "https://www.vitoria-gasteiz.org/we001/http/vgTransit/realTime/tripUpdates.pb"
            )
            print("[DataManager] Feed RT Tuvisa descargado: \(pbData.count) bytes")
            try pbData.write(to: pbURL)

            // Feed RT Euskotren: siempre actualizar
            print("[DataManager] Descargando feed RT Euskotren…")
            let euskotrenPbData = try await downloadData(
                from: "https://opendata.euskadi.eus/transport/moveuskadi/euskotren/gtfsrt_euskotren_trip_updates.pb"
            )
            print("[DataManager] Feed RT Euskotren descargado: \(euskotrenPbData.count) bytes")
            try euskotrenPbData.write(to: euskotrenPbURL)

            // Parsear en background
            if !hasData { loadState = .loading("Procesando datos…") }
            let (parsed, delays) = await parseInBackground()
            print("[DataManager] Datos parseados: \(parsed.stops.count) paradas (\(parsed.stops.values.filter(\.isTram).count) tranvía), \(delays.count) trips RT")

            gtfsData = parsed
            tripDelays = delays
            lastRefresh = Date()
            version += 1
            loadState = .ready
            print("[DataManager] Listo")

        } catch {
            print("[DataManager] ERROR: \(error)")
            // Si ya hay datos cargados, mantenerlos y solo marcar el error de refresh
            if gtfsData != nil {
                loadState = .ready
            } else {
                // Intentar cargar desde caché existente aunque sea antigua
                if let cached = await tryLoadFromCache() {
                    gtfsData = cached.gtfs
                    tripDelays = cached.delays
                    version += 1
                    loadState = .ready
                    print("[DataManager] Cargado desde caché")
                } else {
                    loadState = .failed(error.localizedDescription)
                    print("[DataManager] Sin caché disponible")
                }
            }
        }
    }

    private func isGTFSFresh() -> Bool {
        let stopsFile = gtfsDir.appendingPathComponent("stops.txt")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: stopsFile.path),
              let mod = attrs[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(mod) < maxAge
    }

    private func isEuskoTranFresh() -> Bool {
        let stopsFile = euskotrenGtfsDir.appendingPathComponent("stops.txt")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: stopsFile.path),
              let mod = attrs[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(mod) < maxAge
    }

    private func downloadData(from urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func extractZip(zipData: Data, to dir: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            if FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.removeItem(at: dir)
            }
            try ZIPExtractor.extract(zipData: zipData, to: dir)
        }.value
    }

    private func parseInBackground() async -> (GTFSData, [String: TripDelayInfo]) {
        let folder = gtfsDir.path
        let pbPath = pbURL.path
        let tramFolder = euskotrenGtfsDir.path
        let tramPbPath = euskotrenPbURL.path
        return await Task.detached(priority: .userInitiated) {
            var gtfs = loadGTFS(folder: folder)
            let tramGtfs = loadEuskoTranGTFS(folder: tramFolder)
            // Fusionar datos del tranvía en el GTFS principal
            for (id, stop)     in tramGtfs.stops    { gtfs.stops[id] = stop }
            for (id, trip)     in tramGtfs.trips    { gtfs.trips[id] = trip }
            for (id, route)    in tramGtfs.routes   { gtfs.routes[id] = route }
            for (id, arrivals) in tramGtfs.stopArrivals {
                gtfs.stopArrivals[id, default: []] += arrivals
            }
            for (date, svcIds) in tramGtfs.activeDates {
                gtfs.activeDates[date, default: []].formUnion(svcIds)
            }

            var delays: [String: TripDelayInfo] = [:]
            if let data = FileManager.default.contents(atPath: pbPath) {
                delays = loadTripDelays(data: data)
            }
            if let tramData = FileManager.default.contents(atPath: tramPbPath) {
                let tramDelays = loadTripDelays(data: tramData)
                delays.merge(tramDelays) { _, new in new }
            }
            return (gtfs, delays)
        }.value
    }

    private func tryLoadFromCache() async -> (gtfs: GTFSData, delays: [String: TripDelayInfo])? {
        guard FileManager.default.fileExists(atPath: gtfsDir.appendingPathComponent("stops.txt").path) else {
            return nil
        }
        let folder = gtfsDir.path
        let pbPath = pbURL.path
        let tramFolder = euskotrenGtfsDir.path
        let tramPbPath = euskotrenPbURL.path
        return await Task.detached(priority: .userInitiated) {
            var gtfs = loadGTFS(folder: folder)
            let tramGtfs = loadEuskoTranGTFS(folder: tramFolder)
            for (id, stop)     in tramGtfs.stops    { gtfs.stops[id] = stop }
            for (id, trip)     in tramGtfs.trips    { gtfs.trips[id] = trip }
            for (id, route)    in tramGtfs.routes   { gtfs.routes[id] = route }
            for (id, arrivals) in tramGtfs.stopArrivals {
                gtfs.stopArrivals[id, default: []] += arrivals
            }
            for (date, svcIds) in tramGtfs.activeDates {
                gtfs.activeDates[date, default: []].formUnion(svcIds)
            }

            var delays: [String: TripDelayInfo] = [:]
            if let data = FileManager.default.contents(atPath: pbPath) {
                delays = loadTripDelays(data: data)
            }
            if let tramData = FileManager.default.contents(atPath: tramPbPath) {
                let tramDelays = loadTripDelays(data: tramData)
                delays.merge(tramDelays) { _, new in new }
            }
            return (gtfs, delays)
        }.value
    }
}
