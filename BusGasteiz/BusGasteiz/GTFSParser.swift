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
nonisolated func scheduledDate(serviceDate: String, secondsFromMidnight: Int) -> Date? {
    let f = DateFormatter()
    f.dateFormat = "yyyyMMdd"
    f.timeZone = TimeZone(identifier: "Europe/Madrid")
    guard let base = f.date(from: serviceDate) else { return nil }
    return base.addingTimeInterval(TimeInterval(secondsFromMidnight))
}

nonisolated func formatTime(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    f.timeZone = TimeZone(identifier: "Europe/Madrid")
    return f.string(from: date)
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
            guard !id.isEmpty, localGet(r, iAg) == vitoriaTramAgency else { continue }
            tramRouteIds.insert(id)
            g.routes[id] = RouteInfo(id: id, shortName: localGet(r, iSn),
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

    // 3. stop_times.txt — filtrar a viajes de tranvía y recopilar IDs de paradas
    var tramStopIds = Set<String>()
    if let raw = try? String(contentsOfFile: "\(folder)/stop_times.txt", encoding: .utf8) {
        var lines = raw.components(separatedBy: "\n")
        let h = splitCSV(lines.removeFirst())
        let iTr = localIdx(h, "trip_id"), iSt = localIdx(h, "stop_id")
        let iAr = localIdx(h, "arrival_time"), iDp = localIdx(h, "departure_time")
        let iSq = localIdx(h, "stop_sequence")
        for ln in lines {
            let t = ln.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty else { continue }
            let r = splitCSV(t)
            let tid = localGet(r, iTr), sid = localGet(r, iSt)
            guard !tid.isEmpty, !sid.isEmpty, tramTripIds.contains(tid) else { continue }
            tramStopIds.insert(sid)
            var secs = parseSecs(localGet(r, iAr))
            if secs < 0 { secs = parseSecs(localGet(r, iDp)) }
            guard secs >= 0 else { continue }
            let entry = StopTimeEntry(tripId: tid,
                                      stopSequence: Int(localGet(r, iSq)) ?? 0,
                                      arrivalSecs: secs)
            g.stopArrivals[sid, default: []].append(entry)
        }
    }

    // 4. stops.txt — solo las paradas usadas por el tranvía
    if let raw = try? String(contentsOfFile: "\(folder)/stops.txt", encoding: .utf8) {
        var lines = raw.components(separatedBy: "\n")
        let h = splitCSV(lines.removeFirst())
        let iId = localIdx(h, "stop_id"), iNm = localIdx(h, "stop_name")
        let iLat = localIdx(h, "stop_lat"), iLon = localIdx(h, "stop_lon")
        for ln in lines {
            let t = ln.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty else { continue }
            let r = splitCSV(t); let id = localGet(r, iId)
            guard !id.isEmpty, tramStopIds.contains(id) else { continue }
            g.stops[id] = StopInfo(id: id, name: localGet(r, iNm),
                                   lat: Double(localGet(r, iLat)) ?? 0.0,
                                   lon: Double(localGet(r, iLon)) ?? 0.0,
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

// MARK: - Motor de consulta

/// Paradas dentro del radio, ordenadas por distancia.
nonisolated func computeNearbyStops(lat: Double, lon: Double, radius: Double, gtfsData: GTFSData) -> [NearbyStop] {
    gtfsData.stops.values
        .compactMap { stop -> NearbyStop? in
            let d = haversine(lat1: lat, lon1: lon, lat2: stop.lat, lon2: stop.lon)
            return d <= radius ? NearbyStop(stop: stop, distance: d) : nil
        }
        .sorted { $0.distance < $1.distance }
}

/// Paradas dentro del área visible del mapa (bounding box), ordenadas por distancia al punto de referencia.
nonisolated func computeStopsInBounds(
    minLat: Double, maxLat: Double,
    minLon: Double, maxLon: Double,
    refLat: Double, refLon: Double,
    gtfsData: GTFSData
) -> [NearbyStop] {
    gtfsData.stops.values
        .compactMap { stop -> NearbyStop? in
            guard stop.lat >= minLat && stop.lat <= maxLat &&
                  stop.lon >= minLon && stop.lon <= maxLon else { return nil }
            let d = haversine(lat1: refLat, lon1: refLon, lat2: stop.lat, lon2: stop.lon)
            return NearbyStop(stop: stop, distance: d)
        }
        .sorted { $0.distance < $1.distance }
}

/// Llegadas previstas para una parada en los próximos `windowMinutes` minutos.
nonisolated func computeArrivals(
    stopId: String,
    distance: Double,
    gtfsData: GTFSData,
    delays: [String: TripDelayInfo],
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
        arrivals.append(UpcomingArrival(
            stopId: stopId,
            stopName: stop.name,
            distanceMeters: distance,
            routeShortName: route?.shortName ?? trip.routeId,
            routeLongName:  route?.longName  ?? "",
            routeColor:     route?.color     ?? "",
            headsign:       trip.headsign,
            scheduledTime:  schTime,
            predictedTime:  predTime,
            delaySecs:      delay,
            vehicleLabel:   delayInfo?.vehicleLabel ?? "",
            isRealTime:     isRT
        ))
    }

    arrivals.sort { $0.predictedTime < $1.predictedTime }
    return arrivals
}
