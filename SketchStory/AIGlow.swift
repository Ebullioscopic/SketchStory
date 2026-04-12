import SwiftUI

private struct AIIsGeneratingKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    var aiIsGenerating: Bool {
        get { self[AIIsGeneratingKey.self] }
        set { self[AIIsGeneratingKey.self] = newValue }
    }
}

extension View {
    func showGenerationGlow(_ value: Bool) -> some View {
        environment(\.aiIsGenerating, value)
    }
}

enum Vibrancy: CaseIterable, Sendable {
    case subtle
    case muted
    case normal
    case vivid

    var opacityFactor: Double {
        switch self {
        case .subtle: return 0.25
        case .muted: return 0.5
        case .normal: return 0.75
        case .vivid: return 1
        }
    }
}

struct AIIntelligenceGlowModifier: ViewModifier {
    @Environment(\.aiIsGenerating) private var isGenerating

    @State private var gradientStops: [Gradient.Stop] = []
    @State private var timer: Timer?

    var innerPadding: Double = 8
    var cornerRadius: CGFloat
    var useBackground: Bool
    var backgroundColor: Color
    var vibrancy: Vibrancy

    func body(content: Content) -> some View {
        content
            .padding(innerPadding)
            .background(glowBackground)
            .animation(.easeInOut(duration: 0.35), value: isGenerating)
            .onChange(of: isGenerating) { _, newValue in
                if newValue {
                    gradientStops = GlowEffect.generateGradientStops(vibrancy: vibrancy)
                    startTimer()
                } else {
                    timer?.invalidate()
                    timer = nil
                }
            }
            .onAppear {
                if isGenerating {
                    gradientStops = GlowEffect.generateGradientStops(vibrancy: vibrancy)
                    startTimer()
                }
            }
            .onDisappear {
                timer?.invalidate()
                timer = nil
            }
    }

    private var glowBackground: some View {
        GeometryReader { geometry in
            ZStack {
                GlowLayer(gradientStops: gradientStops, lineWidth: 10, blurRadius: 18, size: geometry.size, cornerRadius: cornerRadius)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                GlowLayer(gradientStops: gradientStops, lineWidth: 2, blurRadius: 0, size: geometry.size, cornerRadius: cornerRadius)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                GlowLayer(gradientStops: gradientStops, lineWidth: 5, blurRadius: 7, size: geometry.size, cornerRadius: cornerRadius)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                if useBackground {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(backgroundColor)
                }
            }
            .opacity(isGenerating ? 1 : 0)
        }
    }

    @MainActor
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.5)) {
                    gradientStops = GlowEffect.generateGradientStops(vibrancy: vibrancy)
                }
            }
        }
    }
}

extension View {
    func aiGlow(
        innerPadding: Double = 8,
        cornerRadius: CGFloat = 22,
        useBackground: Bool = true,
        backgroundColor: Color = Color(UIColor.systemBackground).opacity(0.3),
        vibrancy: Vibrancy = .normal
    ) -> some View {
        modifier(
            AIIntelligenceGlowModifier(
                innerPadding: innerPadding,
                cornerRadius: cornerRadius,
                useBackground: useBackground,
                backgroundColor: backgroundColor,
                vibrancy: vibrancy
            )
        )
    }
}

struct GlowLayer: View {
    var gradientStops: [Gradient.Stop]
    var lineWidth: CGFloat
    var blurRadius: CGFloat
    var size: CGSize
    var cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(
                LinearGradient(stops: gradientStops, startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: lineWidth
            )
            .frame(width: size.width, height: size.height)
            .blur(radius: blurRadius)
    }
}

enum GlowEffect {
    static func generateGradientStops(vibrancy: Vibrancy) -> [Gradient.Stop] {
        let base: [Color] = [
            Color.teal,
            Color.blue,
            Color.purple,
            Color.indigo,
            Color.cyan,
        ]

        let op = vibrancy.opacityFactor
        let selected: [Color] = [
            base[0].opacity(op),
            base[2].opacity(op),
            base[1].opacity(op),
            base[3].opacity(min(op * 1.05, 1.0)),
            base[2].opacity(min(op * 1.0, 1.0)),
            base[4].opacity(min(op * 1.05, 1.0)),
        ]

        let stops = selected.map { color in
            Gradient.Stop(color: color, location: Double.random(in: 0 ... 1))
        }

        return stops.sorted { $0.location < $1.location }
    }
}
