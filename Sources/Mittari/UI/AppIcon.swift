import SwiftUI

/// The app icon, drawn in a 1024 × 1024 space: an amber squircle covering 82% of the
/// canvas (the standard macOS icon padding, as in Tuuli and Kaiku) with a white gauge.
struct AppIconView: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 1024
            ctx.scaleBy(x: s, y: s)
            let body = CGRect(x: 92, y: 92, width: 840, height: 840)
            let squircle = Path(roundedRect: body, cornerRadius: 188, style: .continuous)

            // Drop shadow.
            var shadowCtx = ctx
            shadowCtx.addFilter(.shadow(color: .black.opacity(0.28), radius: 14, x: 0, y: 12))
            shadowCtx.fill(squircle, with: .color(Color(red: 0.93, green: 0.55, blue: 0.10)))

            // Body: warm amber to deep gold.
            ctx.fill(squircle, with: .linearGradient(
                Gradient(colors: [Color(red: 1.0, green: 0.78, blue: 0.30), Color(red: 0.95, green: 0.55, blue: 0.08)]),
                startPoint: CGPoint(x: 512, y: 92), endPoint: CGPoint(x: 512, y: 932)))

            // Soft top sheen and hairline inner edge.
            ctx.fill(squircle, with: .linearGradient(
                Gradient(colors: [.white.opacity(0.22), .white.opacity(0)]),
                startPoint: CGPoint(x: 512, y: 92), endPoint: CGPoint(x: 512, y: 520)))
            ctx.stroke(Path(roundedRect: body.insetBy(dx: 2, dy: 2), cornerRadius: 186, style: .continuous),
                       with: .color(.white.opacity(0.18)), lineWidth: 4)

            // Gauge: a 240° dial opening downwards, two thirds full.
            let center = CGPoint(x: 512, y: 560)
            let radius: CGFloat = 270
            let start = Angle.degrees(150)
            let sweep = 240.0
            let fill = 0.68
            var track = Path()
            track.addArc(center: center, radius: radius, startAngle: start, endAngle: .degrees(150 + sweep), clockwise: false)
            ctx.stroke(track, with: .color(.white.opacity(0.32)), style: StrokeStyle(lineWidth: 64, lineCap: .round))

            var arc = Path()
            arc.addArc(center: center, radius: radius, startAngle: start, endAngle: .degrees(150 + sweep * fill), clockwise: false)
            var arcCtx = ctx
            arcCtx.addFilter(.shadow(color: Color(red: 0.55, green: 0.28, blue: 0.0).opacity(0.25), radius: 10, x: 0, y: 8))
            arcCtx.stroke(arc, with: .color(.white), style: StrokeStyle(lineWidth: 64, lineCap: .round))

            // Needle pointing at the end of the filled arc, with a hub.
            let angle = (150 + sweep * fill) * .pi / 180
            let tip = CGPoint(x: center.x + cos(angle) * (radius - 88), y: center.y + sin(angle) * (radius - 88))
            var needle = Path()
            needle.move(to: center)
            needle.addLine(to: tip)
            var needleCtx = ctx
            needleCtx.addFilter(.shadow(color: Color(red: 0.55, green: 0.28, blue: 0.0).opacity(0.3), radius: 10, x: 0, y: 8))
            needleCtx.stroke(needle, with: .color(.white), style: StrokeStyle(lineWidth: 34, lineCap: .round))
            needleCtx.fill(Path(ellipseIn: CGRect(x: center.x - 52, y: center.y - 52, width: 104, height: 104)), with: .color(.white))
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - 20, y: center.y - 20, width: 40, height: 40)),
                     with: .color(Color(red: 0.96, green: 0.62, blue: 0.14)))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
