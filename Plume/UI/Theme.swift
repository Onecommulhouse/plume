import SwiftUI
import AppKit
import CoreText

/// Charte ONE COM : bleu nuit, jaune moutarde, blanc cassé, neutres chauds, Montserrat.
enum Theme {
    static let navy = Color(hex: 0x081A35)
    static let mustard = Color(hex: 0xF8BB04)
    static let gold = Color(hex: 0xE3A51A)
    static let paper = Color(hex: 0xFEFEFE)
    static let canvas = Color(hex: 0xF7F7F5)
    static let line = Color(hex: 0xE6E6E2)
    static let muted = Color(hex: 0x6E6E6A)
    static let soft = Color(hex: 0x9C9C97)
    static let mustardTint = Color(hex: 0xF8BB04, opacity: 0.16)

    static let goldGradient = LinearGradient(
        stops: [
            .init(color: mustard, location: 0),
            .init(color: gold, location: 0.55),
            .init(color: mustard, location: 1),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .medium: name = "Montserrat-Medium"
        case .semibold: name = "Montserrat-SemiBold"
        case .bold: name = "Montserrat-Bold"
        case .heavy, .black: name = "Montserrat-ExtraBold"
        default: name = "Montserrat-Regular"
        }
        if NSFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: weight)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum Fonts {
    static func registerBundledFonts() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

/// Carte blanche arrondie 12 px, bordure qui passe en jaune au survol.
struct Card<Content: View>: View {
    var padding: CGFloat
    var content: Content
    @State private var hovering = false

    init(padding: CGFloat = 22, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Theme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(hovering ? Theme.mustard : Theme.line, lineWidth: 1)
            )
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// Bouton pilule au dégradé doré, léger lift au survol.
struct PillButtonStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        PillButtonBody(configuration: configuration, prominent: prominent)
    }

    private struct PillButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(Theme.font(13, .semibold))
                .foregroundStyle(Theme.navy)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background {
                    if prominent {
                        Capsule().fill(Theme.goldGradient)
                    } else {
                        Capsule().fill(Theme.paper)
                            .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
                    }
                }
                .shadow(color: prominent && hovering ? Theme.gold.opacity(0.35) : .clear, radius: 8, y: 3)
                .offset(y: hovering && isEnabled ? -1 : 0)
                .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

/// Petit badge texte (appli, statut…).
struct Tag: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.font(11, .semibold))
            .foregroundStyle(Theme.navy)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(Theme.mustardTint))
    }
}

/// La marque Plume : des barres d'onde moutarde.
struct WaveMark: View {
    var color: Color = Theme.mustard
    var heights: [CGFloat] = [0.30, 0.52, 0.76, 1.0, 0.76, 0.58, 0.40]
    var barWidth: CGFloat = 3
    var spacing: CGFloat = 2.5

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(heights.enumerated()), id: \.offset) { _, h in
                    Capsule()
                        .fill(color)
                        .frame(width: barWidth, height: max(barWidth, geo.size.height * h))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
