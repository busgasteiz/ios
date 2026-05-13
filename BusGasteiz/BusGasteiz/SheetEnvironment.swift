import SwiftUI

// MARK: - Environment keys para el estado del sheet de parada

private struct IsSheetMinimizedKey: EnvironmentKey {
    static let defaultValue = false
}

private struct DismissSheetKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    /// `true` cuando el sheet de parada está colapsado al detent mínimo.
    var isSheetMinimized: Bool {
        get { self[IsSheetMinimizedKey.self] }
        set { self[IsSheetMinimizedKey.self] = newValue }
    }

    /// Cierra el sheet de parada (equivalente a pulsar el botón X).
    var dismissSheet: () -> Void {
        get { self[DismissSheetKey.self] }
        set { self[DismissSheetKey.self] = newValue }
    }
}
