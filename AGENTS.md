# AGENTS.md — BusGasteiz iOS

Aplicación para iOS que visualiza la información en tiempo real de los autobuses urbanos y el tranvía de Vitoria-Gasteiz.

---

## Estructura del proyecto

```
ios/
├── BusGasteiz.xcodeproj/
└── BusGasteiz/
    └── BusGasteiz/               ← Código fuente principal
        ├── BusGasteizApp.swift   # Entry point; inyecta los @Observable en el entorno
        ├── ContentView.swift     # TabView raíz (3 pestañas)
        ├── Models.swift          # Structs de datos (StopInfo, TripInfo, GTFSData, …)
        ├── DataManager.swift     # Singleton @Observable; descarga, caché y refresco de datos
        ├── GTFSParser.swift      # Parsers GTFS/GTFS-RT y motor de consulta de llegadas
        ├── ProtoReader.swift     # Decodificador protobuf de bajo nivel (sin dependencias)
        ├── ZIPExtractor.swift    # Descompresión de ZIPs en memoria
        ├── LocationManager.swift # CLLocationManager envuelto en @Observable
        ├── FavoritesManager.swift# @Observable; paradas y líneas favoritas (UserDefaults)
        ├── NearbyStopsView.swift # Pestaña "Stops" — lista de paradas cercanas
        ├── BusMapView.swift      # Pestaña "Map" — mapa MapKit con anotaciones de paradas
        ├── StopDetailView.swift  # Sheet de detalle de parada; llegadas en tiempo real
        ├── FavoritesView.swift   # Pestaña "Favorites" — lista de favoritos
        ├── StopIconView.swift    # Componentes visuales reutilizables (StopIconView, RouteBadgeView)
        ├── Localizable.xcstrings # Cadenas localizadas (en / es / eu)
        └── Assets.xcassets/
```

---

## Tecnologías y requisitos

| Elemento                | Valor                          |
|-------------------------|--------------------------------|
| Lenguaje                | Swift                          |
| Framework UI            | SwiftUI                        |
| Observación de estado   | `@Observable` (Swift 5.9)      |
| iOS mínimo              | 15.0                           |
| Mapas                   | MapKit (`Map`, `Annotation`)   |
| Localización            | `String(localized:)` + `.xcstrings` |
| Persistencia favoritos  | `UserDefaults`                 |
| Red                     | `URLSession.shared`            |

---

## Arquitectura

### Flujo de datos

```
DataManager (singleton @Observable @MainActor)
    ├── Descarga GTFS ZIP (Tuvisa)          → gtfsDir (Documents/GTFSCache/GTFS_Data/)
    ├── Descarga GTFS ZIP (Euskotren)       → euskotrenGtfsDir (Documents/GTFSCache/Euskotren_Data/)
    ├── Descarga RT .pb (Tuvisa)            → pbURL
    ├── Descarga RT .pb (Euskotren)         → euskotrenPbURL
    ├── parseInBackground() [Task.detached]
    │       loadGTFS()           → GTFSData (Tuvisa)
    │       loadEuskoTranGTFS()  → GTFSData (tranvía VGZ)
    │       merge tram → main GTFSData
    │       loadTripDelays() ×2  → [String: TripDelayInfo]
    ├── gtfsData: GTFSData?
    ├── tripDelays: [String: TripDelayInfo]
    └── activeStopIds: Set<String>   ← precomputado 1 vez tras cada carga
```

Los datos estáticos (GTFS ZIP) se refrescan cada **10 minutos**. El feed RT se descarga en cada refresco.

### Fusión de datos de tranvía

`loadEuskoTranGTFS()` filtra el GTFS de Euskotren al operador `EUS_TrGa` (tranvía de Vitoria-Gasteiz):
- Solo se cargan líneas TG1, TG2 y 41.
- Los andenes (Quay, `location_type=0`) se agrupan por su `StopPlace` padre (`location_type=1`) para evitar duplicados en el mapa.
- Las paradas resultantes llevan `StopInfo.isTram = true` y se muestran con icono de tranvía.
- Las fechas activas del tranvía se calculan expandiendo `calendar.txt` (horario semanal) más excepciones de `calendar_dates.txt`.

---

## Fuentes de datos

| Recurso                          | URL                                                                                              |
|----------------------------------|--------------------------------------------------------------------------------------------------|
| GTFS estático Tuvisa             | `https://www.vitoria-gasteiz.org/we001/http/vgTransit/google_transit.zip`                        |
| RT trip updates Tuvisa           | `https://www.vitoria-gasteiz.org/we001/http/vgTransit/realTime/tripUpdates.pb`                   |
| GTFS estático Euskotren          | `https://opendata.euskadi.eus/transport/moveuskadi/euskotren/gtfs_euskotren.zip`                  |
| RT trip updates Euskotren (tram) | `https://opendata.euskadi.eus/transport/moveuskadi/euskotren/gtfsrt_euskotren_trip_updates.pb`    |

---

## Modelos de datos principales (`Models.swift`)

| Struct            | Propósito                                                           |
|-------------------|---------------------------------------------------------------------|
| `StopInfo`        | Parada (id, name, nameEu, nameEs, lat, lon, isTram)                 |
| `TripInfo`        | Viaje (id, routeId, headsign, serviceId)                            |
| `RouteInfo`       | Línea (id, shortName, longName, color hex)                          |
| `StopTimeEntry`   | Horario individual (tripId, stopSequence, arrivalSecs)              |
| `GTFSData`        | Contenedor: stops, trips, routes, stopArrivals, activeDates         |
| `TripDelayInfo`   | Retraso RT: generalDelay, stopDelays[stopId], vehicleLabel          |
| `UpcomingArrival` | Resultado de consulta: horario programado + predicho + retraso      |
| `NearbyStop`      | Parada + distancia + hasArrivals (para colorear iconos)             |

`StopInfo.localizedName` devuelve `nameEu`/`nameEs` según el idioma del sistema, con fallback a `name`.

---

## Motor de consulta (`GTFSParser.swift`)

| Función                            | Descripción                                                                            |
|------------------------------------|----------------------------------------------------------------------------------------|
| `loadGTFS(folder:)`                | Carga GTFS estático Tuvisa (routes, trips, stops, translations, calendar_dates, stop_times) |
| `loadEuskoTranGTFS(folder:)`       | Carga y filtra GTFS Euskotren al tranvía de Vitoria-Gasteiz                            |
| `loadActiveDatesFromCalendar()`    | Expande `calendar.txt` a fechas individuales + aplica excepciones                      |
| `loadTripDelays(data:)`            | Decodifica feed GTFS-RT protobuf → `[String: TripDelayInfo]`                           |
| `computeStopsWithUpcomingArrivals` | Calcula `Set<String>` de stop_id con llegadas en los próximos 60 min (aritmética epoch) |
| `computeNearbyStops`               | Paradas en radio Haversine, ordenadas por distancia                                    |
| `computeStopsInBounds`             | Paradas en bounding box del mapa visible                                               |
| `computeArrivals`                  | Llegadas de una parada en ventana de 60 min con retrasos RT aplicados                  |
| `computeNextArrivals`              | Primer servicio futuro por línea (hasta 7 días), usado en estado vacío de 60 min       |
| `resolveServiceDate`               | Determina si un horario cae hoy o ayer (servicios nocturnos que cruzan medianoche)      |

**Optimización de rendimiento**: `computeStopsWithUpcomingArrivals` usa aritmética de epoch pura (sin `DateFormatter` en el bucle). Los `DateFormatter` para GTFS son singletons de módulo (`nonisolated private let`) para evitar su recreación en cada llamada.

---

## Vistas principales

### `ContentView` — TabView raíz

Tres pestañas:
1. **Stops** (`NearbyStopsView`) — lista de paradas cercanas ordenadas por distancia.
2. **Map** (`BusMapView`) — mapa con anotaciones de paradas; se actualiza continuamente al arrastrar (`.continuous`).
3. **Favorites** (`FavoritesView`) — paradas y líneas guardadas como favoritas.

### `NearbyStopsView`

- Muestra el estado de carga de `DataManager` (`.idle`, `.loading`, `.failed`, `.ready`).
- Cada fila usa `StopIconView` (48 pt) + nombre de parada + distancia.
- Icono en gris si `!NearbyStop.hasArrivals` (sin llegadas en los próximos 60 min).
- Navega a `StopDetailView` al pulsar una parada.

### `BusMapView`

- Anotaciones `StopAnnotationView` (usa `StopIconView`) actualizadas en cada frame de desplazamiento del mapa (`.onMapCameraChange(frequency: .continuous)`).
- Usa `recomputeTask` para cancelar el cálculo anterior antes de lanzar uno nuevo.
- Al seleccionar una anotación abre un sheet con `StopDetailView`.
- Menú de radio de búsqueda (100–2000 m); botón de recentrado en la posición del usuario.

### `StopDetailView`

- Muestra llegadas en los próximos 60 min con `computeArrivals`.
- Si no hay llegadas, muestra `ContentUnavailableView` + sección **"Next scheduled services"** con `computeNextArrivals` (primer servicio por línea en los próximos 7 días).
- `ArrivalRowView.timeLabel`: `Xm` si ≤ 60 min, `Xh Ym` si > 60 min.
- Botón de estrella (favorito) a la izquierda; botón de cierre a la derecha.
- Líneas de llegada muestran `RouteBadgeView` (badge cuadrado con color de línea).

### `FavoritesView`

- Muestra paradas favoritas (`FavoritesManager.favoriteStopIds`) y líneas favoritas por parada (`favoriteRouteKeys`).
- Estado vacío con instrucciones si no hay favoritos.

---

## Componentes visuales (`StopIconView.swift`)

### `StopIconView`
Icono circular con:
- Fondo sólido `Color.accentColor` (azul) o `systemGray` si `hasArrivals == false`.
- Icono `bus.fill` / `tram.fill` en blanco.
- Reborde blanco de 4 pt y sombra sutil.
- Parámetros: `size` (por defecto 28 pt), `isTram`, `hasArrivals`.

### `RouteBadgeView`
Badge cuadrado de 48 pt (44 pt interior + 2 pt reborde):
- `RoundedRectangle(cornerRadius: 10/12)` con color de la línea.
- Color de texto determinado por luminancia (umbral 140): negro para fondos claros, blanco para oscuros.
- Escala el texto con `minimumScaleFactor(0.5)`.

---

## Gestión de favoritos (`FavoritesManager.swift`)

- `favoriteStopIds: Set<String>` — paradas enteras guardadas.
- `favoriteRouteKeys: Set<String>` — claves `"stopId::routeShortName"` para líneas concretas.
- Persistencia en `UserDefaults` (`"favoriteStops"` y `"favoriteRoutes"`).
- Inyectado como `@Observable` en el entorno de SwiftUI.

---

## Localización

- Idiomas: **inglés** (base), **castellano** (`es`), **euskera** (`eu`).
- Si el idioma del dispositivo no coincide con ninguno, se usa el inglés.
- Todos los strings visibles al usuario deben estar en `Localizable.xcstrings`.
- Usar `String(localized: "Key")` o `Text("Key")` (SwiftUI lo resuelve automáticamente).
- Los nombres de paradas tienen versión en euskera (`nameEu`) y castellano (`nameEs`) según `translations.txt` de Tuvisa. `StopInfo.localizedName` los selecciona automáticamente.

---

## Compatibilidad iOS 16

`@Observable` requiere iOS 17, pero el target mínimo es iOS 15. Workaround en `DataManager`:
- Usa `notifyViewsOnRunLoop()` y `.onReceive` con Combine para que SwiftUI observe cambios en iOS 16, donde el executor de `@MainActor` no está integrado con `RunLoop.main`.

---

## Convenciones de código

- Un commit por cada funcionalidad nueva o corrección relevante.
- No crear `DateFormatter` dentro de bucles; usar singletons `nonisolated private let`.
- Las funciones de consulta GTFS son `nonisolated` para poder ejecutarse en `Task.detached`.
- Las conversiones `UInt64 → Int32` usan `Int64(bitPattern:)` + `Int32(truncatingIfNeeded:)` para preservar valores negativos (retrasos).
- Seguir las recomendaciones del Human Interface Guidelines de Apple para iOS.

---

## Diseño de UI

- Iconos de parada: circulares, 48 pt (con reborde blanco incluido), color de acento o gris según disponibilidad de servicio.
- Badges de línea: cuadrados, 48 pt, color de la línea, texto blanco o negro según luminancia.
- Mapa en estilo `.standard` de MapKit.
- Anotaciones seleccionadas se amplían (scale effect) para indicar selección.
