import Foundation

enum ReadingMode: String, Codable, CaseIterable {
    case scroll
    case pageFlip
}

struct AppSettings: Codable {
    var readingMode: ReadingMode = .scroll
    var enhancedTextSize: Bool = false
    var tapImageToExpand: Bool = true
    var textSizeScale: Double = 0.5

    private enum CodingKeys: String, CodingKey {
        case readingMode
        case enhancedTextSize
        case tapImageToExpand
        case textSizeScale
    }

    init() {}

    init(readingMode: ReadingMode = .scroll, enhancedTextSize: Bool = false, tapImageToExpand: Bool = true, textSizeScale: Double = 0.5) {
        self.readingMode = readingMode
        self.enhancedTextSize = enhancedTextSize
        self.tapImageToExpand = tapImageToExpand
        self.textSizeScale = textSizeScale
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        readingMode = try container.decodeIfPresent(ReadingMode.self, forKey: .readingMode) ?? .scroll
        enhancedTextSize = try container.decodeIfPresent(Bool.self, forKey: .enhancedTextSize) ?? false
        tapImageToExpand = try container.decodeIfPresent(Bool.self, forKey: .tapImageToExpand) ?? true
        textSizeScale = try container.decodeIfPresent(Double.self, forKey: .textSizeScale) ?? 0.5
    }
}

struct VisualProcessingContext {
    var drawingReferenceDescription: String
    var extractedText: String
    var semanticLabels: [String]

    var mergedPromptContext: String {
        let labels = semanticLabels.joined(separator: ", ")

        if !extractedText.isEmpty, !labels.isEmpty {
            return "Extracted text: \(extractedText). Visual labels: \(labels)."
        }
        if !extractedText.isEmpty {
            return "Extracted text: \(extractedText)."
        }
        if !labels.isEmpty {
            return "Visual labels: \(labels)."
        }
        return ""
    }
}

struct Profile: Codable {
    var childName: String
    var age: Int
    var gender: String
    var location: String
}

struct StoryScene: Identifiable, Codable {
    var id = UUID()
    var text: String
    var imagePrompt: String
    var imageData: Data?
}

struct Story: Identifiable, Codable {
    var id = UUID()
    var title: String
    var masterCharacterDescription: String
    var scenes: [StoryScene]
    var createdAt: Date
    var parentStoryID: UUID?
    var chapters: [Story]

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case masterCharacterDescription
        case scenes
        case createdAt
        case parentStoryID
        case chapters
    }

    init(
        id: UUID = UUID(),
        title: String,
        masterCharacterDescription: String,
        scenes: [StoryScene],
        createdAt: Date,
        parentStoryID: UUID? = nil,
        chapters: [Story] = []
    ) {
        self.id = id
        self.title = title
        self.masterCharacterDescription = masterCharacterDescription
        self.scenes = scenes
        self.createdAt = createdAt
        self.parentStoryID = parentStoryID
        self.chapters = chapters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        masterCharacterDescription = try container.decode(String.self, forKey: .masterCharacterDescription)
        scenes = try container.decode([StoryScene].self, forKey: .scenes)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        parentStoryID = try container.decodeIfPresent(UUID.self, forKey: .parentStoryID)
        chapters = try container.decodeIfPresent([Story].self, forKey: .chapters) ?? []
    }
}

struct GeneratedScene: Codable {
    var text: String
    var imagePrompt: String
}

struct GeneratedStory: Codable {
    var title: String
    var masterCharacterDescription: String
    var scenes: [GeneratedScene]
}
