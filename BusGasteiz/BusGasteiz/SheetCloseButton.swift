import SwiftUI

// MARK: - Botón de cierre de sheet

/// Muestra un icono xmark en iOS 26+ y el texto "Cerrar" en iOS 18 e inferiores.
struct SheetCloseButton: View {
    let action: () -> Void

    var body: some View {
        if #available(iOS 26, *) {
            Button(action: action) {
                Image(systemName: "xmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
        } else {
            Button("Close", action: action)
        }
    }
}
