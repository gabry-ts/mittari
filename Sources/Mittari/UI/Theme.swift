import SwiftUI
import MittariCore

/// Mittari's look: Tuuli's airy cards on a warm backdrop, with amber as the one accent.
/// Orange and coral only appear when a window gets close to its limit.
enum Theme {
    static let amber = Color(red: 0.98, green: 0.68, blue: 0.16)
    static let warning = Color(red: 0.97, green: 0.47, blue: 0.18)
    static let critical = Color(red: 0.91, green: 0.27, blue: 0.30)
    static let cardRadius: CGFloat = 16

    static func color(_ level: Gauge.Level) -> Color {
        switch level {
        case .normal: amber
        case .warning: warning
        case .critical: critical
        }
    }

    /// Soft series colors for charts and breakdowns, amber first.
    static let palette: [Color] = [
        amber,
        Color(red: 0.36, green: 0.64, blue: 1.0),
        Color(red: 0.62, green: 0.52, blue: 0.95),
        Color(red: 0.30, green: 0.78, blue: 0.70),
        Color(red: 0.95, green: 0.45, blue: 0.42),
    ]
}

// MARK: - Backgrounds and cards

/// Blurs whatever is behind the window.
struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// The window backdrop: the desktop blurred through the window, tinted a pale warm white
/// with two soft amber glows. "Reduce transparency" turns the blur solid automatically.
struct AirBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        ZStack {
            BehindWindowBlur()
                .opacity(0.87)
            LinearGradient(
                colors: dark
                    ? [Color(red: 0.13, green: 0.11, blue: 0.08), Color(red: 0.08, green: 0.07, blue: 0.06)]
                    : [Color(red: 1.0, green: 0.97, blue: 0.91), Color(red: 1.0, green: 0.99, blue: 0.97)],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(0.68)
            GeometryReader { proxy in
                glow(Theme.amber.opacity(dark ? 0.16 : 0.20), radius: proxy.size.width * 0.5)
                    .position(x: proxy.size.width * 0.15, y: proxy.size.height * 0.1)
                glow(Color(red: 1.0, green: 0.82, blue: 0.55).opacity(dark ? 0.10 : 0.22), radius: proxy.size.width * 0.4)
                    .position(x: proxy.size.width * 0.9, y: proxy.size.height * 0.95)
            }
        }
        .ignoresSafeArea()
    }

    private func glow(_ color: Color, radius: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color, color.opacity(0)], center: .center, startRadius: 0, endRadius: radius))
            .frame(width: radius * 2, height: radius * 2)
    }
}

/// A frosted-looking card with a hairline highlight.
struct Card<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.6),
                in: .rect(cornerRadius: Theme.cardRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }
}

/// Scrollable page with the air backdrop, a large title and cards stacked below.
struct AirPage<Content: View>: View {
    let title: String
    var subtitle: String?
    /// Off when the page sits inside a view that already draws the backdrop.
    var drawsBackground = true
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                    if let subtitle {
                        Text(subtitle)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 4)
                content
            }
            .padding(24)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background { if drawsBackground { AirBackground() } }
    }
}

struct CardTitle: View {
    let title: String
    var systemImage: String?

    var body: some View {
        Label {
            Text(title)
        } icon: {
            if let systemImage { Image(systemName: systemImage) }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}
