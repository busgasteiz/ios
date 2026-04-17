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

// MARK: - Badge cuadrado de línea (listas y favoritos)

/// Badge cuadrado de 48 pt con borde blanco, igual que StopIconView.
/// Muestra el número/nombre de línea centrado sobre el color de la ruta.
/// Usa `outerSize` para escalar el badge (por defecto 48 pt; usa ~28 para versión pequeña).
struct RouteBadgeView: View {
    let routeShortName: String
    let colorHex: String
    var outerSize: CGFloat = 48

    private var inner: CGFloat  { outerSize - 4 }
    private var radius: CGFloat { inner * 10 / 44 }
    private var fontSize: CGFloat { inner * 15 / 44 }

    private var fillColor: Color { Color(hex: colorHex) }

    private var textColor: Color {
        let c = colorHex.lowercased()
        if c.isEmpty || c == "ffffff" { return .black }
        guard c.count == 6,
              let r = UInt8(c.prefix(2), radix: 16),
              let g = UInt8(c.dropFirst(2).prefix(2), radix: 16),
              let b = UInt8(c.dropFirst(4), radix: 16) else { return .white }
        let lum = 0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)
        return lum > 140 ? .black : .white
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius + 2)
                .fill(Color.white)
                .frame(width: outerSize, height: outerSize)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)

            RoundedRectangle(cornerRadius: radius)
                .fill(fillColor)
                .frame(width: inner, height: inner)

            Text(routeShortName)
                .font(.system(size: fontSize, weight: .bold))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(textColor)
                .frame(width: inner - 4)
        }
    }
}

#Preview("RouteBadgeView") {
    HStack(spacing: 16) {
        RouteBadgeView(routeShortName: "1",   colorHex: "E30613")
        RouteBadgeView(routeShortName: "L1",  colorHex: "0057A8")
        RouteBadgeView(routeShortName: "T1",  colorHex: "FFD700")
        RouteBadgeView(routeShortName: "L2",  colorHex: "FFFFFF")
    }
    .padding()
}
