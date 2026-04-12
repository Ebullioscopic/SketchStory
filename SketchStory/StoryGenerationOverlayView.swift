import SwiftUI
import Lottie
import UIKit
import VariableBlur
import Combine

struct StoryGenerationOverlayView: View {
    var body: some View {
        ZStack {
            BackgroundBlur(radius: 20)
                .ignoresSafeArea()

            Color.black.opacity(0.18)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                LottieAnimationPlayerView(animationName: "Open book", subdirectory: "animations")
                    .frame(width: 220, height: 220)

                Text("Generating your bedtime story")
                    .font(.headline)
                    .foregroundColor(.white)

                FadeStatusText(
                    phrases: [
                        "crafting story",
                        "choosing pen",
                        "mixing moonlight",
                        "painting pages",
                        "adding gentle magic"
                    ]
                )
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
        }
    }
}

private struct LottieAnimationPlayerView: UIViewRepresentable {
    let animationName: String
    let subdirectory: String?

    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: .zero)
        container.backgroundColor = .clear

        let animationView = LottieAnimationView()
        animationView.contentMode = .scaleAspectFit
        animationView.loopMode = .loop
        animationView.backgroundBehavior = .pauseAndRestore
        animationView.translatesAutoresizingMaskIntoConstraints = false
        animationView.animation = resolveAnimation()

        container.addSubview(animationView)
        NSLayoutConstraint.activate([
            animationView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            animationView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            animationView.topAnchor.constraint(equalTo: container.topAnchor),
            animationView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        animationView.play()
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let animationView = uiView.subviews.compactMap({ $0 as? LottieAnimationView }).first else {
            return
        }

        if animationView.animation == nil {
            animationView.animation = resolveAnimation()
        }

        if !animationView.isAnimationPlaying {
            animationView.play()
        }
    }

    private func resolveAnimation() -> LottieAnimation? {
        if let animation = LottieAnimation.named(animationName) {
            return animation
        }

        if let subdirectory,
           let path = Bundle.main.path(forResource: animationName, ofType: "json", inDirectory: subdirectory) {
            return LottieAnimation.filepath(path)
        }

        if let path = Bundle.main.path(forResource: animationName, ofType: "json") {
            return LottieAnimation.filepath(path)
        }

        if let subdirectory,
           let bundleURL = Bundle.main.resourceURL?.appendingPathComponent(subdirectory),
           let contents = try? FileManager.default.contentsOfDirectory(at: bundleURL, includingPropertiesForKeys: nil) {
            let loweredTarget = animationName.lowercased().replacingOccurrences(of: "_", with: " ")
            if let match = contents.first(where: { url in
                let fileName = url.deletingPathExtension().lastPathComponent.lowercased().replacingOccurrences(of: "_", with: " ")
                return fileName == loweredTarget || fileName.contains(loweredTarget)
            }) {
                return LottieAnimation.filepath(match.path)
            }
        }

        return nil
    }
}

private struct FadeStatusText: View {
    let phrases: [String]

    @State private var phraseIndex = 0
    @State private var textVisible = true

    private let tick = Timer.publish(every: 2.1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(currentPhrase)
            .font(.system(.footnote, design: .rounded).weight(.medium))
            .foregroundColor(.white.opacity(0.95))
            .lineLimit(1)
            .opacity(textVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.45), value: textVisible)
            .onReceive(tick) { _ in
                guard !phrases.isEmpty else { return }

                withAnimation(.easeInOut(duration: 0.45)) {
                    textVisible = false
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.47) {
                    withAnimation(.easeInOut(duration: 0.45)) {
                        phraseIndex = (phraseIndex + 1) % phrases.count
                        textVisible = true
                    }
                }
            }
    }

    private var currentPhrase: String {
        guard !phrases.isEmpty else { return "" }
        return phrases[phraseIndex]
    }
}
