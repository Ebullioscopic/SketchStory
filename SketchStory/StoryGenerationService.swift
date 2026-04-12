import Foundation
import FoundationModels
import ImagePlayground
import CoreGraphics
import UIKit
import Vision
import os
import CoreImage
#if canImport(VisualIntelligence)
import VisualIntelligence
#endif

enum ImagePlaygroundCapability {
    enum Availability: Equatable, CustomStringConvertible {
        case available
        case unavailable(reason: String)

        var description: String {
            switch self {
            case .available:
                return "available"
            case .unavailable(let reason):
                return "unavailable(\(reason))"
            }
        }
    }

    static var availability: Availability {
#if targetEnvironment(simulator)
        return .unavailable(reason: "simulatorUnsupported")
#else
        return .available
#endif
    }
}

class StoryGenerationService {
    private let logger = Logger(subsystem: "SketchStory", category: "StoryGeneration")

    func generateStory(
        profile: Profile,
        drawing: UIImage?,
        drawingReferenceDescription: String? = nil,
        visualProcessingContext: VisualProcessingContext? = nil,
        description: String,
        experience: String,
        moral: String,
        languageTags: [String]
    ) async throws -> Story {
        let session = LanguageModelSession()
        let resolvedDrawingDescription = resolveDrawingReferenceDescription(
            drawing: drawing,
            providedDescription: drawingReferenceDescription
        )

        var promptText = """
        Create a bedtime story for children and return ONLY valid JSON with this exact structure:
        {
          "title": "string",
          "masterCharacterDescription": "string",
          "scenes": [
            { "text": "string", "imagePrompt": "string" }
          ]
        }

        Requirements:
        - age: \(profile.age)
        - moralTheme: \(moral)
        - languageTags: \(languageTags.joined(separator: ", "))
        - do not use the child's name or any real person name anywhere
        - prefer an animal or fantasy protagonist instead of a human child
        - keep all image prompts identity-free (no person identity or portrait framing)
        - minimumScenes: 6
        - each scene must be warm, child-friendly, and bedtime calming
        - each scene should contain 8-10 sentences
        - aim for 120-180 words per scene
        - build gentle suspense and comforting resolution like a real bedtime story
        - include soft sensory details (moonlight, cozy sounds, warmth, calm feelings)
        - keep vocabulary appropriate for the child's age
        - keep scenes coherent for illustration generation
        - for each scene imagePrompt, provide highly specific visual direction (composition, subject pose/action, foreground, background, lighting, palette, mood)
        - each imagePrompt should be 35-70 words and avoid generic terms
        - only include rabbits if explicitly requested in the user idea or drawing description
        - no markdown, no code block, JSON only
        """

        if !description.isEmpty {
            promptText += "\nStory idea: \(description)"
        }
        if !experience.isEmpty {
            promptText += "\nDaily experience to include: \(experience)"
        }
        if drawing != nil {
            promptText += "\nA child drawing is provided by the user and should influence the visuals described in each scene."
        }
        if let resolvedDrawingDescription {
            promptText += "\nDetailed drawing visual reference for scene image prompts: \(resolvedDrawingDescription)"
        }
        if let visualProcessingContext {
            let merged = visualProcessingContext.mergedPromptContext
            if !merged.isEmpty {
                promptText += "\nVisual intelligence extraction: \(merged)"
            }
        }

        let generatedStory: GeneratedStory
        do {
            let response = try await session.respond(to: promptText)
            let decoded = try decodeGeneratedStory(from: response.content)
            generatedStory = sanitizeGeneratedStory(decoded, childName: profile.childName)
        } catch {
            generatedStory = fallbackGeneratedStory(
                description: description,
                experience: experience,
                moral: moral,
                languageTags: languageTags,
                hasDrawing: drawing != nil
            )
        }
        
        let distinctSceneSentences = await generateDistinctSceneImageSentences(
            title: generatedStory.title,
            scenes: generatedStory.scenes,
            drawingReference: resolvedDrawingDescription,
            visualContextSummary: visualProcessingContext?.mergedPromptContext,
            targetCount: generatedStory.scenes.count
        )

        var storyScenes: [StoryScene] = []
        for (index, gScene) in generatedStory.scenes.enumerated() {
            let distinctSentence = distinctSceneSentences[index]
            let enhancedPrompt = makeSpecificImagePrompt(
                scene: gScene,
                masterDescription: generatedStory.masterCharacterDescription,
                drawingReference: resolvedDrawingDescription,
                visualContextSummary: visualProcessingContext?.mergedPromptContext,
                sceneIndex: index,
                distinctSentence: distinctSentence
            )
            storyScenes.append(StoryScene(text: gScene.text, imagePrompt: enhancedPrompt, imageData: nil))
        }
        
        return Story(
            title: generatedStory.title,
            masterCharacterDescription: generatedStory.masterCharacterDescription,
            scenes: storyScenes,
            createdAt: Date()
        )
    }

    func generateDrawingReferenceDescription(from drawing: UIImage) -> String {
        guard let cgImage = drawing.cgImage else {
            let fallback = "Uploaded drawing provided as visual style reference with soft children storybook illustration characteristics."
            logger.info("Drawing reference generated (fallback, missing cgImage): \(fallback, privacy: .public)")
            return fallback
        }

        let width = cgImage.width
        let height = cgImage.height
        let aspectRatio = Double(width) / Double(max(height, 1))
        let orientation = width > height ? "landscape" : (height > width ? "portrait" : "square")

        var categoryHints: [String] = []
        let classifyRequest = VNClassifyImageRequest()

        do {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([classifyRequest])

            if let categories = classifyRequest.results {
                categoryHints = categories
                    .prefix(7)
                    .map { "\($0.identifier.lowercased()) (\(Int($0.confidence * 100))%)" }
            }
        } catch {
            logger.error("Drawing analysis Vision request failed: \(error.localizedDescription, privacy: .public)")
        }

        let colorMood = estimateColorMood(cgImage: cgImage)
        let compositionLine = estimateComposition(cgImage: cgImage)

        let categoryLine = categoryHints.isEmpty
            ? "No strong category predictions; preserve simple hand-drawn child illustration style."
            : "Likely subjects/themes: \(categoryHints.joined(separator: ", "))."

        let detailedDescription = """
        Drawing reference summary: \(orientation) canvas \(width)x\(height) (aspect \(String(format: "%.2f", aspectRatio))).
        Color and style mood: \(colorMood).
        Composition cues: \(compositionLine).
        \(categoryLine)
        Keep composition child-friendly, bedtime-calm, and consistent with this uploaded drawing.
        """
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        logger.info("Drawing reference generated: \(detailedDescription, privacy: .public)")
        return detailedDescription
    }

    func extractVisualProcessingContext(from drawing: UIImage) async -> VisualProcessingContext {
        let drawingReference = generateDrawingReferenceDescription(from: drawing)
        guard let cgImage = drawing.cgImage else {
            return VisualProcessingContext(
                drawingReferenceDescription: drawingReference,
                extractedText: "",
                semanticLabels: []
            )
        }

        let ocrText = recognizeText(from: cgImage)
        let labels = classifyLabels(from: cgImage)
        let normalizedText = await normalizeExtractedVisualText(rawText: ocrText, labels: labels)

        logger.info("Visual context extracted from uploaded drawing. labels=\(labels.joined(separator: ","), privacy: .public) text=\(normalizedText, privacy: .public)")

        return VisualProcessingContext(
            drawingReferenceDescription: drawingReference,
            extractedText: normalizedText,
            semanticLabels: labels
        )
    }

#if canImport(VisualIntelligence)
    func extractVisualProcessingContext(from descriptor: SemanticContentDescriptor) async -> VisualProcessingContext {
        let labels = descriptor.labels
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let pixelBuffer = descriptor.pixelBuffer,
              let uiImage = uiImage(from: pixelBuffer) else {
            let normalizedText = await normalizeExtractedVisualText(rawText: "", labels: labels)
            return VisualProcessingContext(
                drawingReferenceDescription: "Visual intelligence descriptor with labels only.",
                extractedText: normalizedText,
                semanticLabels: labels
            )
        }

        let base = await extractVisualProcessingContext(from: uiImage)
        let mergedLabels = Array(Set(base.semanticLabels + labels)).sorted()
        let mergedText = await normalizeExtractedVisualText(rawText: base.extractedText, labels: mergedLabels)

        return VisualProcessingContext(
            drawingReferenceDescription: base.drawingReferenceDescription,
            extractedText: mergedText,
            semanticLabels: mergedLabels
        )
    }
#endif

    private func resolveDrawingReferenceDescription(drawing: UIImage?, providedDescription: String?) -> String? {
        if let providedDescription {
            let trimmed = providedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        guard let drawing else { return nil }
        return generateDrawingReferenceDescription(from: drawing)
    }

    private func estimateComposition(cgImage: CGImage) -> String {
        let targetWidth = 64
        let targetHeight = 64
        let bytesPerPixel = 4
        let bytesPerRow = targetWidth * bytesPerPixel
        var buffer = [UInt8](repeating: 0, count: targetHeight * bytesPerRow)

        guard let context = CGContext(
            data: &buffer,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return "balanced center composition"
        }

        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

        var quadrants = [0, 0, 0, 0]
        var totalInk = 0

        for y in 0..<targetHeight {
            for x in 0..<targetWidth {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let r = Int(buffer[offset])
                let g = Int(buffer[offset + 1])
                let b = Int(buffer[offset + 2])
                let brightness = (r + g + b) / 3
                let isInk = brightness < 232

                if isInk {
                    totalInk += 1
                    let quadrantIndex: Int
                    if y < targetHeight / 2 {
                        quadrantIndex = x < targetWidth / 2 ? 0 : 1
                    } else {
                        quadrantIndex = x < targetWidth / 2 ? 2 : 3
                    }
                    quadrants[quadrantIndex] += 1
                }
            }
        }

        guard totalInk > 0 else {
            return "minimal line content with open whitespace"
        }

        let distribution = quadrants.map { Double($0) / Double(totalInk) }
        let labels = ["top-left", "top-right", "bottom-left", "bottom-right"]
        let sorted = zip(labels, distribution).sorted { $0.1 > $1.1 }
        let primary = sorted.first?.0 ?? "center"
        let secondary = sorted.dropFirst().first?.0 ?? "center"
        let density = Double(totalInk) / Double(targetWidth * targetHeight)

        let densityText: String
        if density < 0.18 {
            densityText = "sparse strokes"
        } else if density < 0.38 {
            densityText = "moderate detail"
        } else {
            densityText = "dense detail"
        }

        return "\(densityText), strongest visual weight in \(primary) then \(secondary)"
    }

    private func estimateColorMood(cgImage: CGImage) -> String {
        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent
        let context = CIContext(options: nil)
        guard
            let filter = CIFilter(name: "CIAreaAverage", parameters: [
                kCIInputImageKey: ciImage,
                kCIInputExtentKey: CIVector(cgRect: extent)
            ]),
            let outputImage = filter.outputImage
        else {
            return "balanced colors"
        }

        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let r = Double(bitmap[0]) / 255.0
        let g = Double(bitmap[1]) / 255.0
        let b = Double(bitmap[2]) / 255.0
        let brightness = (r + g + b) / 3.0

        let temperature: String
        if r > b + 0.08 {
            temperature = "warm"
        } else if b > r + 0.08 {
            temperature = "cool"
        } else {
            temperature = "neutral"
        }

        let lightness: String
        if brightness > 0.68 {
            lightness = "light"
        } else if brightness < 0.38 {
            lightness = "dark"
        } else {
            lightness = "mid-tone"
        }

        return "\(temperature), \(lightness) palette"
    }

    private func fallbackGeneratedStory(
        description: String,
        experience: String,
        moral: String,
        languageTags: [String],
        hasDrawing: Bool
    ) -> GeneratedStory {
        let languageLine = languageTags.isEmpty ? "simple and calm" : languageTags.joined(separator: ", ")
        let idea = description.isEmpty ? "a cozy bedtime adventure" : description
        let dayExperience = experience.isEmpty ? "a gentle day filled with small joys" : experience
        let visualAnchor = hasDrawing ? "inspired by the child’s drawing" : "in watercolor children’s book style"

        return GeneratedStory(
            title: "The Night of Kind Adventure",
            masterCharacterDescription: "A gentle small forest fox hero with a blue scarf, soft bedtime palette, \(visualAnchor)",
            scenes: [
                GeneratedScene(
                    text: "The evening sky turned lavender as a small fox wrapped in a blue scarf curled beneath a blanket and thought about \(idea). A night breeze hummed softly at the window, and the room smelled like warm milk and clean sheets. Far away, a wind chime rang once, like a tiny bell inviting a new adventure. The little fox whispered a promise to be gentle and brave before the night was over. A silver moonbeam stretched across the floor, touching a pair of slippers by the bed. The old clock ticked in a calm rhythm, as if counting friendly steps. One deep breath, then another, and courage settled quietly in the heart. With a tiny smile and heavy eyelids, the adventure began.",
                    imagePrompt: "small fox in a cozy bedroom, blue scarf, bedtime lamp glow, hopeful pose, \(visualAnchor)"
                ),
                GeneratedScene(
                    text: "Soon, on a moonlit dream path, silver stars painted little trails on the ground. The fox remembered \(dayExperience), and that memory made the world feel familiar and safe. A rustling sound came from behind a blackberry bush, and a worried little hedgehog stepped out. The hedgehog’s paws trembled, and the night seemed suddenly bigger and darker. Instead of running away, the fox slowed down, listened carefully, and chose \(moral.lowercased()) first. They sat together on a smooth stone and named the sounds of the forest one by one. A gentle owl call. A stream’s soft murmur. Leaves brushing like whispers. As the sounds became friendly, fear became smaller.",
                    imagePrompt: "moonlit forest path, fox helping a hedgehog friend, gentle action showing \(moral.lowercased()), soft stars, \(visualAnchor)"
                ),
                GeneratedScene(
                    text: "The two friends followed lantern bugs through a quiet forest where leaves whispered above their heads. A tiny bridge over a stream shook in the wind, and the smaller friend felt scared to cross. The fox offered a paw, counted slowly, and spoke in a calm voice until every step felt easier. One step, then another, then a brave little pause. The bridge creaked, but it held steady beneath them. Halfway across, they looked up and saw the moon shining directly above, bright and kind. By the time they reached the other side, their breaths were slow and easy again. On the riverbank, they laughed softly and listened to water sparkle over stones.",
                    imagePrompt: "forest night path, glowing lantern bugs, small bridge over stream, calm teamwork, \(visualAnchor), language style \(languageLine)"
                ),
                GeneratedScene(
                    text: "Farther ahead, they reached a hill where clouds drifted like sleepy ships. There they found a basket of storybooks scattered by the wind. Some pages fluttered through the grass like white butterflies. The fox and friends gathered every book, dusted them gently, and stacked them in neat little towers. They read a short page aloud to anyone who felt lonely. They wrapped torn covers with ribbon made from moonlight grass. They even saved the smallest book, no bigger than a mitten, and tucked it safely on top. Kindness spread from one smile to another, like warm light passing from candle to candle.",
                    imagePrompt: "moonlit hill with scattered storybooks, children helping together, soft dreamy clouds, warm gentle smiles, \(visualAnchor)"
                ),
                GeneratedScene(
                    text: "At the top of the hill, a quiet bell rang once, and the sky grew softer. Stars gathered in a long curving line, like a glowing path back home. The fox felt proud—not for being the loudest, but for being patient, caring, and steady. The little friend who had been afraid now stood tall and laughed with joy. They thanked each helper one by one, so no kindness was forgotten. A cool breeze moved around them and carried the scent of pine and rain. Together they watched the moon float above them like a silver lullaby, and the whole hill seemed to breathe peacefully.",
                    imagePrompt: "friends on hilltop under moon, peaceful triumph, calm bedtime mood, watercolor glow, \(visualAnchor)"
                ),
                GeneratedScene(
                    text: "When morning light began to peek into the dream, the fox returned to bed wrapped in warmth. The blanket felt like a soft cloud, and the pillow held the last glow of moonlight. The room was still and safe, and the lesson of \(moral.lowercased()) felt close to the heart. Outside, one early bird sang a tiny song from the garden fence. Inside, the clock slowed to the gentlest rhythm. With one long yawn and one grateful breath, the fox drifted into the deepest, sweetest sleep. The night adventure folded itself like a precious letter and tucked into tomorrow. Tomorrow would be brighter because of tonight.",
                    imagePrompt: "peaceful bedtime ending, fox resting under blanket, warm room tones, calm atmosphere, \(visualAnchor), language style \(languageLine)"
                )
            ]
        )
    }

    private func decodeGeneratedStory(from raw: String) throws -> GeneratedStory {
        let cleaned: String
        if let startFence = raw.range(of: "```") {
            let remainder = raw[startFence.upperBound...]
            if let endFence = remainder.range(of: "```") {
                cleaned = String(remainder[..<endFence.lowerBound])
            } else {
                cleaned = raw
            }
        } else {
            cleaned = raw
        }

        let jsonString = cleaned
            .replacingOccurrences(of: "json", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = jsonString.data(using: .utf8) else {
            throw NSError(domain: "StoryGenerationService", code: 1)
        }

        let decoded = try JSONDecoder().decode(GeneratedStory.self, from: data)
        guard !decoded.scenes.isEmpty else {
            throw NSError(domain: "StoryGenerationService", code: 2)
        }
        return decoded
    }
    
    func generateImage(for scene: StoryScene, masterDescription: String, referenceImage: UIImage?) async throws -> Data? {
        let fallbackData = makeDeterministicFallbackImageData(seedText: "\(masterDescription) \(scene.imagePrompt)")
        _ = referenceImage

        let availability = ImagePlaygroundCapability.availability
        if availability != .available {
            logger.info("Image Playground is currently unavailable: \(String(describing: availability), privacy: .public)")
            print("Image Playground is currently: \(availability)")
            return fallbackData
        }

        do {
            let creator = try await ImageCreator()
            var promptForAttempt = makePrimaryScenePrompt(scenePrompt: scene.imagePrompt)
            var attempt = 1

            while attempt <= 5 {
                let concepts: [ImagePlaygroundConcept] = [.text(promptForAttempt)]

                do {
                    if let data = try await runImageGeneration(creator: creator, concepts: concepts) {
                        return data
                    }
                } catch let error as ImageCreator.Error {
                    if error == .conceptsRequirePersonIdentity {
                        logger.error("Image generation failed with conceptsRequirePersonIdentity. Prompt: \(promptForAttempt, privacy: .public)")
                        print("Image generation failed with error: \(error). Prompt: \(promptForAttempt)")
                    }

                    guard attempt < 5 else { break }

                    if let reframed = await rephrasePromptForImagePlayground(
                        sceneContext: scene.imagePrompt,
                        originalPrompt: promptForAttempt,
                        errorDescription: String(describing: error),
                        attempt: attempt
                    ) {
                        promptForAttempt = reframed
                    } else {
                        promptForAttempt = makeDepersonalizedPrompt(scenePrompt: scene.imagePrompt)
                    }
                    attempt += 1
                    continue
                } catch {
                    guard attempt < 5 else { break }
                    if let reframed = await rephrasePromptForImagePlayground(
                        sceneContext: scene.imagePrompt,
                        originalPrompt: promptForAttempt,
                        errorDescription: "runtimeFailure",
                        attempt: attempt
                    ) {
                        promptForAttempt = reframed
                    } else {
                        promptForAttempt = makeDepersonalizedPrompt(scenePrompt: scene.imagePrompt)
                    }
                    attempt += 1
                    continue
                }

                guard attempt < 5 else { break }
                if let reframed = await rephrasePromptForImagePlayground(
                    sceneContext: scene.imagePrompt,
                    originalPrompt: promptForAttempt,
                    errorDescription: "noImageReturned",
                    attempt: attempt
                ) {
                    promptForAttempt = reframed
                } else {
                    promptForAttempt = makeDepersonalizedPrompt(scenePrompt: scene.imagePrompt)
                }
                attempt += 1
            }

            return fallbackData
        } catch {
            return fallbackData
        }
    }

    func fallbackImageData(for scene: StoryScene, masterDescription: String) -> Data? {
        makeDeterministicFallbackImageData(seedText: "\(masterDescription) \(scene.imagePrompt)")
    }

    private func runImageGeneration(
        creator: ImageCreator,
        concepts: [ImagePlaygroundConcept]
    ) async throws -> Data? {
        let results = creator.images(for: concepts, style: .illustration, limit: 1)
        for try await result in results {
            let uiImage = UIImage(cgImage: result.cgImage)
            return uiImage.jpegData(compressionQuality: 0.8)
        }
        return nil
    }

    private func rephrasePromptForImagePlayground(
        sceneContext: String,
        originalPrompt: String,
        errorDescription: String,
        attempt: Int
    ) async -> String? {
        let session = LanguageModelSession()
        let request = """
        Rewrite this image prompt for Apple Image Playground.
        Make it compact, scene-specific, and safer to generate.
        Constraints:
        - English only
        - 12 to 22 words
        - include one clear subject, one action, and one environment cue
        - no names, no dialogue, no quotes
        - no people identity, no person references
        - no copyrighted characters, no logos, no text in image
        - keep child-friendly tone
        - return plain text only

        Attempt: \(attempt)
        PreviousError: \(errorDescription)
        SceneContext: \(sceneContext)
        PreviousPrompt: \(originalPrompt)
        """

        do {
            let response = try await session.respond(to: request)
            let normalized = normalizePromptText(response.content)
            let safe = removePersonIdentityTerms(normalized)
            let limited = limitWords(safe, maxWords: 22)
            if limited.count > 14 {
                return "storybook watercolor, \(limited), no text"
            }
        } catch {
            logger.error("Prompt rephrase failed: \(error.localizedDescription, privacy: .public)")
        }

        return nil
    }

    private func makeSpecificImagePrompt(
        scene: GeneratedScene,
        masterDescription: String,
        drawingReference: String?,
        visualContextSummary: String?,
        sceneIndex: Int,
        distinctSentence: String?
    ) -> String {
        _ = masterDescription
        let sceneSummary = summarizeSceneText(scene.text)
        let distinctLine = (distinctSentence?.isEmpty == false) ? distinctSentence! : scene.imagePrompt
        let sceneAnchor = distinctVisualAnchor(for: sceneIndex)
        let drawingLine = (drawingReference?.isEmpty == false) ? "drawing reference: \(drawingReference!)" : ""
        let contextLine = (visualContextSummary?.isEmpty == false) ? "visual context: \(visualContextSummary!)" : ""

        let base = """
        scene \(sceneIndex + 1) children storybook watercolor illustration, \(distinctLine), action: \(sceneSummary), visual anchor: \(sceneAnchor), composition: clear foreground subject and readable background depth, camera: medium shot with gentle perspective, lighting: warm moonlight and soft lamp glow, palette: pastel blues and violets, mood: calm bedtime comfort, no logos or text overlays, \(drawingLine), \(contextLine)
        """

        let normalized = normalizePromptText(base)
        let depersonalized = removePersonIdentityTerms(normalized)
        let limited = limitWords(depersonalized, maxWords: 56)
        return "children storybook watercolor illustration, \(limited)"
    }

    private func distinctVisualAnchor(for sceneIndex: Int) -> String {
        let anchors = [
            "indoor bedroom scene, window and blanket foreground, deep navy and amber palette, side view",
            "forest trail scene, lantern bugs and tall trees, cool teal and moss palette, wide angle",
            "wooden bridge over stream, rippling water highlights, silver-blue palette, low camera angle",
            "moonlit hill with scattered books, cloud layers and grass movement, lavender palette, high angle",
            "hilltop sky panorama with curved star trail, mist depth layers, indigo palette, long shot",
            "quiet room dawn transition, soft curtain light and pillow textures, peach-blue palette, close-medium"
        ]
        return anchors[sceneIndex % anchors.count]
    }

    private func makePrimaryScenePrompt(scenePrompt: String) -> String {
        let normalizedScene = normalizePromptText(scenePrompt)

        let scenePart = limitWords(removePersonIdentityTerms(normalizedScene), maxWords: 26)

        if !scenePart.isEmpty {
            return "storybook watercolor, \(scenePart), one clear subject, one clear action, no text"
        }

        return makeDepersonalizedPrompt(scenePrompt: scenePrompt)
    }

    private func summarizeSceneText(_ text: String) -> String {
        let sentenceSplit = text.split(separator: ".")
        if let first = sentenceSplit.first {
            return String(first).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    private func makeConciseSafePrompt(masterDescription: String, scenePrompt: String) -> String {
        let base = normalizePromptText("\(masterDescription) \(scenePrompt)")
        let peopleSafe = removePersonIdentityTerms(base)
        let limited = limitWords(peopleSafe, maxWords: 44)

        if limited.count >= 20 {
            return "children storybook watercolor illustration, single consistent character design, clear foreground and background, medium shot, warm soft night lighting, no text overlay, \(limited)"
        }

        return "children storybook watercolor illustration, cozy bedtime room with moonlight, small table lamp glow, plush toys in background, gentle color palette, calm mood"
    }

    private func makeEnglishSafePrompt(masterDescription: String, scenePrompt: String) -> String {
        let normalized = normalizePromptText("\(masterDescription). \(scenePrompt)")
        let peopleSafe = removePersonIdentityTerms(normalized)
        let limited = limitWords(peopleSafe, maxWords: 52)

        if limited.count >= 20 {
            return "children storybook watercolor illustration, specific scene composition, visible foreground action, soft depth in background, moonlit warm ambiance, no logos no text, \(limited)"
        }

        return "children storybook watercolor illustration of a moonlit cozy bedroom and quiet window scene, warm gentle lighting, pastel colors, calm bedtime atmosphere"
    }

    private func makeDepersonalizedPrompt(scenePrompt: String) -> String {
        let normalized = normalizePromptText(scenePrompt)
        let noPeople = removePersonIdentityTerms(normalized)
        let limited = limitWords(noPeople, maxWords: 34)
        return "children storybook watercolor landscape, moonlit room and garden, lantern glow, cozy bedtime objects, soft textures, calm atmosphere, \(limited)"
    }

    private func normalizePromptText(_ input: String) -> String {
        let transliterated = input.applyingTransform(.toLatin, reverse: false) ?? input
        let folded = transliterated.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let allowed = folded.unicodeScalars.map { scalar -> Character in
            let isLetter = CharacterSet.letters.contains(scalar)
            let isDigit = CharacterSet.decimalDigits.contains(scalar)
            let isSpaceOrPunctuation = " ,.-".unicodeScalars.contains(scalar)
            return (isLetter || isDigit || isSpaceOrPunctuation) ? Character(scalar) : " "
        }

        return String(allowed)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func removePersonIdentityTerms(_ input: String) -> String {
        let banned: Set<String> = [
            "child", "children", "kid", "boy", "girl", "man", "woman", "person", "people", "human",
            "portrait", "face", "selfie", "named", "name", "mother", "father", "mom", "dad", "identity",
            "he", "she", "his", "her", "hers", "him", "humanlike", "realistic"
        ]

        let filteredWords = input
            .split(separator: " ")
            .map(String.init)
            .filter { !banned.contains($0) }

        return filteredWords.joined(separator: " ")
    }

    private func limitWords(_ input: String, maxWords: Int) -> String {
        let words = input.split(separator: " ").prefix(maxWords)
        return words.joined(separator: " ")
    }

    private func sanitizeGeneratedStory(_ story: GeneratedStory, childName: String) -> GeneratedStory {
        let sanitizedTitle = removeChildName(from: story.title, childName: childName)
        let sanitizedMaster = removeChildName(from: story.masterCharacterDescription, childName: childName)
        let sanitizedScenes = story.scenes.map { scene in
            GeneratedScene(
                text: removeChildName(from: scene.text, childName: childName),
                imagePrompt: removeChildName(from: scene.imagePrompt, childName: childName)
            )
        }

        return GeneratedStory(
            title: sanitizedTitle,
            masterCharacterDescription: sanitizedMaster,
            scenes: sanitizedScenes
        )
    }

    private func removeChildName(from input: String, childName: String) -> String {
        let trimmedName = childName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return input }

        let escaped = NSRegularExpression.escapedPattern(for: trimmedName)
        guard let regex = try? NSRegularExpression(pattern: "\\b\(escaped)\\b", options: [.caseInsensitive]) else {
            return input
        }

        let range = NSRange(input.startIndex..., in: input)
        let replaced = regex.stringByReplacingMatches(in: input, options: [], range: range, withTemplate: "the little hero")
        return replaced.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct DistinctSceneLine: Codable {
        let sceneNumber: Int
        let sentence: String
    }

    private func generateDistinctSceneImageSentences(
        title: String,
        scenes: [GeneratedScene],
        drawingReference: String?,
        visualContextSummary: String?,
        targetCount: Int
    ) async -> [Int: String] {
        let count = min(max(targetCount, 0), scenes.count)
        guard count > 0 else { return [:] }

        let sceneBlock = scenes
            .enumerated()
            .prefix(count)
            .map { index, scene in
                let summary = summarizeSceneText(scene.text)
                return "Scene \(index + 1): \(summary)"
            }
            .joined(separator: "\n")

        let drawingLine = drawingReference ?? "none"
        let contextLine = (visualContextSummary?.isEmpty == false) ? visualContextSummary! : "none"
        let request = """
        You are preparing Image Playground prompts for a children's bedtime story.
        Generate exactly \(count) DISTINCT single-sentence lines, one per scene.

        Output must be strict JSON array with this shape:
        [
          {"sceneNumber": 1, "sentence": "..."}
        ]

        Constraints for each sentence:
        - 18 to 30 words
        - must be visually specific and include scene-unique keywords
        - include foreground subject, background setting, and one concrete action
        - include a lighting cue and color cue
        - no person identity, no names, no portrait terms, no logos, no text overlay
        - child-friendly, calm bedtime tone

        Story title: \(title)
        Drawing reference: \(drawingLine)
        Visual extraction context: \(contextLine)
        Scenes:
        \(sceneBlock)
        """

        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: request)
            let parsed = try decodeDistinctSceneLines(from: response.content)
            var byIndex: [Int: String] = [:]

            for line in parsed {
                let zeroBased = line.sceneNumber - 1
                guard zeroBased >= 0, zeroBased < count else { continue }
                let normalized = normalizePromptText(line.sentence)
                let safe = removePersonIdentityTerms(normalized)
                let limited = limitWords(safe, maxWords: 30)
                if !limited.isEmpty {
                    byIndex[zeroBased] = limited
                }
            }

            return byIndex
        } catch {
            logger.error("Distinct scene sentence generation failed: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }

    private func decodeDistinctSceneLines(from raw: String) throws -> [DistinctSceneLine] {
        let cleaned: String
        if let startFence = raw.range(of: "```") {
            let remainder = raw[startFence.upperBound...]
            if let endFence = remainder.range(of: "```") {
                cleaned = String(remainder[..<endFence.lowerBound])
            } else {
                cleaned = raw
            }
        } else {
            cleaned = raw
        }

        let jsonString = cleaned
            .replacingOccurrences(of: "json", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = jsonString.data(using: .utf8) else {
            throw NSError(domain: "StoryGenerationService", code: 301)
        }

        return try JSONDecoder().decode([DistinctSceneLine].self, from: data)
    }

    private func makeDeterministicFallbackImageData(seedText: String) -> Data? {
        let size = CGSize(width: 768, height: 1024)
        let renderer = UIGraphicsImageRenderer(size: size)
        let hashValue = abs(seedText.hashValue)

        let image = renderer.image { context in
            let cgContext = context.cgContext

            let hue = CGFloat((hashValue % 360)) / 360.0
            let topColor = UIColor(hue: hue, saturation: 0.35, brightness: 0.85, alpha: 1.0)
            let bottomColor = UIColor(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1.0), saturation: 0.30, brightness: 0.55, alpha: 1.0)

            let colors = [topColor.cgColor, bottomColor.cgColor] as CFArray
            let space = CGColorSpaceCreateDeviceRGB()
            let locations: [CGFloat] = [0.0, 1.0]
            if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: locations) {
                cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: 0, y: size.height),
                    options: []
                )
            }

            let moonRect = CGRect(x: size.width * 0.68, y: size.height * 0.08, width: 130, height: 130)
            cgContext.setFillColor(UIColor.white.withAlphaComponent(0.85).cgColor)
            cgContext.fillEllipse(in: moonRect)

            cgContext.setFillColor(UIColor.white.withAlphaComponent(0.8).cgColor)
            for index in 0..<24 {
                let xSeed = CGFloat((hashValue + index * 97) % 700)
                let ySeed = CGFloat((hashValue + index * 149) % 560)
                let starRect = CGRect(x: 24 + xSeed, y: 30 + ySeed, width: 3.5, height: 3.5)
                cgContext.fillEllipse(in: starRect)
            }

            let hillPath = UIBezierPath()
            hillPath.move(to: CGPoint(x: 0, y: size.height * 0.72))
            hillPath.addCurve(
                to: CGPoint(x: size.width, y: size.height * 0.76),
                controlPoint1: CGPoint(x: size.width * 0.25, y: size.height * 0.63),
                controlPoint2: CGPoint(x: size.width * 0.75, y: size.height * 0.82)
            )
            hillPath.addLine(to: CGPoint(x: size.width, y: size.height))
            hillPath.addLine(to: CGPoint(x: 0, y: size.height))
            hillPath.close()
            UIColor(red: 0.12, green: 0.22, blue: 0.22, alpha: 0.9).setFill()
            hillPath.fill()
        }

        return image.jpegData(compressionQuality: 0.82)
    }

    private func recognizeText(from cgImage: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        do {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])
            let lines = (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return lines.joined(separator: " ")
        } catch {
            logger.error("OCR extraction failed: \(error.localizedDescription, privacy: .public)")
            return ""
        }
    }

    private func classifyLabels(from cgImage: CGImage) -> [String] {
        let request = VNClassifyImageRequest()

        do {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])
            return (request.results ?? [])
                .prefix(8)
                .map { $0.identifier.lowercased() }
                .map { $0.replacingOccurrences(of: "_", with: " ") }
        } catch {
            logger.error("Label classification failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func normalizeExtractedVisualText(rawText: String, labels: [String]) async -> String {
        let compactRaw = rawText
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !compactRaw.isEmpty || !labels.isEmpty else {
            return ""
        }

        let labelLine = labels.joined(separator: ", ")
        let request = """
        Summarize extracted visual input for story and image prompt conditioning.
        Return one concise plain-English sentence, max 24 words.
        Keep concrete nouns, actions, mood cues.
        No names, no identity assumptions.

        OCR text: \(compactRaw)
        Visual labels: \(labelLine)
        """

        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: request)
            let normalized = normalizePromptText(response.content)
            return limitWords(normalized, maxWords: 24)
        } catch {
            let fallback = [compactRaw, labelLine]
                .filter { !$0.isEmpty }
                .joined(separator: "; ")
            return limitWords(normalizePromptText(fallback), maxWords: 24)
        }
    }

#if canImport(VisualIntelligence)
    private func uiImage(from pixelBuffer: CVReadOnlyPixelBuffer) -> UIImage? {
        let mutablePixelBuffer = pixelBuffer as! CVPixelBuffer
        let ciImage = CIImage(cvPixelBuffer: mutablePixelBuffer)
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
#endif
}
