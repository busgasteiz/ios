import CoreLocation

// MARK: - Constantes de ámbito de aplicación

/// Centro geográfico de Vitoria-Gasteiz (EPSG:4326).
let vitoriaCenterCoordinate = CLLocationCoordinate2D(latitude: 42.846667, longitude: -2.673056)

/// Radio en metros del área urbana de referencia. Si el usuario está más lejos de este
/// radio desde el centro, se utiliza la posición predeterminada en lugar de la GPS.
let vitoriaCenterRadiusMeters: CLLocationDistance = 10_000
