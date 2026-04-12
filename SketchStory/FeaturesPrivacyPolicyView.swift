import SwiftUI
import SafariServices

struct FeaturesPrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var storage: StorageService

    @State private var showResetAlert = false
    @State private var showDetailedPrivacyPolicy = false

    private let detailedPolicyURL = URL(string: "https://ebullioscopic.github.io/SketchStory")!

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Features")
                            .font(.title2.weight(.bold))

                        FeaturePoint(
                            symbolName: "apple.intelligence",
                            title: "Smart storytelling, right on your device",
                            description: "SketchStory uses Apple Intelligence to turn your prompt into a warm, kid-friendly story. Your story is created on-device, so nothing needs to be sent out."
                        )

                        FeaturePoint(
                            symbolName: "text.quote",
                            title: "Text prompts become playful stories",
                            description: "Type your idea, and SketchStory helps shape it into a clear and engaging story for family reading time."
                        )

                        FeaturePoint(
                            symbolName: "camera.viewfinder",
                            title: "Image understanding with Visual Intelligence",
                            description: "SketchStory can understand a drawing or photo to inspire the story. The image stays stored locally on your device."
                        )
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Privacy Policy")
                            .font(.title2.weight(.bold))

                        Text("Your privacy comes first. SketchStory does not collect personal data, does not track usage, and does not upload your stories or images.")
                            .fixedSize(horizontal: false, vertical: true)

                        Text("SketchStory is designed to work completely offline. Stories and images are kept locally on your device.")
                            .fixedSize(horizontal: false, vertical: true)

                        Text("In short: what you create in SketchStory stays with you.")
                            .fontWeight(.semibold)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            showDetailedPrivacyPolicy = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "link")
                                Text("Read Detailed Privacy Policy")
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(.top, 4)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                    }

                    Divider()

                    Button(role: .destructive) {
                        showResetAlert = true
                    } label: {
                        Text("Reset All Generated Data")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .background(AppPalette.background(for: colorScheme))
            .navigationTitle("Features & Privacy")
            .sheet(isPresented: $showDetailedPrivacyPolicy) {
                InAppBrowserView(url: detailedPolicyURL)
                    .ignoresSafeArea()
            }
            .alert("Reset all generated data?", isPresented: $showResetAlert) {
                Button("Delete Everything", role: .destructive) {
                    storage.clearAllGeneratedData()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will permanently delete all generated stories and their saved images from this device.")
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct InAppBrowserView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) { }
}

private struct FeaturePoint: View {
    @Environment(\.colorScheme) private var colorScheme

    let symbolName: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 26, height: 26)
                .background(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
