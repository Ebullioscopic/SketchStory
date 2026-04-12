import SwiftUI
import ImagePlayground
import FoundationModels
import TipKit

struct StoryPreviewView: View {
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var storage: StorageService
    
    @State var story: Story
    var referenceImage: UIImage?
    var onSaveStory: ((Story) -> Story)?
    var onStorySaved: ((Story) -> Void)?
    
    @State private var isGeneratingImages = false
    @State private var showingDiscardConfirmation = false

    private let saveTip = StoryPreviewSaveTip()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    TextField("Story Title", text: $story.title)
                        .font(.largeTitle)
                        .textFieldStyle(.roundedBorder)
                    
                    ForEach(story.scenes.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 12) {
                            if index % 3 == 0 {
                                HStack(alignment: .top, spacing: 12) {
                                    pageImageView(for: index)
                                    sceneEditor(index: index)
                                }
                            } else if index % 3 == 1 {
                                HStack(alignment: .top, spacing: 12) {
                                    sceneEditor(index: index)
                                    pageImageView(for: index)
                                }
                            } else {
                                HStack {
                                    Spacer(minLength: 0)
                                    pageImageView(for: index)
                                }
                                sceneEditor(index: index)
                            }

                            Text("Page \(index + 1)")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(AppPalette.card(for: colorScheme))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color(.separator), lineWidth: 0.6)
                        )
                        .padding(.bottom)
                    }
                }
                .padding()
            }
            .background(AppPalette.background(for: colorScheme).ignoresSafeArea())
            .navigationTitle("Preview")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showingDiscardConfirmation = true
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let savedStory: Story
                        if let onSaveStory {
                            savedStory = onSaveStory(story)
                        } else {
                            storage.saveStory(story)
                            savedStory = story
                        }
                        onStorySaved?(savedStory)
                        presentationMode.wrappedValue.dismiss()
                    }
                    .disabled(isGeneratingImages)
                    .popoverTip(saveTip, arrowEdge: .top)
                }
            }
            .onAppear {
                generateImages()
            }
            .alert("Discard Generated Story?", isPresented: $showingDiscardConfirmation) {
                Button("Discard", role: .destructive) {
                    presentationMode.wrappedValue.dismiss()
                }
                Button("Keep Editing", role: .cancel) { }
            } message: {
                Text("If you cancel now, the generated story and images will not be saved.")
            }
        }
    }
    
    func generateImages() {
        isGeneratingImages = true
        
        Task {
            let service = StoryGenerationService()

            let availability = ImagePlaygroundCapability.availability
            if availability == .available {
                print("Image Playground is currently: \(availability)")
            } else {
                print("Image Playground is currently: \(availability)")

                await MainActor.run {
                    for index in story.scenes.indices {
                        story.scenes[index].imageData = service.fallbackImageData(
                            for: story.scenes[index],
                            masterDescription: story.masterCharacterDescription
                        )
                    }
                    isGeneratingImages = false
                }
                return
            }
            
            for index in story.scenes.indices {
                do {
                    if let imageData = try await service.generateImage(
                        for: story.scenes[index],
                        masterDescription: story.masterCharacterDescription,
                        referenceImage: referenceImage
                    ) {
                        await MainActor.run {
                            story.scenes[index].imageData = imageData
                        }
                    }
                } catch {
                    print("Error generating image for scene \(index): \(error)")
                }
            }
            
            await MainActor.run {
                isGeneratingImages = false
            }
        }
    }

    @ViewBuilder
    private func pageImageView(for index: Int) -> some View {
        if let data = story.scenes[index].imageData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 130, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 130, height: 180)
                .overlay {
                    if isGeneratingImages {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.clear)
                            .aiGlow(
                                innerPadding: 0,
                                cornerRadius: 10,
                                useBackground: false,
                                vibrancy: .normal
                            )
                            .showGenerationGlow(true)
                            .padding(1)
                    }
                }
                .overlay(
                    Text(isGeneratingImages ? "Generating..." : "Image")
                        .font(.caption)
                        .foregroundColor(.secondary)
                )
        }
    }

    private func sceneEditor(index: Int) -> some View {
        TextEditor(text: $story.scenes[index].text)
            .frame(minHeight: 180)
            .padding(8)
            .background(AppPalette.background(for: colorScheme).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
