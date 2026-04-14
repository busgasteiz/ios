//
//  StopIconView.swift
//  BusGasteiz
//

import SwiftUI

// MARK: - Icono circular de parada (lista y mapa)

/// Icono circular con fondo sólido del color de acento, icono blanco y
/// reborde blanco exterior para dar contraste contra cualquier fondo.
/// Se usa tanto en las listas como en las anotaciones del mapa.
struct StopIconView: View {
    var isTram: Bool = false
    /// Diámetro del círculo interior. El reborde añade 4 pt más.
    var size: CGFloat = 28
    /// Si es false, el icono se muestra en gris (sin llegadas programadas).
    var hasArrivals: Bool = true

    private var fillColor: Color { hasArrivals ? Color.accentColor : Color(uiColor: .systemGray) }

    var body: some View {
        ZStack {
            // Reborde blanco exterior
            Circle()
                .fill(Color.white)
                .frame(width: size + 4, height: size + 4)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)

            // Fondo de color sólido
            Circle()
                .fill(fillColor)
                .frame(width: size, height: size)

            // Icono blanco
            Image(systemName: isTram ? "tram.fill" : "bus.fill")
                .font(.system(size: size * 0.40))
                .foregroundStyle(.white)
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        StopIconView(isTram: false, size: 24)
        StopIconView(isTram: true,  size: 28)
        StopIconView(isTram: false, size: 32)
    }
    .padding()
}
