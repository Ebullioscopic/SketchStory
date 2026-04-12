import SwiftUI
import AVFoundation
import TipKit
import Combine

struct StoryReaderView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var storage: StorageService
    var story: Story

    @State private var selectedPage = 0
    @State private var previousPageForFlip: Int?
    @State private var flipProgress: CGFloat = 0
    @State private var flipDirection: CGFloat = 1
    @StateObject private var narration = StoryNarrationController()
    @State private var presentedImage: PresentedImage?

    private let storyReaderAudioTip = StoryReaderAudioTip()
    private let storyReaderScrollTip = StoryReaderScrollTip()

    private var readerDynamicTypeSize: DynamicTypeSize {
        guard storage.settings.enhancedTextSize else { return .xxLarge }

        let scale = max(0, min(1, storage.settings.textSizeScale))
        let sizes: [DynamicTypeSize] = [.small, .medium, .large, .xLarge, .xxLarge, .xxxLarge, .accessibility1, .accessibility2]
        let index = Int((Double(sizes.count - 1) * scale).rounded())
        return sizes[index]
    }
    
    var body: some View {
        Group {
            if storage.settings.readingMode == .scroll {
                scrollReader
            } else {
                pageFlipReader
            }
        }
        .background(AppPalette.background(for: colorScheme).ignoresSafeArea())
        .overlay {
            if storage.settings.readingMode == .pageFlip,
               let previousPageForFlip,
               previousPageForFlip >= 0,
               previousPageForFlip < story.scenes.count,
               flipProgress > 0 {
                BookPageView(
                    pageIndex: previousPageForFlip,
                    title: story.title,
                    scene: story.scenes[previousPageForFlip],
                    totalPages: story.scenes.count,
                    highlightRange: nil,
                    colorScheme: colorScheme,
                    canExpandImage: false,
                    onImageTap: { _ in }
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
                .rotation3DEffect(
                    .degrees(Double(flipProgress) * (flipDirection > 0 ? -170 : 170)),
                    axis: (x: 0, y: 1, z: 0),
                    anchor: flipDirection > 0 ? .leading : .trailing,
                    perspective: 0.7
                )
                .opacity(1 - Double(flipProgress * 0.92))
                .shadow(color: .black.opacity(0.2), radius: 8, x: flipDirection > 0 ? -4 : 4, y: 3)
                .allowsHitTesting(false)
            }
        }
        .navigationTitle(story.title)
        .navigationBarTitleDisplayMode(.inline)
        .dynamicTypeSize(readerDynamicTypeSize...readerDynamicTypeSize)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: toggleNarration) {
                    Image(systemName: narration.playbackState == .playing ? "pause.fill" : "play.fill")
                }
                .accessibilityLabel(narration.playbackState == .playing ? "Pause narration" : "Play narration")
                .popoverTip(storyReaderAudioTip, arrowEdge: .top)
            }
        }
        .onAppear {
            narration.configure(
                sceneTexts: story.scenes.map { $0.text },
                onSceneChanged: { index in
                    withAnimation(.easeInOut(duration: 0.42)) {
                        selectedPage = index
                    }
                },
                onFinishedAllScenes: {
                    selectedPage = 0
                }
            )
        }
        .onDisappear {
            narration.stop()
        }
        .onChange(of: selectedPage) { oldValue, newValue in
            if storage.settings.readingMode == .pageFlip {
                runFlipAnimation(from: oldValue, to: newValue)
            }
            if narration.playbackState == .playing {
                narration.jumpToScene(newValue)
            }
        }
        .sheet(item: $presentedImage) { item in
            ZoomedImageView(image: item.image)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var scrollReader: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(Array(story.scenes.enumerated()), id: \.element.id) { index, scene in
                        BookPageView(
                            pageIndex: index,
                            title: story.title,
                            scene: scene,
                            totalPages: story.scenes.count,
                            highlightRange: narration.currentSceneIndex == index ? narration.spokenRange : nil,
                            colorScheme: colorScheme,
                            canExpandImage: storage.settings.tapImageToExpand,
                            onImageTap: openImage
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(AppPalette.background(for: colorScheme))
                        .id(index)
                    }
                }
            }
            .popoverTip(storyReaderScrollTip, arrowEdge: .top)
            .onChange(of: narration.currentSceneIndex) { _, newValue in
                withAnimation(.easeInOut(duration: 0.4)) {
                    proxy.scrollTo(newValue, anchor: .top)
                }
            }
        }
    }

    private var pageFlipReader: some View {
        TabView(selection: $selectedPage) {
            ForEach(Array(story.scenes.enumerated()), id: \.element.id) { index, scene in
                BookPageView(
                    pageIndex: index,
                    title: story.title,
                    scene: scene,
                    totalPages: story.scenes.count,
                    highlightRange: narration.currentSceneIndex == index ? narration.spokenRange : nil,
                    colorScheme: colorScheme,
                    canExpandImage: storage.settings.tapImageToExpand,
                    onImageTap: openImage
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
                .background(AppPalette.background(for: colorScheme))
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
    }

    private func openImage(_ image: UIImage) {
        presentedImage = PresentedImage(image: image)
    }

    private func toggleNarration() {
        Task {
            await StoryReaderAudioTip.audioTapped.donate()
        }

        switch narration.playbackState {
        case .playing:
            narration.pause()
        case .paused:
            narration.resume()
        case .stopped:
            narration.start(from: selectedPage)
        }
    }

    private func runFlipAnimation(from oldValue: Int, to newValue: Int) {
        guard oldValue != newValue else { return }
        flipDirection = newValue > oldValue ? 1 : -1
        previousPageForFlip = oldValue
        flipProgress = 0

        withAnimation(.easeInOut(duration: 0.46)) {
            flipProgress = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
            previousPageForFlip = nil
            flipProgress = 0
        }
    }
}

private struct BookPageView: View {
    let pageIndex: Int
    let title: String
    let scene: StoryScene
    let totalPages: Int
    let highlightRange: NSRange?
    let colorScheme: ColorScheme
    let canExpandImage: Bool
    let onImageTap: (UIImage) -> Void

    private var layoutType: Int { pageIndex % 3 }
    private var wrappedChunks: (top: NSRange, side: NSRange, bottom: NSRange) {
        chunkedRanges(scene.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if pageIndex == 0 {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
            }

            if layoutType == 0 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(styledSegmentText(fullText: scene.text, segment: wrappedChunks.top))
                            .font(.body)
                            .multilineTextAlignment(.leading)

                        HStack(alignment: .top, spacing: 12) {
                            pageImage
                            Text(styledSegmentText(fullText: scene.text, segment: wrappedChunks.side))
                                .font(.body)
                                .multilineTextAlignment(.leading)
                        }

                        Text(styledSegmentText(fullText: scene.text, segment: wrappedChunks.bottom))
                            .font(.body)
                            .multilineTextAlignment(.leading)
                    }
                }
            } else if layoutType == 1 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(styledSegmentText(fullText: scene.text, segment: wrappedChunks.top))
                            .font(.body)
                            .multilineTextAlignment(.leading)

                        HStack(alignment: .top, spacing: 12) {
                            Text(styledSegmentText(fullText: scene.text, segment: wrappedChunks.side))
                                .font(.body)
                                .multilineTextAlignment(.leading)
                            pageImage
                        }

                        Text(styledSegmentText(fullText: scene.text, segment: wrappedChunks.bottom))
                            .font(.body)
                            .multilineTextAlignment(.leading)
                    }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Spacer(minLength: 0)
                            pageImage
                        }

                        Text(styledSegmentText(fullText: scene.text, segment: NSRange(location: 0, length: (scene.text as NSString).length)))
                            .font(.body)
                            .multilineTextAlignment(.leading)
                    }
                }
            }

            Text("Page \(pageIndex + 1) of \(totalPages)")
                .font(.footnote)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(AppPalette.card(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color(.separator), lineWidth: 0.6)
        )
    }

    @ViewBuilder
    private var pageImage: some View {
        if let data = scene.imageData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 140, height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onTapGesture {
                    if canExpandImage {
                        onImageTap(uiImage)
                    }
                }
                .accessibilityAddTraits(canExpandImage ? .isButton : [])
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 140, height: 190)
                .overlay(
                    Image(systemName: "photo")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                )
        }
    }

    private func styledSegmentText(fullText: String, segment: NSRange) -> AttributedString {
        let nsText = fullText as NSString
        guard segment.location != NSNotFound,
              segment.location >= 0,
              segment.upperBound <= nsText.length
        else {
            return AttributedString("")
        }

        let segmentString = nsText.substring(with: segment)
        var attributed = AttributedString(segmentString)

        guard let highlightRange,
              let intersection = intersectionRange(segment, highlightRange),
              intersection.length > 0
        else {
            return attributed
        }

        let localRange = NSRange(location: intersection.location - segment.location, length: intersection.length)
        if let swiftRange = Range(localRange, in: segmentString),
           let lower = AttributedString.Index(swiftRange.lowerBound, within: attributed),
           let upper = AttributedString.Index(swiftRange.upperBound, within: attributed) {
            attributed[lower..<upper].backgroundColor = .yellow.opacity(0.42)
            attributed[lower..<upper].foregroundColor = .primary
        }

        return attributed
    }

    private func chunkedRanges(_ text: String) -> (top: NSRange, side: NSRange, bottom: NSRange) {
        let nsText = text as NSString
        let wordRanges = enumerateWordRanges(text)

        guard !wordRanges.isEmpty else {
            let empty = NSRange(location: 0, length: min(1, nsText.length))
            return (empty, empty, empty)
        }

        let total = wordRanges.count
        let topCount = max(18, Int(Double(total) * 0.22))
        let sideCount = max(30, Int(Double(total) * 0.36))

        let topEnd = min(topCount - 1, total - 1)
        let sideStart = min(topEnd + 1, total - 1)
        let sideEnd = min(sideStart + sideCount - 1, total - 1)
        let bottomStart = min(sideEnd + 1, total - 1)

        let topRange = combinedRange(from: wordRanges, startIndex: 0, endIndex: topEnd)
        let sideRange = combinedRange(from: wordRanges, startIndex: sideStart, endIndex: sideEnd)
        let bottomRange = combinedRange(from: wordRanges, startIndex: bottomStart, endIndex: total - 1)

        return (topRange, sideRange, bottomRange)
    }

    private func enumerateWordRanges(_ text: String) -> [NSRange] {
        let nsText = text as NSString
        var ranges: [NSRange] = []
        nsText.enumerateSubstrings(in: NSRange(location: 0, length: nsText.length), options: [.byWords, .localized]) { _, range, _, _ in
            ranges.append(range)
        }
        return ranges
    }

    private func combinedRange(from ranges: [NSRange], startIndex: Int, endIndex: Int) -> NSRange {
        guard !ranges.isEmpty else { return NSRange(location: 0, length: 0) }
        let safeStart = max(0, min(startIndex, ranges.count - 1))
        let safeEnd = max(safeStart, min(endIndex, ranges.count - 1))
        let start = ranges[safeStart].location
        let end = ranges[safeEnd].location + ranges[safeEnd].length
        return NSRange(location: start, length: max(0, end - start))
    }

    private func intersectionRange(_ lhs: NSRange, _ rhs: NSRange) -> NSRange? {
        let start = max(lhs.location, rhs.location)
        let end = min(lhs.location + lhs.length, rhs.location + rhs.length)
        guard end > start else { return nil }
        return NSRange(location: start, length: end - start)
    }
}

private struct PresentedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct ZoomedImageView: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(16)
            .navigationTitle("Image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private final class StoryNarrationController: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    enum PlaybackState {
        case stopped
        case playing
        case paused
    }

    @Published var playbackState: PlaybackState = .stopped
    @Published var currentSceneIndex: Int = 0
    @Published var spokenRange: NSRange? = nil

    private let synthesizer = AVSpeechSynthesizer()
    private var sceneTexts: [String] = []
    private var onSceneChanged: ((Int) -> Void)?
    private var onFinishedAllScenes: (() -> Void)?
    private var localeIdentifier = "en-US"

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func configure(sceneTexts: [String], onSceneChanged: @escaping (Int) -> Void, onFinishedAllScenes: @escaping () -> Void) {
        self.sceneTexts = sceneTexts
        self.onSceneChanged = onSceneChanged
        self.onFinishedAllScenes = onFinishedAllScenes
        if let preferredLanguage = Locale.current.language.languageCode?.identifier {
            localeIdentifier = preferredLanguage == "en" ? "en-US" : Locale.current.identifier
        }
    }

    func start(from page: Int) {
        guard !sceneTexts.isEmpty else { return }
        currentSceneIndex = max(0, min(page, sceneTexts.count - 1))
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        speakCurrentScene()
    }

    func pause() {
        guard synthesizer.isSpeaking else { return }
        if synthesizer.pauseSpeaking(at: .word) {
            playbackState = .paused
        }
    }

    func resume() {
        guard playbackState == .paused else { return }
        if synthesizer.continueSpeaking() {
            playbackState = .playing
        }
    }

    func stop() {
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        playbackState = .stopped
        spokenRange = nil
    }

    func jumpToScene(_ index: Int) {
        guard playbackState == .playing else { return }
        let bounded = max(0, min(index, sceneTexts.count - 1))
        guard bounded != currentSceneIndex else { return }
        currentSceneIndex = bounded
        synthesizer.stopSpeaking(at: .immediate)
        DispatchQueue.main.async { [weak self] in
            self?.speakCurrentScene()
        }
    }

    private func speakCurrentScene() {
        guard currentSceneIndex >= 0, currentSceneIndex < sceneTexts.count else {
            playbackState = .stopped
            spokenRange = nil
            onFinishedAllScenes?()
            return
        }

        let text = sceneTexts[currentSceneIndex]
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: localeIdentifier) ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.41
        utterance.pitchMultiplier = 0.92
        utterance.volume = 0.9
        utterance.preUtteranceDelay = 0.12
        utterance.postUtteranceDelay = 0.3

        spokenRange = nil
        playbackState = .playing
        onSceneChanged?(currentSceneIndex)
        synthesizer.speak(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.spokenRange = characterRange
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.spokenRange = nil
            if self.playbackState == .stopped {
                return
            }

            let next = self.currentSceneIndex + 1
            if next < self.sceneTexts.count {
                self.currentSceneIndex = next
                self.speakCurrentScene()
            } else {
                self.playbackState = .stopped
                self.currentSceneIndex = 0
                self.onFinishedAllScenes?()
            }
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            if self.playbackState != .paused {
                self.playbackState = .stopped
                self.spokenRange = nil
            }
        }
    }
}
