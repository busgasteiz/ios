//
//  RouteVariantConfig.swift
//  BusGasteiz
//
//  Define las variantes de línea (sufijos A/B/C...) basándose en el headsign del viaje.
//  Para añadir variantes a una nueva línea, añadir entradas a `routeVariantRules`.
//  Las reglas se evalúan en orden; la primera que coincide gana.
//

import Foundation

struct RouteVariantRule: Sendable {
    /// route_id en el feed GTFS (p.ej. "5").
    let routeId: String
    /// Sufijo que se añade al nombre corto de la ruta (p.ej. "A" → "5A").
    let suffix: String
    /// Subcadena que debe aparecer en el headsign del viaje (en mayúsculas).
    let headsignContains: String
}

/// Reglas de variante para todas las líneas con extensiones diferenciadas.
/// Se comprueban en orden; la primera coincidencia determina el sufijo.
nonisolated(unsafe) let routeVariantRules: [RouteVariantRule] = [
    // Línea 5: 5A = Astegieta, 5B = Jundiz/Ariñez, 5C = ITV Ariñez
    // "ARIÑEZ ITV" debe ir antes de "ARIÑEZ" para no quedar enmascarado.
    RouteVariantRule(routeId: "5", suffix: "A", headsignContains: "ASTEGIETA"),
    RouteVariantRule(routeId: "5", suffix: "C", headsignContains: "ARIÑEZ ITV"),
    RouteVariantRule(routeId: "5", suffix: "B", headsignContains: "ARIÑEZ"),
    RouteVariantRule(routeId: "5", suffix: "B", headsignContains: "JUNDIZ"),
]

/// Devuelve el sufijo de variante (p.ej. "A") para un viaje dado, o `nil` si no aplica ninguna regla.
nonisolated func variantSuffix(routeId: String, headsign: String) -> String? {
    let upper = headsign.uppercased()
    for rule in routeVariantRules where rule.routeId == routeId {
        if upper.contains(rule.headsignContains) {
            return rule.suffix
        }
    }
    return nil
}
