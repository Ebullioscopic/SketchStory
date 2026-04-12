import Foundation
import AppIntents
#if canImport(VisualIntelligence)
import VisualIntelligence
#endif

struct StoryVisualSearchEntity: AppEntity, Identifiable {
    typealias ID = String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Story")
    }

    static let defaultQuery = StoryVisualEntityQuery()

    let id: String
    let title: String
    let subtitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: title),
            subtitle: LocalizedStringResource(stringLiteral: subtitle)
        )
    }
}

struct StoryVisualEntityQuery: EntityQuery {
    func entities(for identifiers: [StoryVisualSearchEntity.ID]) async throws -> [StoryVisualSearchEntity] {
        let stories = loadStories()
        let selected = stories.filter { identifiers.contains($0.id.uuidString) }
        return selected.map { story in
            StoryVisualSearchEntity(
                id: story.id.uuidString,
                title: story.title,
                subtitle: story.masterCharacterDescription
            )
        }
    }

    func suggestedEntities() async throws -> [StoryVisualSearchEntity] {
        let stories = loadStories().prefix(25)
        return stories.map { story in
            StoryVisualSearchEntity(
                id: story.id.uuidString,
                title: story.title,
                subtitle: story.masterCharacterDescription
            )
        }
    }

    private func loadStories() -> [Story] {
        guard
            let data = UserDefaults.standard.data(forKey: "sketchstory_stories"),
            let stories = try? JSONDecoder().decode([Story].self, from: data)
        else {
            return []
        }

        return stories
    }
}

