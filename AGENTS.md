# AGENTS.md — BusGasteiz iOS

Aplicación para iOS que visualiza la información en tiempo real de los autobuses urbanos y el tranvía de Vitoria-Gasteiz.

---

## Estructura del proyecto

```
ios/
├── BusGasteiz.xcodeproj/
└── BusGasteiz/
    └── BusGasteiz/               ← Código fuente principal
        ├── BusGasteizApp.swift        # Entry point; inyecta los @Observable en el entorno; refresco al volver de background
        ├── ContentView.swift          # TabView raíz (3 pestañas) + pre-calentamiento de MapKit; refresco al cambiar pestaña
        ├── Models.swift               # Structs de datos (StopInfo, TripInfo, GTFSData, …)
        ├── DataManager.swift          # Singleton @Observable; descarga, caché y refresco de datos
        ├── GTFSParser.swift           # Parsers GTFS/GTFS-RT y motor de consulta de llegadas
        ├── ProtoReader.swift          # Decodificador protobuf de bajo nivel (sin dependencias)
        ├── ZIPExtractor.swift         # Descompresión de ZIPs en memoria
        ├── LocationManager.swift      # CLLocationManager envuelto en @Observable
        ├── FavoritesManager.swift     # @Observable; paradas y líneas favoritas (UserDefaults)
        ├── AppSettings.swift          # @Observable; ajustes compartidos (radio de búsqueda)
        ├── NavigationDestination.swift# Enum AppNavDestination para navegación tipada entre pestañas
        ├── RouteVariantConfig.swift   # Lógica de variantes de línea (sufijos A/B/C según headsign)
        ├── NearbyStopsView.swift      # Pestaña "Stops" — lista de paradas cercanas
        ├── BusMapView.swift           # Pestaña "Map" — mapa MapKit con anotaciones de paradas
        ├── StopDetailView.swift       # Detalle de parada; llegadas en tiempo real
        ├── FavoritesView.swift        # Pestaña "Favorites" — lista de favoritos
        ├── AboutView.swift            # Sheet "About": licencias, fuentes de datos, privacidad
        ├── StopIconView.swift         # Componentes visuales reutilizables (StopIconView, RouteBadgeView)
        ├── SheetCloseButton.swift     # Botón de cierre de sheet adaptativo (iOS 26+ / anterior)
        ├── BridgingHeader.h           # Bridging header (vacío en producción)
        ├── Localizable.xcstrings      # Cadenas localizadas (en / es / eu)
        └── Assets.xcassets/
```

---

## Tecnologías y requisitos

| Elemento                | Valor                          |
|-------------------------|--------------------------------|
| Lenguaje                | Swift                          |
| Framework UI            | SwiftUI                        |
| Observación de estado   | `@Observable` (Swift 5.9)      |
| iOS mínimo              | 17.0                           |
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
    ├── Descarga alertas .pb (Tuvisa)       → tuvisaAlertsPbURL    (no crítico: errores ignorados)
    ├── Descarga alertas .pb (Euskotren)    → euskotrenAlertsPbURL (no crítico: errores ignorados)
    ├── parseInBackground() [Task.detached]
    │       loadGTFS()           → GTFSData (Tuvisa)
    │       loadEuskoTranGTFS()  → GTFSData (tranvía VGZ)
    │       merge tram → main GTFSData
    │       loadTripDelays() ×2  → [String: TripDelayInfo]
    │       loadAlerts() ×2      → ServiceAlerts (fusionados)
    ├── gtfsData: GTFSData?
    ├── tripDelays: [String: TripDelayInfo]
    ├── serviceAlerts: ServiceAlerts
    ├── activeStopIds: Set<String>   ← precomputado 1 vez tras cada carga
    ├── version: Int                 ← se incrementa con cada recarga; útil para onChange
    ├── isRefreshing: Bool           ← true mientras forceRefresh() está en curso
    └── needsRefresh: Bool           ← true cuando han pasado ≥10 min desde la última carga
```

Los datos estáticos (GTFS ZIP) se refrescan cada **10 minutos**. El feed RT y las alertas se descargan en cada refresco. `forceRefresh()` fuerza una recarga inmediata (usado por el botón de recargar manual). Incluye un guard `guard !isRefreshing else { return }` para evitar ejecuciones concurrentes.

**Refresco automático al volver de segundo plano o cambiar de pestaña**: si `gtfsData != nil && needsRefresh`, se llama a `forceRefresh()` (con animación de spinner). Si `gtfsData == nil`, las vistas gestionan la carga inicial con `refreshIfNeeded()` desde su `onAppear`.

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
| RT alertas Tuvisa                | `https://opendata.euskadi.eus/transport/moveuskadi/tuvisa/gtfsrt_tuvisa_alerts.pb`               |
| GTFS estático Euskotren          | `https://opendata.euskadi.eus/transport/moveuskadi/euskotren/gtfs_euskotren.zip`                  |
| RT trip updates Euskotren (tram) | `https://opendata.euskadi.eus/transport/moveuskadi/euskotren/gtfsrt_euskotren_trip_updates.pb`    |
| RT alertas Euskotren (tram)      | `https://opendata.euskadi.eus/transport/moveuskadi/euskotren/gtfsrt_euskotren_alerts.pb`          |

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
| `ServiceAlert`    | Alerta de servicio: headerText, descriptionText                     |
| `ServiceAlerts`   | Contenedor: stopAlerts[stopId], routeAlerts[routeId], stopIds, routeIds |
| `UpcomingArrival` | Resultado de consulta: horario programado + predicho + retraso + hasAlert |
| `RouteTag`        | Línea resumida para listas: shortName, color, hasAlert              |
| `NearbyStop`      | Parada + distancia + hasArrivals + routes ([RouteTag]) + hasAlert   |

`StopInfo.localizedName` devuelve `nameEu`/`nameEs` según el idioma del sistema, con fallback a `name`.

---

## Motor de consulta (`GTFSParser.swift`)

| Función                            | Descripción                                                                            |
|------------------------------------|----------------------------------------------------------------------------------------|
| `loadGTFS(folder:)`                | Carga GTFS estático Tuvisa (routes, trips, stops, translations, calendar_dates, stop_times) |
| `loadEuskoTranGTFS(folder:)`       | Carga y filtra GTFS Euskotren al tranvía de Vitoria-Gasteiz                            |
| `loadActiveDatesFromCalendar()`    | Expande `calendar.txt` a fechas individuales + aplica excepciones                      |
| `loadTripDelays(data:)`            | Decodifica feed GTFS-RT protobuf → `[String: TripDelayInfo]`                           |
| `loadAlerts(data:)`                | Decodifica feed GTFS-RT Alerts → `ServiceAlerts` (stopAlerts + routeAlerts)            |
| `routesForStop(stopId:gtfsData:alerts:)` | Calcula `[RouteTag]` para una parada, marcando líneas con alerta               |
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

Tres pestañas con `NavigationStack` independiente cada una:
1. **Stops** (`NearbyStopsView`) — lista de paradas cercanas ordenadas por distancia.
2. **Map** (`BusMapView`) — mapa con anotaciones de paradas; se actualiza continuamente al arrastrar (`.continuous`).
3. **Favorites** (`FavoritesView`) — paradas y líneas guardadas como favoritas.

Tocar una pestaña ya seleccionada resetea su `NavigationPath` al nivel raíz.

`.onChange(of: selectedTab)` dispara `forceRefresh()` (con animación) si `gtfsData != nil && needsRefresh` al cambiar de pestaña.

`ContentView` inserta un `MapKitPrewarm` (invisible, `UIViewRepresentable`) en el árbol al arrancar para inicializar Metal/MapKit antes de que el usuario abra la pestaña de mapa, eliminando el freeze de ~1 s en la primera apertura.

### `NearbyStopsView`

- Muestra el estado de carga de `DataManager` (`.idle`, `.loading`, `.failed`, `.ready`).
- Lee `appSettings.searchRadius` del entorno para filtrar paradas por distancia.
- Cada fila usa `StopIconView` (48 pt) + nombre de parada + distancia + badges de línea (`RouteBadgeView`).
- Icono en gris si `!NearbyStop.hasArrivals` (sin llegadas en los próximos 60 min).
- Icono de alerta si `NearbyStop.hasAlert`.
- Navega a `StopDetailView` (`.stopDetail`) al pulsar una parada.
- Botón "About" en la barra de navegación que abre `AboutView` como sheet.
- Si no hay paradas en el radio actual, muestra un mensaje con un enlace tappable **"Increase search radius to Xm"** que salta automáticamente al siguiente radio disponible en `[100, 200, 300, 500, 1000]`.

### `BusMapView`

- Anotaciones `StopAnnotationView` (usa `StopIconView`) actualizadas en cada frame de desplazamiento del mapa (`.onMapCameraChange(frequency: .continuous)`).
- Usa `recomputeTask` para cancelar el cálculo anterior antes de lanzar uno nuevo.
- Al seleccionar una anotación abre un sheet con `StopDetailView`.
- Menú de radio de búsqueda (100–1000 m); botón de recentrado en la posición del usuario.
- Overlay con `ProgressView` o panel de error según `DataManager.loadState`, para garantizar que la pantalla nunca queda en blanco.

### `StopDetailView`

- Muestra llegadas en los próximos 60 min con `computeArrivals`.
- Si no hay llegadas, muestra `ContentUnavailableView` + sección **"Next scheduled services"** con `computeNextArrivals` (primer servicio por línea en los próximos 7 días).
- Muestra alertas de servicio (`serviceAlerts.stopAlerts`) al principio de la lista si las hay.
- `ArrivalRowView.timeLabel`: `Xm` si ≤ 60 min, `Xh Ym` si > 60 min.
- Botón de estrella (favorito) a la izquierda; botón de cierre a la derecha.
- Líneas de llegada muestran `RouteBadgeView` (badge cuadrado con color de línea).
- Desde "Next scheduled services", navega a una vista de llegadas por línea (`.routeArrivals`).

### `FavoritesView`

- Muestra paradas favoritas (`FavoritesManager.favoriteStopIds`) y líneas favoritas por parada (`favoriteRouteKeys`).
- Estado vacío con instrucciones si no hay favoritos.
- Muestra `ProgressView` mientras carga y un panel de error si `loadState == .failed`, para garantizar que la pantalla nunca queda en blanco.

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

### `AboutView`

Sheet accesible desde el botón de información en `NearbyStopsView`. Muestra:
- Copyright y términos de uso.
- Política de privacidad (la app no recoge ningún dato personal).
- Enlace a la licencia Apache 2.0.
- Fuentes de datos con licencia CC BY (Tuvisa, Open Data Euskadi/Moveuskadi) y paletas de color CC BY-NC-SA.
- Enlace al repositorio de GitHub.
- Sección de pruebas en builds DEBUG (`simulateAlerts`).

---

## Ajustes compartidos (`AppSettings.swift`)

`@Observable final class AppSettings` centraliza los ajustes de usuario que afectan a más de una vista:

| Propiedad       | Tipo     | Persistencia          | Descripción                        |
|-----------------|----------|-----------------------|------------------------------------|
| `searchRadius`  | `Double` | `UserDefaults`        | Radio de búsqueda de paradas en metros (por defecto 200 m) |

Se inyecta como `@Observable` en el entorno de SwiftUI desde `BusGasteizApp`. Usar `@Environment(AppSettings.self)` para acceder a él en cualquier vista.

---

## Navegación tipada (`NavigationDestination.swift`)

El enum `AppNavDestination: Hashable` centraliza todos los destinos de navegación push compartidos entre pestañas:

| Case                                                          | Destino                                          |
|---------------------------------------------------------------|--------------------------------------------------|
| `.stopDetail(stop:distance:starLeading:)`                     | `StopDetailView` — detalle de llegadas de parada |
| `.routeArrivals(stop:distance:routeShortName:routeColor:)`    | Vista de llegadas filtradas por línea             |

Cada `NavigationStack` declara `.navigationDestination(for: AppNavDestination.self)` para manejar estos casos.

---

## Variantes de línea (`RouteVariantConfig.swift`)

Algunas líneas tienen ramales diferenciados que se identifican mediante un sufijo en el nombre (p.ej. `5A`, `5B`, `5C`). La función `variantSuffix(routeId:headsign:)` aplica las reglas configuradas en `RouteVariantConfig.rules` para determinar qué sufijo añadir al `shortName` de la línea al mostrarla en la UI.

Para añadir variantes a una nueva línea, añadir entradas al array `rules` dentro de `variantSuffix`. Las reglas se evalúan en orden; la primera coincidencia gana, por lo que las cadenas más específicas deben ir antes.

---

## Gestión de favoritos (`FavoritesManager.swift`)

- `favoriteStopIds: Set<String>` — paradas enteras guardadas.
- `favoriteRouteKeys: Set<String>` — claves `"stopId::routeShortName"` para líneas concretas.
- Persistencia en iCloud Key-Value Store (`NSUbiquitousKeyValueStore`) bajo las claves `"favoriteStops"` y `"favoriteRoutes"`.
- Inyectado como `@Observable` en el entorno de SwiftUI.

### Formato de clave de línea favorita y advertencia con IDs de Euskotren

Las claves de línea-en-parada usan el separador `"::"`: `"<stopId>::<routeShortName>"`.

> ⚠️ **Los IDs de parada de Euskotren terminan en dos puntos** (p.ej. `ES:Euskotren:StopPlace:1559:`).
> Esto produce triples `":::"` en la clave compuesta. Al parsear, **siempre dividir por la última
> ocurrencia de `"::"` ** (no la primera), ya que los nombres de línea nunca contienen `":"`.
>
> En iOS: `key.range(of: "::", options: .backwards)` (ya implementado en `parsedRouteKeys`).
>
> No usar `components(separatedBy: "::")`: encontraría el primer `"::"` y dejaría el trailing `":"`
> del stopId fuera, rompiendo la búsqueda en `gtfs.stops`.

---

## Localización

- Idiomas: **inglés** (base), **castellano** (`es`), **euskera** (`eu`).
- Si el idioma del dispositivo no coincide con ninguno, se usa el inglés.
- Todos los strings visibles al usuario deben estar en `Localizable.xcstrings`.
- Usar `String(localized: "Key")` o `Text("Key")` (SwiftUI lo resuelve automáticamente).
- Los nombres de paradas tienen versión en euskera (`nameEu`) y castellano (`nameEs`) según `translations.txt` de Tuvisa. `StopInfo.localizedName` los selecciona automáticamente.

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
