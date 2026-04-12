import Foundation
import Combine
import SwiftUI

class StorageService: ObservableObject {
    @Published var hasCompletedOnboarding: Bool = false
    @Published var profile: Profile?
    @Published var stories: [Story] = []
    @Published var settings: AppSettings = AppSettings()
    
    private let onboardingKey = "sketchstory_onboarding_complete"
    private let profileKey = "sketchstory_profile"
    private let storiesKey = "sketchstory_stories"
    private let settingsKey = "sketchstory_settings"
    
    init() {
        loadOnboardingState()
        loadProfile()
        loadSettings()
        loadStories()
        normalizeChapterTitlesIfNeeded()
        removeLegacyPresetStoriesIfPresent()
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: onboardingKey)
    }

    func loadOnboardingState() {
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: onboardingKey)
    }
    
    func saveProfile(_ profile: Profile) {
        self.profile = profile
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: profileKey)
        }
    }
    
    func loadProfile() {
        if let data = UserDefaults.standard.data(forKey: profileKey),
           let profile = try? JSONDecoder().decode(Profile.self, from: data) {
            self.profile = profile
        }
    }

    func clearProfile() {
        profile = nil
        UserDefaults.standard.removeObject(forKey: profileKey)
    }

    func saveSettings(_ settings: AppSettings) {
        self.settings = settings
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = settings
        }
    }
    
    @discardableResult
    func saveStory(_ story: Story) -> Story {
        var rootStory = story
        rootStory.parentStoryID = nil
        stories.append(rootStory)
        saveStories()
        return rootStory
    }

    @discardableResult
    func addChapter(_ chapter: Story, to parentStoryID: UUID) -> Story {
        guard let parentIndex = stories.firstIndex(where: { $0.id == parentStoryID }) else { return chapter }

        var chapterToSave = chapter
        chapterToSave.id = UUID()
        chapterToSave.parentStoryID = parentStoryID
        stories[parentIndex].chapters.append(chapterToSave)
        saveStories()
        return chapterToSave
    }
    
    func deleteStory(at offsets: IndexSet) {
        stories.remove(atOffsets: offsets)
        saveStories()
    }

    func deleteStory(withID storyID: UUID) {
        guard let index = stories.firstIndex(where: { $0.id == storyID }) else { return }
        stories.remove(at: index)
        saveStories()
    }

    func deleteChapter(chapterID: UUID, from parentStoryID: UUID) {
        guard let parentIndex = stories.firstIndex(where: { $0.id == parentStoryID }) else { return }

        let previousCount = stories[parentIndex].chapters.count
        stories[parentIndex].chapters.removeAll { $0.id == chapterID }

        guard stories[parentIndex].chapters.count != previousCount else { return }
        saveStories()
    }
    
    private func saveStories() {
        if let data = try? JSONEncoder().encode(stories) {
            UserDefaults.standard.set(data, forKey: storiesKey)
        }
    }
    
    func loadStories() {
        if let data = UserDefaults.standard.data(forKey: storiesKey),
           let stories = try? JSONDecoder().decode([Story].self, from: data) {
            self.stories = stories
        } else {
            self.stories = []
        }
    }
    
    func updateStory(_ story: Story) {
        if let index = stories.firstIndex(where: { $0.id == story.id }) {
            stories[index] = story
            saveStories()
        }
    }

    func clearAllGeneratedData() {
        stories = []
        UserDefaults.standard.removeObject(forKey: storiesKey)
    }

    private func removeLegacyPresetStoriesIfPresent() {
        let presetTitles: Set<String> = [
            "Milo and the Moonlight Library",
            "Asha’s Star Pillow Adventure"
        ]

        let filteredStories = stories.filter { !presetTitles.contains($0.title) }
        guard filteredStories.count != stories.count else { return }

        stories = filteredStories
        saveStories()
    }

    private func normalizeChapterTitlesIfNeeded() {
        var didChange = false

        for storyIndex in stories.indices {
            guard !stories[storyIndex].chapters.isEmpty else { continue }

            for chapterIndex in stories[storyIndex].chapters.indices {
                let expectedNumber = chapterIndex + 2
                let currentTitle = stories[storyIndex].chapters[chapterIndex].title
                let suffix = chapterTitleSuffix(from: currentTitle)
                let normalizedTitle = "Chapter \(expectedNumber): \(suffix)"

                if currentTitle != normalizedTitle {
                    stories[storyIndex].chapters[chapterIndex].title = normalizedTitle
                    didChange = true
                }
            }
        }

        if didChange {
            saveStories()
        }
    }

    private func chapterTitleSuffix(from title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseTitle: String

        if let colonIndex = trimmed.firstIndex(of: ":") {
            let suffix = trimmed[trimmed.index(after: colonIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            baseTitle = suffix.isEmpty ? trimmed : suffix
        } else {
            baseTitle = trimmed
        }

        let withoutChapterWords = baseTitle
            .replacingOccurrences(
                of: "(?i)\\bchapter\\s*\\d+\\b\\s*[:\\-–—]?\\s*",
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let cleaned = withoutChapterWords
            .replacingOccurrences(of: "^[\\s:,.!\\-–—]+|[\\s:,.!\\-–—]+$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned.isEmpty ? "Untitled" : cleaned
    }
}
