import SwiftUI
import Combine

struct OnboardingView: View {
    @EnvironmentObject var storage: StorageService
    @Environment(\.colorScheme) private var colorScheme

    @State private var step: Step = .carousel
    @State private var childName = ""
    @State private var age = 6
    @State private var gender = ""
    @State private var location = ""
    @State private var carouselIndex = 0

    private let slideshowTimer = Timer.publish(every: 3.2, on: .main, in: .common).autoconnect()

    private let features: [OnboardingFeature] = [
        OnboardingFeature(
            title: "Sketch to Story",
            subtitle: "Bring Your Child’s Drawing to Life",
            imageName: "child_drawing"
        ),
        OnboardingFeature(
            title: "Read Aloud",
            subtitle: "Hear the Story Come to Life",
            imageName: "read_aloud"
        ),
        OnboardingFeature(
            title: "Story Chapters",
            subtitle: "Add New Chapters to the Tale",
            imageName: "story"
        )
    ]

    private enum Step {
        case childDetails
        case carousel
    }

    private var primaryButtonBackground: Color {
        colorScheme == .dark ? .white : .black
    }

    private var primaryButtonForeground: Color {
        colorScheme == .dark ? .black : .white
    }

    private var secondaryButtonBackground: Color {
        colorScheme == .dark ? .black : .white
    }

    private var secondaryButtonForeground: Color {
        colorScheme == .dark ? .white : .black
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .childDetails:
                    childDetailsView
                case .carousel:
                    carouselView
                }
            }
            .padding()
            .background(AppPalette.background(for: colorScheme).ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step == .childDetails {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            step = .carousel
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .accessibilityLabel("Back")
                    }
                }
            }
        }
    }

    private var childDetailsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Child Details")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            Text("Tell us about your little dreamer")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            Form {
                Section {
                    TextField("Name", text: $childName)

                    Stepper("Age: \(age)", value: $age, in: 2...12)

                    TextField("Gender (Optional)", text: $gender)
                    TextField("Location/Culture (Optional)", text: $location)
                }

                Section {
                    Button("Continue") {
                        let cleanedName = childName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let finalName = cleanedName.isEmpty ? "Little One" : cleanedName
                        storage.saveProfile(
                            Profile(
                                childName: finalName,
                                age: age,
                                gender: gender,
                                location: location
                            )
                        )
                        storage.completeOnboarding()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(primaryButtonBackground)
                    .foregroundStyle(primaryButtonForeground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .listRowBackground(Color.clear)

                Section {
                    Text("SketchStory uses Apple Intelligence. All your data is safe, stays offline, and never leaves your device.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 2)
                }
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppPalette.background(for: colorScheme).ignoresSafeArea())
    }

    private var carouselView: some View {
        VStack(spacing: 20) {
            Text("Welcome to SketchStory")
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)

            TabView(selection: $carouselIndex) {
                ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                    VStack(spacing: 16) {
                        GeometryReader { geometry in
                            ZStack {
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .fill(AppPalette.card(for: colorScheme))

                                Image(feature.imageName)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                    .clipped()
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: 300)
                    }
                    .padding(.horizontal, 10)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onReceive(slideshowTimer) { _ in
                withAnimation(.easeInOut(duration: 0.5)) {
                    carouselIndex = (carouselIndex + 1) % features.count
                }
            }

            Text(features[carouselIndex].subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            HStack(spacing: 8) {
                ForEach(features.indices, id: \.self) { index in
                    Circle()
                        .fill(index == carouselIndex ? primaryButtonBackground : .gray.opacity(0.35))
                        .frame(width: 8, height: 8)
                }
            }

            VStack(spacing: 12) {
                Button("Add your Child's Details") {
                    step = .childDetails
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(primaryButtonBackground)
                .foregroundStyle(primaryButtonForeground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button("Skip for now") {
                    storage.clearProfile()
                    storage.completeOnboarding()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(secondaryButtonBackground)
                .foregroundStyle(secondaryButtonForeground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(primaryButtonBackground.opacity(0.35), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Spacer(minLength: 0)
        }
    }
}

private struct OnboardingFeature {
    let title: String
    let subtitle: String
    let imageName: String
}
