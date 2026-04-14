import XCTest

final class BusGasteizUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Verifica que la app sale del estado "Iniciando…" y muestra la lista de paradas
    /// (o el estado vacío si no hay paradas cercanas) en un tiempo razonable.
    /// Detecta el bug de iOS 16 donde la UI se quedaba bloqueada en la carga inicial.
    @MainActor
    func testNearbyStopsListLoads() throws {
        let app = XCUIApplication()
        app.launch()

        // Aceptar el diálogo de permisos de localización si aparece
        let alert = app.alerts.firstMatch
        if alert.waitForExistence(timeout: 5) {
            // Buscar botón de "Allow" en inglés o español
            var tapped = false
            for i in 0..<alert.buttons.count {
                let btn = alert.buttons.element(boundBy: i)
                let label = btn.label.lowercased()
                if label.contains("allow") || label.contains("permit") || label.contains("usar") {
                    btn.tap()
                    tapped = true
                    break
                }
            }
            if !tapped {
                alert.buttons.element(boundBy: alert.buttons.count - 1).tap()
            }
        }

        // Esperar hasta 90 s a que aparezca la tabla con paradas O el estado vacío.
        // Cualquiera de los dos indica que la carga se completó correctamente.
        let table       = app.tables.firstMatch
        let emptyLabel  = app.staticTexts["Sin paradas cercanas"]
        let errorButton = app.buttons["Reintentar"]

        let loaded = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                table.exists || emptyLabel.exists || errorButton.exists
            },
            object: nil
        )
        let waiter = XCTWaiter.wait(for: [loaded], timeout: 180)

        // El texto "Iniciando…" no debe seguir visible al terminar la espera
        XCTAssertFalse(
            app.staticTexts["Iniciando…"].exists,
            "La app sigue bloqueada en 'Iniciando…' — el observador de @EnvironmentObject no recibió la notificación"
        )

        XCTAssertEqual(
            waiter, .completed,
            "La lista de paradas (o el estado vacío/error) debe aparecer en 90 s"
        )
    }
}
