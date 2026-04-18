import SwiftUI

// MARK: - Vista de información de la aplicación

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {

                // ── Copyright ──────────────────────────────────────────────
                Section {
                    Text("© 2026 Ion Jaureguialzo Sarasola. Todos los derechos reservados.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                // ── Términos de servicio ────────────────────────────────────
                Section("Terms of Service") {
                    Text("BusGasteiz is a viewer of publicly available open data from official sources. It is not affiliated with any transport operator or public authority. The app is provided as-is, without warranty of any kind, express or implied.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                // ── Política de privacidad ─────────────────────────────────
                Section("Privacy Policy") {
                    Text("BusGasteiz does not collect, store or share any personal data of any kind.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                // ── Licencia de la app ─────────────────────────────────────
                Section("App License") {
                    Link(destination: URL(string: "https://www.apache.org/licenses/LICENSE-2.0")!) {
                        Label("Apache License 2.0", systemImage: "doc.text")
                    }
                }

                // ── Fuentes de datos ───────────────────────────────────────
                Section("Data Sources") {
                    DataSourceRow(
                        name: "Ayuntamiento de Vitoria-Gasteiz – TUVISA bus lines",
                        license: "CC BY",
                        url: URL(string: "https://www.vitoria-gasteiz.org/wb021/was/contenidoAction.do?uid=app_j34_0021&idioma=es")!
                    )
                    DataSourceRow(
                        name: "Ayuntamiento de Vitoria-Gasteiz – TUVISA real-time data",
                        license: "CC BY",
                        url: URL(string: "https://www.vitoria-gasteiz.org/wb021/was/contenidoAction.do?uid=app_j34_0022&idioma=es")!
                    )
                    DataSourceRow(
                        name: "Open Data Euskadi – Moveuskadi",
                        license: "CC BY",
                        url: URL(string: "https://opendata.euskadi.eus/catalogo/-/moveuskadi-datos-de-la-red-de-transporte-publico-de-euskadi-operadores-horarios-paradas-calendario-tarifas-etc/")!
                    )
                }

                // ── Soporte y código fuente ────────────────────────────────
                Section("Support and Source Code") {
                    Link(destination: URL(string: "https://github.com/busgasteiz")!) {
                        Label("GitHub Repository", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }

                // ── Paletas de colores ─────────────────────────────────────
                Section("Color Palettes") {
                    DataSourceRow(
                        name: "Autumn Rainbow – COLOURlovers",
                        license: "CC BY-NC-SA",
                        url: URL(string: "http://www.colourlovers.com/palette/3240116/%E2%80%A2Autumn_Rainbow%E2%80%A2")!
                    )
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    SheetCloseButton { dismiss() }
                }
            }
        }
    }
}

// MARK: - Fila de fuente de datos

private struct DataSourceRow: View {
    let name: String
    let license: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .foregroundStyle(.primary)
                Text(license)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
