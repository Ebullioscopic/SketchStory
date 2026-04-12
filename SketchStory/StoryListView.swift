import SwiftUI
import TipKit

struct StoryListView: View {
    @EnvironmentObject var storage: StorageService
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingCreateStory = false
    @State private var showingSettings = false
    @State private var pendingDeleteStoryID: UUID?
    @State private var pendingDeleteChapter: PendingChapterDelete?
    @State private var showingDeleteConfirmation = false
    @State private var showingChapterDeleteConfirmation = false
    @State private var expandedStoryIDs: Set<UUID> = []
    @State private var searchText = ""
    @State private var selectedReadingStoryID: UUID?
    @State private var pendingOpenStoryID: UUID?

    private let createStoryTip = CreateStoryButtonTip()

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var filteredStories: [Story] {
        guard !normalizedSearchText.isEmpty else { return storage.stories }

        return storage.stories.filter { story in
            story.title.lowercased().contains(normalizedSearchText)
            || story.chapters.contains(where: { $0.title.lowercased().contains(normalizedSearchText) })
        }
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(filteredStories) { story in
                    storyRow(for: story)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppPalette.background(for: colorScheme))
            .navigationTitle("My Stories")
            .searchable(text: $searchText, prompt: "Search stories and chapters")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingCreateStory = true
                        Task {
                            await CreateStoryButtonTip.createTapped.donate()
                        }
                    }) {
                        Image(systemName: "plus")
                    }
                    .popoverTip(createStoryTip, arrowEdge: .top)
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingCreateStory, onDismiss: {
                guard let pendingOpenStoryID else { return }
                selectedReadingStoryID = pendingOpenStoryID
                self.pendingOpenStoryID = nil
            }) {
                CreateStoryView(onStorySaved: { savedStory in
                    if let parentID = savedStory.parentStoryID {
                        expandedStoryIDs.insert(parentID)
                    }
                    searchText = ""
                    pendingOpenStoryID = savedStory.id
                    showingCreateStory = false
                })
            }
            .alert("Delete Story?", isPresented: $showingDeleteConfirmation, presenting: pendingDeleteStoryID) { storyID in
                Button("Delete", role: .destructive) {
                    storage.deleteStory(withID: storyID)
                    pendingDeleteStoryID = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDeleteStoryID = nil
                }
            } message: { _ in
                Text("This story and all its chapters will be permanently removed.")
            }
            .alert("Delete Chapter?", isPresented: $showingChapterDeleteConfirmation, presenting: pendingDeleteChapter) { chapter in
                Button("Delete", role: .destructive) {
                    storage.deleteChapter(chapterID: chapter.chapterID, from: chapter.parentStoryID)
                    pendingDeleteChapter = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDeleteChapter = nil
                }
            } message: { chapter in
                Text("Delete \"\(chapter.chapterTitle)\"? This chapter will be permanently removed.")
            }
        }
    }

    @ViewBuilder
    private func storyRow(for story: Story) -> some View {
        let visibleChapters = filteredChapters(for: story)

        if visibleChapters.isEmpty {
            storyLink(for: story)
                .listRowBackground(AppPalette.card(for: colorScheme))
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingDeleteStoryID = story.id
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
        } else {
            DisclosureGroup(isExpanded: expansionBinding(for: story.id)) {
                ForEach(visibleChapters) { chapter in
                    NavigationLink(
                        tag: chapter.id,
                        selection: $selectedReadingStoryID,
                        destination: { StoryReaderView(story: chapter.story) },
                        label: {
                        HStack(spacing: 10) {
                            rowThumbnail(for: chapter.story)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(chapter.displayTitle)
                                    .font(.subheadline.weight(.semibold))
                                Text(chapter.createdAt, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.leading, 6)
                    })
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !chapter.isRootChapter {
                            Button(role: .destructive) {
                                pendingDeleteChapter = PendingChapterDelete(
                                    parentStoryID: chapter.parentStoryID,
                                    chapterID: chapter.id,
                                    chapterTitle: chapter.displayTitle
                                )
                                showingChapterDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            } label: {
                storyLabel(for: story)
            }
            .listRowBackground(AppPalette.card(for: colorScheme))
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    pendingDeleteStoryID = story.id
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func storyLink(for story: Story) -> some View {
        NavigationLink(
            tag: story.id,
            selection: $selectedReadingStoryID,
            destination: { StoryReaderView(story: story) },
            label: {
            storyLabel(for: story)
        })
    }

    private func storyLabel(for story: Story) -> some View {
        HStack(spacing: 10) {
            rowThumbnail(for: story)

            VStack(alignment: .leading, spacing: 2) {
                Text(story.title)
                    .font(.headline)
                Text(story.createdAt, style: .date)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                if !story.chapters.isEmpty {
                    let totalChapters = story.chapters.count + 1
                    Text("\(totalChapters) chapter\(totalChapters == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func rowThumbnail(for story: Story) -> some View {
        if let imageData = story.scenes.first?.imageData,
           let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 44, height: 56)
                .overlay(
                    Image(systemName: "photo")
                        .font(.caption)
                        .foregroundColor(.secondary)
                )
        }
    }

    private func filteredChapters(for story: Story) -> [StoryChapterItem] {
        guard !story.chapters.isEmpty else { return [] }

        var chapterItems: [StoryChapterItem] = [
            StoryChapterItem(
                id: story.id,
                story: story,
                parentStoryID: story.id,
                isRootChapter: true,
                displayTitle: "Chapter 1: \(story.title)",
                createdAt: story.createdAt
            )
        ]

        chapterItems.append(
            contentsOf: story.chapters.enumerated().map { index, chapter in
                let chapterNumber = index + 2
                return StoryChapterItem(
                    id: chapter.id,
                    story: chapter,
                    parentStoryID: story.id,
                    isRootChapter: false,
                    displayTitle: chapter.title.lowercased().hasPrefix("chapter ") ? chapter.title : "Chapter \(chapterNumber): \(chapter.title)",
                    createdAt: chapter.createdAt
                )
            }
        )

        guard !normalizedSearchText.isEmpty else { return chapterItems }

        return chapterItems.filter {
            $0.displayTitle.lowercased().contains(normalizedSearchText)
        }
    }

    private func expansionBinding(for storyID: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedStoryIDs.contains(storyID) || !normalizedSearchText.isEmpty },
            set: { isExpanded in
                if isExpanded {
                    expandedStoryIDs.insert(storyID)
                } else {
                    expandedStoryIDs.remove(storyID)
                }
            }
        )
    }
}

private struct StoryChapterItem: Identifiable {
    let id: UUID
    let story: Story
    let parentStoryID: UUID
    let isRootChapter: Bool
    let displayTitle: String
    let createdAt: Date
}

private struct PendingChapterDelete: Identifiable {
    let parentStoryID: UUID
    let chapterID: UUID
    let chapterTitle: String

    var id: UUID { chapterID }
}
