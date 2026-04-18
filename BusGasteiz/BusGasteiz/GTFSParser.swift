import Foundation

// MARK: - Utilidades de fecha y distancia

nonisolated func haversine(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
    let R = 6_371_000.0
    let φ1 = lat1 * .pi / 180, φ2 = lat2 * .pi / 180
    let Δφ = (lat2 - lat1) * .pi / 180, Δλ = (lon2 - lon1) * .pi / 180
    let a = sin(Δφ / 2) * sin(Δφ / 2) + cos(φ1) * cos(φ2) * sin(Δλ / 2) * sin(Δλ / 2)
    return R * 2 * atan2(sqrt(a), sqrt(1 - a))
}

nonisolated func dateString(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyyMMdd"
    f.timeZone = TimeZone(identifier: "Europe/Madrid")
    return f.string(from: date)
}

/// Convierte (fecha de servicio yyyyMMdd, segundos desde medianoche) → Date.
// MARK: - Formateadores compartidos (DateFormatter es caro de crear)

nonisolated private let _gtfsDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyyMMdd"
    f.timeZone = TimeZone(identifier: "Europe/Madrid")
    return f
}()

nonisolated private let _timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    f.timeZone = TimeZone(identifier: "Europe/Madrid")
    return f
}()

nonisolated func scheduledDate(serviceDate: String, secondsFromMidnight: Int) -> Date? {
    guard let base = _gtfsDateFormatter.date(from: serviceDate) else { return nil }
    return base.addingTimeInterval(TimeInterval(secondsFromMidnight))
}

nonisolated func formatTime(_ date: Date) -> String {
    _timeFormatter.string(from: date)
}

nonisolated func minutesUntil(_ date: Date, from now: Date = Date()) -> Int {
    Int((date.timeIntervalSince(now) / 60).rounded())
}

/// Determina la fecha de servicio (hoy o ayer) que hace que el horario caiga en la ventana.
nonisolated func resolveServiceDate(
    trip: TripInfo,
    arrivalSecs: Int,
    activeServiceIds: Set<String>,
    yesterdayActiveIds: Set<String>,
    today: String,
    yesterday: String,
    windowStart: Date,
    windowEnd: Date
) -> String? {
    let candidates: [(date: String, validSvcIds: Set<String>)] = [
        (today, activeServiceIds),
        (yesterday, yesterdayActiveIds)
    ]
    for (date, validIds) in candidates {
        let svcOk = validIds.contains(trip.serviceId) || trip.serviceId == "UNDEFINED"
        guard svcOk else { continue }
        guard let schTime = scheduledDate(serviceDate: date, secondsFromMidnight: arrivalSecs)
        else { continue }
        if schTime >= windowStart && schTime <= windowEnd { return date }
    }
    return nil
}

// MARK: - Cargador GTFS estático

nonisolated func loadGTFS(folder: String) -> GTFSData {
    var g = GTFSData()

    func idx(_ h: [String], _ n: String) -> Int? { h.firstIndex(of: n) }
    func get(_ r: [String], _ i: Int?) -> String {
        guard let i, i < r.count else { return "" }; return r[i]
    }
    func parseSecs(_ s: String) -> Int {
        let p = s.split(separator: ":").compactMap { Int($0) }
        guard p.count == 3 else { return -1 }
        return p[0] * 3600 + p[1] * 60 + p[2]
    }

    // routes.txt
    if let raw = try? String(contentsOfFile: "\(folder)/routes.txt", encoding: .utf8) {
        var lines = raw.components(separatedBy: "\n")
        let h = splitCSV(lines.removeFirst())
        let iId = idx(h, "route_id"),  iSn = idx(h, "route_short_name")
        let iLn = idx(h, "route_long_name"), iCo = idx(h, "route_color")
        for ln in lines {
            let t = ln.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty else { continue }
            let r = splitCSV(t); let id = get(r, iId); guard !id.isEmpty else { continue }
            g.routes[id] = RouteInfo(id: id, shortName: get(r, iSn),
                                     longName: get(r, iLn), color: get(r, iCo))
        }
    }

    // trips.txt
    if let raw = try? String(contentsOfFile: "\(folder)/trips.txt", encoding: .utf8) {
        var lines = raw.components(separatedBy: "\n")
        let h = splitCSV(lines.removeFirst())
        let iId = idx(h, "trip_id"), iRt = idx(h, "route_id")
        let iHs = idx(h, "trip_headsign"), iSv = idx(h, "service_id")
        for ln in lines {
            let t = ln.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty else { continue }
            let r = splitCSV(t); let id = get(r, iId); guard !id.isEmpty else { continue }
            g.trips[id] = TripInfo(id: id, routeId: get(r, iRt),
                                   headsign: get(r, iHs), serviceId: get(r, iSv))
        }
    }

    // stops.txt
    if let raw = try? String(contentsOfFile: "\(folder)/stops.txt", encoding: .utf8) {
        var lines = raw.components(separatedBy: "\n")
        let h = splitCSV(lines.removeFirst())
        let iId = idx(h, "stop_id"), iNm = idx(h, "stop_name")
        let iLat = idx(h, "stop_lat"), iLon = idx(h, "stop_lon")
        for ln in lines {
            let t = ln.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty else { continue }
            let r = splitCSV(t); let id = get(r, iId); guard !id.isEmpty else { continue }
            g.stops[id] = StopInfo(id: id, name: get(r, iNm),
                                   lat: Double(get(r, iLat)) ?? 0.0,
                                   lon: Double(get(r, iLon)) ?? 0.0)
        }
    }

    // translations.txt — nombres localizados de paradas (eu y es)
    if let raw = try? String(contentsOfFile: "\(folder)/translations.txt", encoding: .utf8) {
        var lines = raw.components(separatedBy: "\n")
        let h = splitCSV(lines.removeFirst())
        let iTbl = idx(h, "table_name"), iFld = idx(h, "field_name")
        let iLng = idx(h, "language"),   iTrl = idx(h, "translation")
        let iRid = idx(h, "record_id")
        for ln in lines {
            let t = ln.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty else { continue }
            let r = splitCSV(t)
            guard get(r, iTbl) == "stops", get(r, iFld) == "stop_name" else { continue }
            let lang = get(r, iLng); let rid = get(r, iRid)
            guard !rid.isEmpty, !lang.isEmpty else { continue }
            let translation = get(r, iTrl)
            switch lang {
            case "eu": g.stops[rid]?.nameEu = translation
            case "es": g.stops[rid]?.nameEs = translation
            default: break
            }
        }
    }

    // calendar_dates.txt
    if let raw = try? String(contentsOfFile: "\(folder)/calendar_dates.txt", encoding: .utf8) {
        var lines = raw.components(separatedBy: "\n")
        let h = splitCSV(lines.removeFirst())
        let iSv = idx(h, "service_id"), iDt = idx(h, "date"), iEx = idx(h, "exception_type")
        for ln in lines {
            let t = ln.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty else { continue }
            let r = splitCSV(t)
            let svcId = get(r, iSv); let date = get(r, iDt); let ex = get(r, iEx)
            guard !svcId.isEmpty, !date.isEmpty, ex == "1" else { continue }
            g.activeDates[date, default: []].insert(svcId)
        }
    }

    // stop_times.txt — índice por stop_id
    if let raw = try? String(contentsOfFile: "\(folder)/stop_times.txt", encoding: .utf8) {
        var lines = raw.components(separatedBy: "\n")
        let h = splitCSV(lines.removeFirst())
        let iTr = idx(h, "trip_id"), iSt = idx(h, "stop_id")
        let iAr = idx(h, "arrival_time"), iDp = idx(h, "departure_time"), iSq = idx(h, "stop_sequence")
        for ln in lines {
            let t = ln.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty else { continue }
            let r = splitCSV(t)
            let tid = get(r, iTr); let sid = get(r, iSt)
            guard !tid.isEmpty, !sid.isEmpty else { continue }
            var secs = parseSecs(get(r, iAr))
            if secs < 0 { secs = parseSecs(get(r, iDp)) }
            guard secs >= 0 else { continue }
            let entry = StopTimeEntry(tripId: tid, stopSequence: Int(get(r, iSq)) ?? 0, arrivalSecs: secs)
            g.stopArrivals[sid, default: []].append(entry)
        }
    }

    return g
}

// MARK: - Parser CSV mínimo

nonisolated func splitCSV(_ line: String) -> [String] {
    var fields: [String] = []; var current = ""; var inQ = false
    for c in line {
        if c == "\"" { inQ.toggle() }
        else if c == "," && !inQ { fields.append(current); current = "" }
        else { current.append(c) }
    }
    fields.append(current); return fields
}

// MARK: - Lector de fechas activas desde calendar.txt (Euskotren)

/// Expande `calendar.txt` (horario semanal) y aplica excepciones de `calendar_dates.txt`.
/// Devuelve un diccionario `yyyyMMdd → Set<service_id>` equivalente al de Tuvisa.
nonisolated func loadActiveDatesFromCalendar(folder: String) -> [String: Set<String>] {
    func idx(_ h: [String], _ n: String) -> Int? { h.firstIndex(of: n) }
    func get(_ r: [String], _ i: Int?) -> String {
        guard let i, i < r.count else { return "" }; return r[i]
    }

    var activeDates: [String: Set<String>] = [:]
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Europe/Madrid")!
    let df = DateFormatter()
    df.dateFormat = "yyyyMMdd"
    df.timeZone = TimeZone(identifier: "Europe/Madrid")

    // calendar.txt: expand weekly schedule into individual dates
    if let raw = try? String(contentsOfFile: "\(folder)/calendar.txt", encoding: .utf8) {
        var lines = raw.components(separatedBy: "\n")
        guard !lines.isEmpty else { return activeDates }
        let h = splitCSV(lines.removeFirst())
        let iSv = idx(h, "service_id")
        // Columns ordered Mon…Sun; weekday component 1=Sun,2=Mon,…,7=Sat → (wd-2+7)%7 = 0=Mon…6=Sun
        let dayIdxs = ["monday", "tuesday", "wednesday", "thursday",
                        "friday", "saturday", "sunday"].map { idx(h, $0) }
        let iSt = idx(h, "start_date"), iEn = idx(h, "end_date")
        for ln in lines {
            let t = ln.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty else { continue }
            let r = splitCSV(t); let svcId = get(r, iSv); guard !svcId.isEmpty else { continue }
            let flags = dayIdxs.map { get(r, $0) == "1" }
            guard let startDate = df.date(from: get(r, iSt)),
                  let endDate   = df.date(from: get(r, iEn)) else { continue }
            var current = startDate
            while current <= endDate {
                let wd = (cal.component(.weekday, from: current) - 2 + 7) % 7
                if flags[wd] {
                    activeDates[df.string(from: current), default: []].insert(svcId)
                }
                current = cal.date(byAdding: .day, value: 1, to: current)!
            }
        }
    }

    // calendar_dates.txt: apply additions (type 1) and removals (type 2)
    if let raw = try? String(contentsOfFile: "\(folder)/calendar_dates.txt", encoding: .utf8) {
        var lines = raw.components(separatedBy: "\n")
        guard !lines.isEmpty else { return activeDates }
        let h = splitCSV(lines.removeFirst())
        let iSv = idx(h, "service_id"), iDt = idx(h, "date"), iEx = idx(h, "exception_type")
        for ln in lines {
            let t = ln.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty else { continue }
            let r = splitCSV(t)
            let svcId = get(r, iSv); let date = get(r, iDt); let ex = get(r, iEx)
            guard !svcId.isEmpty, !date.isEmpty else { continue }
            if ex == "1"      { activeDates[date, default: []].insert(svcId) }
            else if ex == "2" { activeDates[date]?.remove(svcId) }
        }
    }

    return activeDates
}

// MARK: - Cargador GTFS Euskotren Tranvía Vitoria-Gasteiz

/// Carga únicamente las paradas, viajes y horarios del tranvía de Vitoria-Gasteiz
/// (operador EUS_TrGa: líneas TG1, TG2 y 41) desde el GTFS estático de Euskotren.
/// Las paradas resultantes llevan `isTram = true`.
nonisolated func loadEuskoTranGTFS(folder: String) -> GTFSData {
    var g = GTFSData()

    func localIdx(_ h: [String], _ n: String) -> Int? { h.firstIndex(of: n) }
    func localGet(_ r: [String], _ i: Int?) -> String {
        guard let i, i < r.count else { return "" }; return r[i]
    }
    func parseSecs(_ s: String) -> Int {
        let p = s.split(separator: ":").compactMap { Int($0) }
        guard p.count == 3 else { return -1 }
        return p[0] * 3600 + p[1] * 60 + p[2]
    }

    let vitoriaTramAgency = "ES:Euskotren:Operator:EUS_TrGa:"

    // 1. routes.txt — filtrar al operador del tranvía de Vitoria
    var tramRouteIds = Set<String>()
    if let raw = try? String(contentsOfFile: "\(folder)/routes.txt", encoding: .utf8) {
        var lines = raw.components(separatedBy: "\n")
        let h = splitCSV(lines.removeFirst())
        let iId = localIdx(h, "route_id"), iAg = localIdx(h, "agency_id")
        let iSn = localIdx(h, "route_short_name"), iLn = localIdx(h, "route_long_name")
        let iCo = localIdx(h, "route_color")
        for ln in lines {
            let t = ln.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty else { continue }
            let r = splitCSV(t); let id = localGet(r, iId)
            let shortName = localGet(r, iSn)
            // Incluir solo rutas del tranvía de Gasteiz con nombre visible (TG1, TG2…).
            // La línea "41" (Ibaiondo-Unibertsitatea) es un servicio combinado interno
            // que no tiene identidad visual para el usuario.
            guard !id.isEmpty,
                  localGet(r, iAg) == vitoriaTramAgency,
                  shortName.hasPrefix("TG") else { continue }
            tramRouteIds.insert(id)
            g.routes[id] = RouteInfo(id: id, shortName: shortName,
                                     longName: localGet(r, iLn), color: localGet(r, iCo))
        }
    }

    // 2. trips.txt — filtrar a rutas de tranvía
    var tramTripIds = Set<String>()
    if let raw = try? String(contentsOfFile: "\(folder)/trips.txt", encoding: .utf8) {
        var lines = raw.components(separatedBy: "\n")
        let h = splitCSV(lines.removeFirst())
        let iId = localIdx(h, "trip_id"), iRt = localIdx(h, "route_id")
        let iHs = localIdx(h, "trip_headsign"), iSv = localIdx(h, "service_id")
        for ln in lines {
            let t = ln.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty else { continue }
            let r = splitCSV(t)
            let id = localGet(r, iId), routeId = localGet(r, iRt)
            guard !id.isEmpty, tramRouteIds.contains(routeId) else { continue }
            tramTripIds.insert(id)
            g.trips[id] = TripInfo(id: id, routeId: routeId,
                                   headsign: localGet(r, iHs), serviceId: localGet(r, iSv))
        }
    }

    // 2b. stops.txt — mapa Quay → StopPlace (parent_station) para agrupar andenes
    //     Cada parada física tiene dos Quays (un andén por sentido) con las mismas
    //     coordenadas. Agrupamos por StopPlace para evitar duplicados en el mapa
    //     y mostrar los tranvías de ambas direcciones en la misma entrada.
    var quayToStopPlace: [String: String] = [:]  // quay_id → stopPlace_id
    var stopPlaceInfo: [String: (name: String, lat: Double, lon: Double)] = [:]
    if let raw = try? String(contentsOfFile: "\(folder)/stops.txt", encoding: .utf8) {
        var lines = raw.components(separatedBy: "\n")
        let h = splitCSV(lines.removeFirst())
        let iId  = localIdx(h, "stop_id"),    iNm  = localIdx(h, "stop_name")
        let iLat = localIdx(h, "stop_lat"),   iLon = localIdx(h, "stop_lon")
        let iLt  = localIdx(h, "location_type"), iPa = localIdx(h, "parent_station")
        for ln in lines {
            let t = ln.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty else { continue }
            let r = splitCSV(t); let id = localGet(r, iId); guard !id.isEmpty else { continue }
            let locType = localGet(r, iLt)
            if locType == "1" {
                // StopPlace: guardar sus datos para usarlos como parada canónica
                let lat = Double(localGet(r, iLat)) ?? 0.0
                let lon = Double(localGet(r, iLon)) ?? 0.0
                stopPlaceInfo[id] = (name: localGet(r, iNm), lat: lat, lon: lon)
            } else if locType == "0" {
                // Quay (andén): apuntar a su StopPlace padre
                let parent = localGet(r, iPa)
                if !parent.isEmpty { quayToStopPlace[id] = parent }
            }
        }
    }

    // 3. stop_times.txt — filtrar a viajes de tranvía; traducir Quay → StopPlace
    if let raw = try? String(contentsOfFile: "\(folder)/stop_times.txt", encoding: .utf8) {
        var lines = raw.components(separatedBy: "\n")
        let h = splitCSV(lines.removeFirst())
        let iTr = localIdx(h, "trip_id"), iSt = localIdx(h, "stop_id")
        let iAr = localIdx(h, "arrival_time"), iDp = localIdx(h, "departure_time")
        let iSq = localIdx(h, "stop_sequence")
        for ln in lines {
            let t = ln.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty else { continue }
            let r = splitCSV(t)
            let tid = localGet(r, iTr), quayId = localGet(r, iSt)
            guard !tid.isEmpty, !quayId.isEmpty, tramTripIds.contains(tid) else { continue }
            // Resolver al StopPlace padre para agrupar andenes del mismo apeadero
            let sid = quayToStopPlace[quayId] ?? quayId
            var secs = parseSecs(localGet(r, iAr))
            if secs < 0 { secs = parseSecs(localGet(r, iDp)) }
            guard secs >= 0 else { continue }
            let entry = StopTimeEntry(tripId: tid,
                                      stopSequence: Int(localGet(r, iSq)) ?? 0,
                                      arrivalSecs: secs)
            g.stopArrivals[sid, default: []].append(entry)
        }
    }

    // 4. stops — crear una entrada por StopPlace que tenga stop_times
    let usedStopPlaceIds = Set(g.stopArrivals.keys)
    for spId in usedStopPlaceIds {
        if let info = stopPlaceInfo[spId] {
            g.stops[spId] = StopInfo(id: spId, name: info.name,
                                     lat: info.lat, lon: info.lon,
                                     isTram: true)
        }
    }

    // 5. Fechas activas desde calendar.txt + calendar_dates.txt
    let tramDates = loadActiveDatesFromCalendar(folder: folder)
    for (date, svcIds) in tramDates {
        g.activeDates[date, default: []].formUnion(svcIds)
    }

    return g
}



nonisolated func loadTripDelays(data: Data) -> [String: TripDelayInfo] {
    var delays: [String: TripDelayInfo] = [:]
    var r = ProtoReader(data: data)
    while r.hasMore {
        guard let t = r.readTag() else { break }
        switch t.field {
        case 1: _ = r.readLengthDelimited()
        case 2: if let d = r.readLengthDelimited() { parseTUEntity(d, into: &delays) }
        default: r.skip(wire: t.wire)
        }
    }
    return delays
}

private nonisolated func parseTUEntity(_ data: Data, into delays: inout [String: TripDelayInfo]) {
    var r = ProtoReader(data: data)
    var tuData: Data? = nil
    var deleted = false
    while r.hasMore {
        guard let t = r.readTag() else { break }
        switch t.field {
        case 1: _ = r.readLengthDelimited()
        case 2: if let v = r.readVarint() { deleted = v != 0 }
        case 3: tuData = r.readLengthDelimited()
        default: r.skip(wire: t.wire)
        }
    }
    guard !deleted, let tuD = tuData else { return }

    var tu = ProtoReader(data: tuD)
    var tripId = ""
    var info = TripDelayInfo()
    while tu.hasMore {
        guard let t = tu.readTag() else { break }
        switch t.field {
        case 1:
            if let d = tu.readLengthDelimited() {
                var td = ProtoReader(data: d)
                while td.hasMore {
                    guard let tt = td.readTag() else { break }
                    switch tt.field {
                    case 1: if let s = td.readLengthDelimited() { tripId = String(data: s, encoding: .utf8) ?? "" }
                    default: td.skip(wire: tt.wire)
                    }
                }
            }
        case 2:
            if let d = tu.readLengthDelimited() {
                var stu = ProtoReader(data: d)
                var stopId = ""; var arrDelay: Int32 = 0
                while stu.hasMore {
                    guard let tt = stu.readTag() else { break }
                    switch tt.field {
                    case 1: _ = stu.readVarint()
                    case 2:
                        if let d2 = stu.readLengthDelimited() {
                            var ste = ProtoReader(data: d2)
                            while ste.hasMore {
                                guard let tt2 = ste.readTag() else { break }
                                switch tt2.field {
                                case 1: if let v = ste.readVarint() {
                                    arrDelay = Int32(truncatingIfNeeded: Int64(bitPattern: v))
                                }
                                default: ste.skip(wire: tt2.wire)
                                }
                            }
                        }
                    case 3: _ = stu.readLengthDelimited()
                    case 4: if let s = stu.readLengthDelimited() { stopId = String(data: s, encoding: .utf8) ?? "" }
                    default: stu.skip(wire: tt.wire)
                    }
                }
                if !stopId.isEmpty { info.stopDelays[stopId] = arrDelay }
            }
        case 3:
            if let d = tu.readLengthDelimited() {
                var vd = ProtoReader(data: d)
                while vd.hasMore {
                    guard let tt = vd.readTag() else { break }
                    switch tt.field {
                    case 2: if let s = vd.readLengthDelimited() { info.vehicleLabel = String(data: s, encoding: .utf8) ?? "" }
                    default: vd.skip(wire: tt.wire)
                    }
                }
            }
        case 5:
            if let v = tu.readVarint() {
                info.generalDelay = Int32(truncatingIfNeeded: Int64(bitPattern: v))
            }
        default: tu.skip(wire: t.wire)
        }
    }
    if !tripId.isEmpty { delays[tripId] = info }
}

// MARK: - Análisis de alertas de servicio (GTFS-RT Alerts)

nonisolated func loadAlerts(data: Data) -> ServiceAlerts {
    var alerts = ServiceAlerts()
    var r = ProtoReader(data: data)
    while r.hasMore {
        guard let t = r.readTag() else { break }
        switch t.field {
        case 1: _ = r.readLengthDelimited()  // header, ignorar
        case 2: if let d = r.readLengthDelimited() { parseAlertEntity(d, into: &alerts) }
        default: r.skip(wire: t.wire)
        }
    }
    return alerts
}

private nonisolated func parseAlertEntity(_ data: Data, into alerts: inout ServiceAlerts) {
    var r = ProtoReader(data: data)
    var alertData: Data? = nil
    var deleted = false
    while r.hasMore {
        guard let t = r.readTag() else { break }
        switch t.field {
        case 1: _ = r.readLengthDelimited()                           // id
        case 2: if let v = r.readVarint() { deleted = v != 0 }        // is_deleted
        case 5: alertData = r.readLengthDelimited()                    // Alert (campo 5, no 3)
        default: r.skip(wire: t.wire)
        }
    }
    guard !deleted, let aData = alertData else { return }

    // Recoger selectores de entidad y textos en una sola pasada
    var stopIds:     [String] = []
    var routeIds:    [String] = []
    var headerParts: [(lang: String, text: String)] = []
    var descParts:   [(lang: String, text: String)] = []

    var ar = ProtoReader(data: aData)
    while ar.hasMore {
        guard let t = ar.readTag() else { break }
        switch t.field {
        case 1: _ = ar.readLengthDelimited()  // active_period, ignorar
        case 2:  // informed_entity (EntitySelector)
            if let d = ar.readLengthDelimited() {
                var es = ProtoReader(data: d)
                while es.hasMore {
                    guard let tt = es.readTag() else { break }
                    switch tt.field {
                    case 2: // route_id
                        if let dd = es.readLengthDelimited(),
                           let s = String(data: dd, encoding: .utf8), !s.isEmpty {
                            routeIds.append(s)
                        }
                    case 5: // stop_id
                        if let dd = es.readLengthDelimited(),
                           let s = String(data: dd, encoding: .utf8), !s.isEmpty {
                            stopIds.append(s)
                        }
                    default: es.skip(wire: tt.wire)
                    }
                }
            }
        case 6: // header_text (TranslatedString)
            if let d = ar.readLengthDelimited() { headerParts = parseTranslatedString(d) }
        case 7: // description_text (TranslatedString)
            if let d = ar.readLengthDelimited() { descParts = parseTranslatedString(d) }
        default: ar.skip(wire: t.wire)
        }
    }

    let header = bestTranslation(from: headerParts)
    let desc   = bestTranslation(from: descParts)
    guard !header.isEmpty || !desc.isEmpty else { return }

    let alert = ServiceAlert(headerText: header, descriptionText: desc)
    for sid in stopIds  {
        alerts.stopAlerts[sid,  default: []].append(alert)
        alerts.stopIds.insert(sid)
    }
    for rid in routeIds {
        alerts.routeAlerts[rid, default: []].append(alert)
        alerts.routeIds.insert(rid)
    }
}

private nonisolated func parseTranslatedString(_ data: Data) -> [(lang: String, text: String)] {
    var r = ProtoReader(data: data)
    var result: [(lang: String, text: String)] = []
    while r.hasMore {
        guard let t = r.readTag() else { break }
        switch t.field {
        case 1:  // Translation
            if let d = r.readLengthDelimited() {
                var tr = ProtoReader(data: d)
                var text = ""
                var lang = ""
                while tr.hasMore {
                    guard let tt = tr.readTag() else { break }
                    switch tt.field {
                    case 1: if let d2 = tr.readLengthDelimited() { text = String(data: d2, encoding: .utf8) ?? "" }
                    case 2: if let d2 = tr.readLengthDelimited() { lang = String(data: d2, encoding: .utf8) ?? "" }
                    default: tr.skip(wire: tt.wire)
                    }
                }
                if !text.isEmpty { result.append((lang: lang, text: text)) }
            }
        default: r.skip(wire: t.wire)
        }
    }
    return result
}

private nonisolated func bestTranslation(from parts: [(lang: String, text: String)]) -> String {
    guard !parts.isEmpty else { return "" }
    let deviceLang = Locale.current.language.languageCode?.identifier ?? ""
    if let match = parts.first(where: { $0.lang == deviceLang }) { return match.text }
    if let es    = parts.first(where: { $0.lang == "es" })        { return es.text }
    return parts[0].text
}

// MARK: - Motor de consulta

/// Devuelve true si la parada tiene al menos un viaje con servicio activo hoy
/// (o ayer, para cubrir viajes que cruzan la medianoche).
nonisolated func stopHasServiceToday(stopId: String, gtfsData: GTFSData) -> Bool {
    guard let entries = gtfsData.stopArrivals[stopId] else { return false }
    let now = Date()
    let activeIds:    Set<String> = gtfsData.activeDates[dateString(now)]                         ?? []
    let yesterdayIds: Set<String> = gtfsData.activeDates[dateString(now.addingTimeInterval(-86400))] ?? []
    return entries.contains { entry in
        guard let trip = gtfsData.trips[entry.tripId] else { return false }
        return activeIds.contains(trip.serviceId) || yesterdayIds.contains(trip.serviceId)
    }
}

/// Calcula de una sola pasada el conjunto de stop_id que tienen al menos una
/// llegada prevista en los próximos `windowMinutes` minutos.
/// Usa aritmética de epoch pura (sin DateFormatter en el bucle) para ser rápido.
nonisolated func computeStopsWithUpcomingArrivals(gtfsData: GTFSData, windowMinutes: Int = 60) -> Set<String> {
    let now           = Date()
    let nowEpoch      = now.timeIntervalSince1970
    let windowStart   = nowEpoch - 60
    let windowEnd     = nowEpoch + Double(windowMinutes) * 60

    // Precalcula la epoch de medianoche (Europe/Madrid) para hoy y ayer,
    // sin DateFormatter en el bucle.
    let tz = TimeZone(identifier: "Europe/Madrid")!
    func midnightEpoch(daysAgo: Int) -> Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let d = cal.startOfDay(for: now.addingTimeInterval(Double(-daysAgo) * 86400))
        return d.timeIntervalSince1970
    }
    let todayMidnight     = midnightEpoch(daysAgo: 0)
    let yesterdayMidnight = midnightEpoch(daysAgo: 1)

    let today     = dateString(now)
    let yesterday = dateString(now.addingTimeInterval(-86400))
    let activeIds:    Set<String> = gtfsData.activeDates[today]     ?? []
    let yesterdayIds: Set<String> = gtfsData.activeDates[yesterday] ?? []

    var result = Set<String>()
    for (stopId, entries) in gtfsData.stopArrivals {
        guard !result.contains(stopId) else { continue }
        for entry in entries {
            guard let trip = gtfsData.trips[entry.tripId] else { continue }
            let svc = trip.serviceId
            // Comprobar hoy
            if activeIds.contains(svc) || svc == "UNDEFINED" {
                let t = todayMidnight + Double(entry.arrivalSecs)
                if t >= windowStart && t <= windowEnd { result.insert(stopId); break }
            }
            // Comprobar viajes que cruzaron medianoche (servicio de ayer, hora >24h)
            if yesterdayIds.contains(svc) || svc == "UNDEFINED" {
                let t = yesterdayMidnight + Double(entry.arrivalSecs)
                if t >= windowStart && t <= windowEnd { result.insert(stopId); break }
            }
        }
    }
    return result
}

/// Líneas únicas que pasan por una parada, incluyendo variantes (5A/5B/5C...),
/// ordenadas numéricamente/alfabéticamente.
nonisolated func routesForStop(stopId: String, gtfsData: GTFSData, alerts: ServiceAlerts = ServiceAlerts()) -> [RouteTag] {
    guard let entries = gtfsData.stopArrivals[stopId] else { return [] }
    var seen = Set<String>()
    var tags: [RouteTag] = []
    for entry in entries {
        guard let trip = gtfsData.trips[entry.tripId],
              let route = gtfsData.routes[trip.routeId] else { continue }
        let suffix = variantSuffix(routeId: trip.routeId, headsign: trip.headsign)
        let displayName = route.shortName + (suffix ?? "")
        guard seen.insert(displayName).inserted else { continue }
        let hasAlert = alerts.routeIds.contains(trip.routeId)
        tags.append(RouteTag(shortName: displayName, color: route.color, hasAlert: hasAlert))
    }
    tags.sort {
        // Ordena por prefijo numérico y luego por sufijo alfabético (5 < 5A < 5B < 6).
        let aNum = Int($0.shortName.prefix(while: { $0.isNumber }))
        let bNum = Int($1.shortName.prefix(while: { $0.isNumber }))
        if let a = aNum, let b = bNum {
            if a != b { return a < b }
            return $0.shortName < $1.shortName
        }
        if aNum != nil { return true }
        if bNum != nil { return false }
        return $0.shortName < $1.shortName
    }
    return tags
}

/// Paradas dentro del radio, ordenadas por distancia.
nonisolated func computeNearbyStops(lat: Double, lon: Double, radius: Double,
                                     gtfsData: GTFSData, activeStopIds: Set<String>,
                                     alerts: ServiceAlerts = ServiceAlerts()) -> [NearbyStop] {
    return gtfsData.stops.values
        .compactMap { stop -> NearbyStop? in
            let d = haversine(lat1: lat, lon1: lon, lat2: stop.lat, lon2: stop.lon)
            guard d <= radius else { return nil }
            let routeTags = routesForStop(stopId: stop.id, gtfsData: gtfsData, alerts: alerts)
            let hasAlert = alerts.stopIds.contains(stop.id) || routeTags.contains(where: { $0.hasAlert })
            return NearbyStop(stop: stop, distance: d,
                              hasArrivals: activeStopIds.contains(stop.id),
                              routes: routeTags,
                              hasAlert: hasAlert)
        }
        .sorted { $0.distance < $1.distance }
}

/// Paradas dentro del área visible del mapa (bounding box), ordenadas por distancia al punto de referencia.
nonisolated func computeStopsInBounds(
    minLat: Double, maxLat: Double,
    minLon: Double, maxLon: Double,
    refLat: Double, refLon: Double,
    gtfsData: GTFSData,
    activeStopIds: Set<String>,
    alerts: ServiceAlerts = ServiceAlerts()
) -> [NearbyStop] {
    return gtfsData.stops.values
        .compactMap { stop -> NearbyStop? in
            guard stop.lat >= minLat && stop.lat <= maxLat &&
                  stop.lon >= minLon && stop.lon <= maxLon else { return nil }
            let d = haversine(lat1: refLat, lon1: refLon, lat2: stop.lat, lon2: stop.lon)
            let routeTags = routesForStop(stopId: stop.id, gtfsData: gtfsData, alerts: alerts)
            let hasAlert = alerts.stopIds.contains(stop.id) || routeTags.contains(where: { $0.hasAlert })
            return NearbyStop(stop: stop, distance: d,
                              hasArrivals: activeStopIds.contains(stop.id),
                              routes: routeTags,
                              hasAlert: hasAlert)
        }
        .sorted { $0.distance < $1.distance }
}

/// Llegadas previstas para una parada en los próximos `windowMinutes` minutos.
nonisolated func computeArrivals(
    stopId: String,
    distance: Double,
    gtfsData: GTFSData,
    delays: [String: TripDelayInfo],
    alerts: ServiceAlerts = ServiceAlerts(),
    windowMinutes: Int = 60
) -> [UpcomingArrival] {
    guard let stop = gtfsData.stops[stopId],
          let entries = gtfsData.stopArrivals[stopId] else { return [] }

    let now = Date()
    let today = dateString(now)
    let yesterday = dateString(now.addingTimeInterval(-86400))
    let activeIds: Set<String> = gtfsData.activeDates[today] ?? []
    let yesterdayIds: Set<String> = gtfsData.activeDates[yesterday] ?? []
    let windowStart = now.addingTimeInterval(-60)
    let windowEnd = now.addingTimeInterval(TimeInterval(windowMinutes * 60))

    var arrivals: [UpcomingArrival] = []

    for entry in entries {
        guard let trip = gtfsData.trips[entry.tripId] else { continue }

        guard let serviceDate = resolveServiceDate(
            trip: trip,
            arrivalSecs: entry.arrivalSecs,
            activeServiceIds: activeIds,
            yesterdayActiveIds: yesterdayIds,
            today: today,
            yesterday: yesterday,
            windowStart: windowStart,
            windowEnd: windowEnd
        ) else { continue }

        guard let schTime = scheduledDate(serviceDate: serviceDate,
                                         secondsFromMidnight: entry.arrivalSecs)
        else { continue }

        let delayInfo = delays[entry.tripId]
        let delay: Int32
        let isRT: Bool
        if let d = delayInfo?.stopDelays[stopId] {
            delay = d; isRT = true
        } else if let g = delayInfo?.generalDelay {
            delay = g; isRT = true
        } else {
            delay = 0; isRT = false
        }

        let predTime = schTime.addingTimeInterval(TimeInterval(delay))
        guard predTime >= windowStart && predTime <= windowEnd else { continue }

        let route = gtfsData.routes[trip.routeId]
        let routeDisplayName = (route?.shortName ?? trip.routeId)
            + (variantSuffix(routeId: trip.routeId, headsign: trip.headsign) ?? "")
        let hasAlert = alerts.routeIds.contains(trip.routeId) || alerts.stopIds.contains(stopId)
        arrivals.append(UpcomingArrival(
            stopId: stopId,
            stopName: stop.name,
            distanceMeters: distance,
            routeShortName: routeDisplayName,
            routeLongName:  route?.longName  ?? "",
            routeColor:     route?.color     ?? "",
            headsign:       trip.headsign,
            scheduledTime:  schTime,
            predictedTime:  predTime,
            delaySecs:      delay,
            vehicleLabel:   delayInfo?.vehicleLabel ?? "",
            isRealTime:     isRT,
            hasAlert:       hasAlert
        ))
    }

    arrivals.sort { $0.predictedTime < $1.predictedTime }
    return arrivals
}

/// Devuelve el primer servicio futuro por línea en los próximos `daysAhead` días,
/// útil para mostrar cuándo volverá a haber servicio cuando la ventana de 60 min está vacía.
nonisolated func computeNextArrivals(
    stopId: String,
    distance: Double,
    gtfsData: GTFSData,
    delays: [String: TripDelayInfo],
    alerts: ServiceAlerts = ServiceAlerts(),
    daysAhead: Int = 7
) -> [UpcomingArrival] {
    guard let stop = gtfsData.stops[stopId],
          let entries = gtfsData.stopArrivals[stopId] else { return [] }

    let now = Date()
    let nowEpoch = now.timeIntervalSince1970

    let tz = TimeZone(identifier: "Europe/Madrid")!
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz

    // Construye la lista de días a buscar: ayer (viajes cross-midnight) + hoy + próximos días
    struct DayInfo { let dateStr: String; let midnightEpoch: Double; let svcIds: Set<String> }
    var days: [DayInfo] = []
    for offset in -1..<daysAhead {
        let date = now.addingTimeInterval(Double(offset) * 86400)
        let str = dateString(date)
        let midnight = cal.startOfDay(for: date).timeIntervalSince1970
        let svcIds: Set<String> = gtfsData.activeDates[str] ?? []
        days.append(DayInfo(dateStr: str, midnightEpoch: midnight, svcIds: svcIds))
    }

    // Mejor (más próxima futura) llegada por routeShortName
    var bestEpochByRoute: [String: Double] = [:]
    var bestArrivalByRoute: [String: UpcomingArrival] = [:]

    for entry in entries {
        guard let trip = gtfsData.trips[entry.tripId] else { continue }
        let svc = trip.serviceId
        let route = gtfsData.routes[trip.routeId]
        let routeShortName = (route?.shortName ?? trip.routeId)
            + (variantSuffix(routeId: trip.routeId, headsign: trip.headsign) ?? "")

        for day in days {
            let active = day.svcIds.contains(svc) || svc == "UNDEFINED"
            guard active else { continue }

            let epoch = day.midnightEpoch + Double(entry.arrivalSecs)
            guard epoch > nowEpoch else { continue } // solo en el futuro

            // Si ya tenemos una mejor, descartamos
            if let best = bestEpochByRoute[routeShortName], best <= epoch { continue }

            let schTime = Date(timeIntervalSince1970: epoch)
            let delayInfo = delays[entry.tripId]
            let delay: Int32
            let isRT: Bool
            if let d = delayInfo?.stopDelays[stopId] {
                delay = d; isRT = true
            } else if let g = delayInfo?.generalDelay {
                delay = g; isRT = true
            } else {
                delay = 0; isRT = false
            }
            let predTime = schTime.addingTimeInterval(TimeInterval(delay))

            bestEpochByRoute[routeShortName] = epoch
            let hasAlert = alerts.routeIds.contains(trip.routeId) || alerts.stopIds.contains(stopId)
            bestArrivalByRoute[routeShortName] = UpcomingArrival(
                stopId: stopId,
                stopName: stop.name,
                distanceMeters: distance,
                routeShortName: routeShortName,
                routeLongName:  route?.longName  ?? "",
                routeColor:     route?.color     ?? "",
                headsign:       trip.headsign,
                scheduledTime:  schTime,
                predictedTime:  predTime,
                delaySecs:      delay,
                vehicleLabel:   delayInfo?.vehicleLabel ?? "",
                isRealTime:     isRT,
                hasAlert:       hasAlert
            )
            break // este día ya da el mínimo para esta entrada; ir al siguiente entry
        }
    }

    return bestArrivalByRoute.values.sorted { $0.scheduledTime < $1.scheduledTime }
}
