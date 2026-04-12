import SwiftUI
import PhotosUI
import TipKit
import os
import UIKit

struct CreateStoryView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var storage: StorageService
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var description = ""
    @State private var experience = ""
    @State private var moral = "Kindness"
    @State private var languageTags = ["very simple language", "bedtime calm tone"]
    
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var showImageSourceDialog = false
    @State private var showPhotoPicker = false
    @State private var showCameraPicker = false
    @State private var showCameraUnavailableAlert = false
    @State private var drawingReferenceDescription = ""
    @State private var visualProcessingContext: VisualProcessingContext?
    @State private var isLanguageStyleExpanded = false
    @State private var isBottomGenerateVisible = false
    @State private var hasEditedInputs = false
    
    @State private var isGenerating = false
    @State private var generatedStory: Story?
    @State private var errorMessage = ""
    @State private var showErrorAlert = false
    @State private var creationMode: CreationMode = .newStory
    @State private var selectedParentStoryID: UUID?

    private let logger = Logger(subsystem: "SketchStory", category: "CreateStory")
    private let storyTypeTip = StoryTypeSelectionTip()
    var onStorySaved: ((Story) -> Void)? = nil
    
    let morals = ["Kindness", "Honesty", "Sharing", "Bravery", "Patience"]
    let availableTags = ["very simple language", "short sentences", "bedtime calm tone"]

    private enum CreationMode: String, CaseIterable, Identifiable {
        case newStory = "New Story"
        case newChapter = "New Chapter"

        var id: String { rawValue }
    }

    private var screenBackground: Color {
        AppPalette.background(for: colorScheme)
    }

    private var rowBackground: Color {
        AppPalette.card(for: colorScheme)
    }

    private var trimmedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedParentStory: Story? {
        guard let selectedParentStoryID else { return nil }
        return storage.stories.first(where: { $0.id == selectedParentStoryID })
    }

    private var selectedStoryName: String {
        selectedParentStory?.title ?? "Select a story"
    }

    private var canCreateChapter: Bool {
        !storage.stories.isEmpty
    }

    private var canGenerate: Bool {
        switch creationMode {
        case .newStory:
            return selectedImage != nil || !trimmedDescription.isEmpty
        case .newChapter:
            return selectedParentStory != nil
        }
    }

    private var shouldShowInputError: Bool {
        hasEditedInputs && !canGenerate
    }

    private var primaryActionBackground: Color {
        colorScheme == .dark ? .white : .black
    }

    private var primaryActionForeground: Color {
        colorScheme == .dark ? .black : .white
    }
    
    var body: some View {
        NavigationView {
            Form {
                if canCreateChapter {
                    creationModeSection
                }
                if creationMode == .newChapter {
                    chapterParentSection
                }
                drawingSection
                storyDetailsSection
                languageStyleSection
                generateSection
            }
            .scrollContentBackground(.hidden)
            .background(screenBackground.ignoresSafeArea())
            .navigationTitle(creationMode == .newStory ? "New Story" : "New Chapter")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }

                if !isBottomGenerateVisible && !isGenerating {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Generate") {
                            generateStory()
                        }
                        .disabled(isGenerating || !canGenerate)
                    }
                }
            }
            .sheet(item: $generatedStory) { story in
                StoryPreviewView(
                    story: story,
                    referenceImage: selectedImage,
                    onSaveStory: { previewStory in
                        if let parentStoryID = previewStory.parentStoryID {
                            return storage.addChapter(previewStory, to: parentStoryID)
                        } else {
                            return storage.saveStory(previewStory)
                        }
                    },
                    onStorySaved: { savedStory in
                        self.generatedStory = nil
                        self.onStorySaved?(savedStory)
                        DispatchQueue.main.async {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                )
            }
            .alert("Couldn’t Generate Story", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .alert("Camera Unavailable", isPresented: $showCameraUnavailableAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("This device does not have a camera available.")
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedItem, matching: .images)
            .sheet(isPresented: $showCameraPicker) {
                CameraImagePicker { image in
                    handlePickedImage(image)
                }
            }
            .confirmationDialog(
                "Add Drawing",
                isPresented: $showImageSourceDialog,
                titleVisibility: .visible
            ) {
                Button("Photos") {
                    showPhotoPicker = true
                }
                Button("Camera") {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        showCameraPicker = true
                    } else {
                        showCameraUnavailableAlert = true
                    }
                }
                Button("Cancel", role: .cancel) { }
            }
            .onPreferenceChange(GenerateVisibilityPreferenceKey.self) { value in
                isBottomGenerateVisible = value
            }
            .onChange(of: selectedItem) { _, newItem in
                hasEditedInputs = true

                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        selectedImage = uiImage
                        await analyzeUploadedDrawing(uiImage)
                    }
                }
            }
            .onChange(of: description) { _, _ in
                hasEditedInputs = true
            }
            .onChange(of: creationMode) { _, newMode in
                hasEditedInputs = true
                if newMode == .newStory {
                    selectedParentStoryID = nil
                }
            }
            .onChange(of: storage.stories.count) { _, newCount in
                if newCount == 0 {
                    creationMode = .newStory
                    selectedParentStoryID = nil
                }
            }
            .overlay {
                if isGenerating {
                    StoryGenerationOverlayView()
                    .transition(.opacity)
                }
            }
        }
    }

    private var drawingSection: some View {
        Section(header: Text("Drawing")) {
            drawingPickerContent

            Text("Add a sketch or photo so SketchStory can personalize scenes, style, and details from your child’s artwork.")
                .font(.caption)
                .foregroundColor(.secondary)

            if shouldShowInputError {
                Text("Add a drawing or enter a story description to enable Generate.")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .listRowBackground(rowBackground)
    }

    private var creationModeSection: some View {
        Section("Create Type") {
            Picker("Story Type", selection: $creationMode) {
                ForEach(CreationMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .popoverTip(storyTypeTip, arrowEdge: .top)
        }
        .listRowBackground(rowBackground)
    }

    private var chapterParentSection: some View {
        Section("Parent Story") {
            Picker("Story", selection: $selectedParentStoryID) {
                Text("Select a story").tag(UUID?.none)
                ForEach(storage.stories) { story in
                    Text(story.title).tag(Optional(story.id))
                }
            }
            .pickerStyle(.menu)

            if selectedParentStory == nil {
                Text("Choose an existing story to generate a connected chapter.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("New chapter will be added under: \(selectedStoryName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .listRowBackground(rowBackground)
    }

    @ViewBuilder
    private var drawingPickerContent: some View {
        if let image = selectedImage {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button {
                    showImageSourceDialog = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(Color.black.opacity(0.8), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(10)
            }
        } else {
            Button {
                showImageSourceDialog = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "photo.badge.plus")
                    Text("Select a drawing")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(primaryActionBackground)
            .foregroundStyle(primaryActionForeground)
        }
    }

    private var storyDetailsSection: some View {
        Section(
            header: Text(creationMode == .newStory ? "Story Details" : "Chapter Details"),
            footer: Text("Share short context to make the story feel personal—for example favorite characters, today’s event, or the mood you want.")
        ) {
            TextField("Story description (optional)", text: $description, axis: .vertical)
                .lineLimit(3...6)
            TextField("Daily experience to include (optional)", text: $experience, axis: .vertical)
                .lineLimit(3...6)

            if shouldShowInputError {
                Text(
                    creationMode == .newStory
                    ? "If no drawing is uploaded, add a short description to continue."
                    : "Select a parent story to continue."
                )
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Picker("Moral Theme", selection: $moral) {
                ForEach(morals, id: \.self) {
                    Text($0)
                }
            }
        }
        .listRowBackground(rowBackground)
    }

    private var languageStyleSection: some View {
        Section {
            DisclosureGroup(
                isExpanded: $isLanguageStyleExpanded,
                content: {
                    ForEach(availableTags, id: \.self) { tag in
                        Toggle(tag, isOn: Binding(
                            get: { languageTags.contains(tag) },
                            set: { isSelected in
                                if isSelected {
                                    if !languageTags.contains(tag) {
                                        languageTags.append(tag)
                                    }
                                } else {
                                    languageTags.removeAll(where: { $0 == tag })
                                }
                            }
                        ))
                    }
                },
                label: {
                    HStack {
                        Text("Language Style")
                        Spacer()
                        Text("\(languageTags.count) selected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            )
        }
        .listRowBackground(rowBackground)
    }

    private var generateSection: some View {
        Section {
            CreateStoryGenerateButton(
                isGenerating: isGenerating,
                baseColor: primaryActionBackground,
                foregroundColor: primaryActionForeground,
                action: generateStory
            )
            .listRowInsets(EdgeInsets())
            .padding(.vertical, 6)
            .disabled(isGenerating || !canGenerate)
            .background(generateVisibilityReader)
        }
        .listRowBackground(Color.clear)
    }

    private var generateVisibilityReader: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: GenerateVisibilityPreferenceKey.self,
                    value: UIScreen.main.bounds.intersects(proxy.frame(in: .global))
                )
        }
    }
    
    func generateStory() {
        let profile = storage.profile ?? Profile(childName: "Little One", age: 6, gender: "", location: "")
        isGenerating = true
        
        Task {
            do {
                let service = StoryGenerationService()
                let story: Story

                if creationMode == .newChapter, let parentStory = selectedParentStory {
                    let chapterNumber = parentStory.chapters.count + 2
                    let continuationSource = parentStory.chapters.last ?? parentStory
                    let previousScenesSummary = continuationSource.scenes.map(\.text).joined(separator: " ")
                    let chapterGuidance = """
                    Continue the existing story titled \"\(parentStory.title)\".
                    Keep the same world, tone, and character consistency using this base character description: \(parentStory.masterCharacterDescription).
                    Existing chapter count: \(parentStory.chapters.count).
                    This should read like chapter \(chapterNumber) and continue naturally from the most recent chapter.
                    Continue directly after: \(continuationSource.title).
                    Previous chapter context: \(previousScenesSummary)
                    """

                    let chapter = try await service.generateStory(
                        profile: profile,
                        drawing: selectedImage,
                        drawingReferenceDescription: drawingReferenceDescription,
                        visualProcessingContext: visualProcessingContext,
                        description: chapterGuidance + "\n" + description,
                        experience: experience,
                        moral: moral,
                        languageTags: languageTags
                    )

                    let cleanedChapterTitle = sanitizedGeneratedChapterTitle(chapter.title)

                    story = Story(
                        title: "Chapter \(chapterNumber): \(cleanedChapterTitle)",
                        masterCharacterDescription: chapter.masterCharacterDescription,
                        scenes: chapter.scenes,
                        createdAt: chapter.createdAt,
                        parentStoryID: parentStory.id,
                        chapters: []
                    )
                } else {
                    story = try await service.generateStory(
                        profile: profile,
                        drawing: selectedImage,
                        drawingReferenceDescription: drawingReferenceDescription,
                        visualProcessingContext: visualProcessingContext,
                        description: description,
                        experience: experience,
                        moral: moral,
                        languageTags: languageTags
                    )
                }
                
                await MainActor.run {
                    self.generatedStory = story
                    self.isGenerating = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "SketchStory couldn’t reach Apple Intelligence models on this device right now. Please verify Apple Intelligence is enabled and model assets are available, then try again."
                    self.showErrorAlert = true
                    self.isGenerating = false
                }
            }
        }
    }

    private func handlePickedImage(_ image: UIImage) {
        hasEditedInputs = true
        selectedImage = image

        Task {
            await analyzeUploadedDrawing(image)
        }
    }

    @MainActor
    private func analyzeUploadedDrawing(_ image: UIImage) async {
        let service = StoryGenerationService()
        let context = await service.extractVisualProcessingContext(from: image)
        drawingReferenceDescription = context.drawingReferenceDescription
        visualProcessingContext = context

        logger.info("Uploaded drawing detailed reference: \(context.drawingReferenceDescription, privacy: .public)")
        logger.info("Uploaded visual extraction context: \(context.mergedPromptContext, privacy: .public)")
        print("[SketchStory] Uploaded drawing detailed reference: \(context.drawingReferenceDescription)")
        print("[SketchStory] Uploaded visual extraction context: \(context.mergedPromptContext)")
    }

    private func sanitizedGeneratedChapterTitle(_ title: String) -> String {
        let withoutChapterWords = title
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

private struct CameraImagePicker: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraImagePicker

        init(parent: CameraImagePicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) { }
}

private struct GenerateVisibilityPreferenceKey: PreferenceKey {
    static let defaultValue: Bool = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

private struct CreateStoryGenerateButton: View {
    let isGenerating: Bool
    let baseColor: Color
    let foregroundColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isGenerating {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(foregroundColor)
                    Text("Generating...")
                        .fontWeight(.semibold)
                } else {
                    Image(systemName: "sparkles")
                        .imageScale(.large)
                    Text("Generate Story")
                        .fontWeight(.semibold)
                }
            }
            .foregroundStyle(foregroundColor)
            .padding()
            .frame(height: 56)
            .frame(maxWidth: .infinity)
            .background(
                AnimatedMeshView()
                    .mask(
                        RoundedRectangle(cornerRadius: 28)
                            .stroke(lineWidth: 16)
                            .blur(radius: 8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28)
                            .stroke(.white, lineWidth: 3)
                            .blur(radius: 2)
                            .blendMode(.overlay)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28)
                            .stroke(.white, lineWidth: 1)
                            .blur(radius: 1)
                            .blendMode(.overlay)
                    )
            )
            .background(baseColor)
            .cornerRadius(28)
            .background(
                RoundedRectangle(cornerRadius: 28)
                    .stroke(baseColor.opacity(0.5), lineWidth: 1)
            )
        }
    }
}
